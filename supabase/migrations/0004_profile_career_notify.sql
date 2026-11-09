-- 심판 프로필 확장
alter table profiles
  add column if not exists region text,        -- 활동 지역
  add column if not exists sport text,         -- 주 종목
  add column if not exists bio text,           -- 소개·경력 요약
  add column if not exists avatar_path text;   -- storage: avatars/<uid>/...

-- 심판 경력 요약: 본인 / 관리자 / 그 심판이 지원한 공고의 대회관계자만 조회
create or replace function referee_summary(p_user uuid) returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not (p_user = auth.uid() or is_admin()
          or exists (select 1 from applications a where a.user_id = p_user and owns_recruitment(a.recruitment_id))) then
    raise exception 'forbidden';
  end if;
  return json_build_object(
    'applied',   (select count(*) from applications where user_id = p_user and status <> 'cancelled'),
    'selected',  (select count(*) from applications where user_id = p_user and status = 'selected'),
    'completed', (select count(*) from applications where user_id = p_user and completed_at is not null),
    'absent',    (select count(*) from applications where user_id = p_user and attendance = 'absent'),
    'by_position', (select coalesce(json_object_agg(position, n), '{}') from (
        select r.position, count(*) n from applications a join recruitments r on r.id = a.recruitment_id
        where a.user_id = p_user and a.completed_at is not null group by r.position) t),
    'recent', (select coalesce(json_agg(t), '[]') from (
        select c.name, c.starts_on, c.venue, r.position from applications a
        join recruitments r on r.id = a.recruitment_id join competitions c on c.id = r.competition_id
        where a.user_id = p_user and a.completed_at is not null
        order by c.starts_on desc limit 5) t)
  );
end $$;
revoke all on function referee_summary(uuid) from public, anon;
grant execute on function referee_summary(uuid) to authenticated;

-- 프로필 사진: 본인 폴더(avatars/<uid>/)에만 업로드·삭제
drop policy if exists p_files_avatar_insert on storage.objects;
create policy p_files_avatar_insert on storage.objects for insert with check (
  bucket_id = 'files' and name like 'avatars/' || auth.uid()::text || '/%');
drop policy if exists p_files_avatar_delete on storage.objects;
create policy p_files_avatar_delete on storage.objects for delete using (
  bucket_id = 'files' and name like 'avatars/' || auth.uid()::text || '/%');

-- 선발 결과 알림 (선발 / 예비 / 미선발로 바뀔 때)
create or replace function notify_application_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare cname text; pos text;
begin
  if new.status is not distinct from old.status or new.status not in ('selected', 'reserve', 'rejected') then
    return new;
  end if;
  select c.name, r.position into cname, pos
  from recruitments r join competitions c on c.id = r.competition_id where r.id = new.recruitment_id;
  insert into notifications (user_id, kind, title, body)
  values (new.user_id, 'selection',
    case new.status when 'selected' then '심판 선발 안내' when 'reserve' then '예비 심판 안내' else '선발 결과 안내' end,
    cname || ' · ' || pos || ' — ' || case new.status
      when 'selected' then '선발되었습니다. 브리핑 자료를 확인하세요.'
      when 'reserve' then '예비 심판으로 지정되었습니다.'
      else '이번 대회에는 선발되지 않았습니다.' end);
  return new;
end $$;
create or replace trigger applications_notify after update on applications
  for each row execute function notify_application_change();

-- 자격 승인·반려 알림
create or replace function notify_qualification_change() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
    insert into notifications (user_id, kind, title, body)
    values (new.user_id, 'qualification',
      case new.status when 'approved' then '자격 승인 완료' else '자격 반려 안내' end,
      new.name || coalesce(' ' || new.grade, '') || case new.status
        when 'approved' then ' 자격이 승인되었습니다.' else ' 자격이 반려되었습니다. 내용을 확인 후 다시 등록하세요.' end);
  end if;
  return new;
end $$;
create or replace trigger qualifications_notify after update on qualifications
  for each row execute function notify_qualification_change();

-- 브리핑 자료 등록 시 선발된 심판에게 알림
create or replace function notify_briefing() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, kind, title, body)
  select distinct a.user_id, 'briefing', '브리핑 자료 등록', c.name || ' — ' || new.title
  from applications a join recruitments r on r.id = a.recruitment_id
  join competitions c on c.id = r.competition_id
  where r.competition_id = new.competition_id and a.status = 'selected';
  return new;
end $$;
create or replace trigger briefings_notify after insert on briefings
  for each row execute function notify_briefing();
