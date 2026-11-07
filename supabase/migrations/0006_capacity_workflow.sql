-- ===== 교육 정원 =====
-- 신청(applied)·확정(confirmed) 인원이 정원에 차면 더 받지 않는다. 동시 신청은 과정 행 잠금으로 직렬화.
create function check_course_capacity() returns trigger
language plpgsql security definer set search_path = public as $$
declare cap int; taken int;
begin
  if new.status not in ('applied', 'confirmed') then return new; end if;
  if tg_op = 'UPDATE' and old.status in ('applied', 'confirmed') then return new; end if;  -- 신청→확정은 자리 이동 없음
  select capacity into cap from courses where id = new.course_id for update;
  if cap is null then return new; end if;
  select count(*) into taken from course_applications
  where course_id = new.course_id and status in ('applied', 'confirmed') and id <> new.id;
  if taken >= cap then raise exception '정원이 마감되었습니다'; end if;
  return new;
end $$;
create trigger course_capacity before insert or update on course_applications
  for each row execute function check_course_capacity();

-- 과정별 신청 인원 (개인 정보 없이 숫자만 공개)
create function course_seats() returns table (course_id bigint, taken bigint)
language sql stable security definer set search_path = public as $$
  select course_id, count(*) from course_applications
  where status in ('applied', 'confirmed') group by course_id;
$$;
revoke all on function course_seats() from public, anon;
grant execute on function course_seats() to authenticated;

-- ===== 대회 삭제 보호 =====
create function guard_competition_delete() returns trigger language plpgsql as $$
begin
  if exists (select 1 from applications a join recruitments r on r.id = a.recruitment_id
             where r.competition_id = old.id and a.completed_at is not null) then
    raise exception '활동완료 기록이 있는 대회는 삭제할 수 없습니다';
  end if;
  return old;
end $$;
create trigger competitions_delete_guard before delete on competitions
  for each row execute function guard_competition_delete();

-- ===== 처리할 사람에게 가는 알림 =====
create function notify_admins(p_kind text, p_title text, p_body text) returns void
language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, title, body)
  select id, p_kind, p_title, p_body from profiles where role = 'admin';
$$;
revoke all on function notify_admins(text, text, text) from public, anon, authenticated;

-- 새 지원자 → 대회관계자
create function notify_new_applicant() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, kind, title, body)
  select c.organizer_id, 'new_applicant', '새 심판 지원',
         p.name || ' · ' || c.name || ' ' || r.position
  from recruitments r join competitions c on c.id = r.competition_id, profiles p
  where r.id = new.recruitment_id and p.id = new.user_id and c.organizer_id is not null;
  return new;
end $$;
create trigger applications_new_notify after insert on applications
  for each row execute function notify_new_applicant();

-- 기관 승인 요청 → 관리자
create function notify_org_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.role = 'organizer' and new.org_status = 'pending'
     and (tg_op = 'INSERT' or old.org_status is distinct from 'pending' or old.role <> 'organizer') then
    perform notify_admins('org_request', '기관 승인 요청',
      coalesce(new.organization, '') || ' · ' || new.name || ' 님이 대회관계자 승인을 기다립니다.');
  end if;
  return new;
end $$;
create trigger profiles_org_request after insert or update on profiles
  for each row execute function notify_org_request();

-- 자격 확인 요청 → 관리자
create function notify_qual_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform notify_admins('qual_request', '자격 확인 요청',
    (select name from profiles where id = new.user_id) || ' · ' || new.name || coalesce(' ' || new.grade, ''));
  return new;
end $$;
create trigger qualifications_request after insert on qualifications
  for each row execute function notify_qual_request();

-- ===== 자격증 사본 =====
alter table qualifications add column file_path text;  -- storage: quals/<uid>/...

-- 그 심판이 지원한 공고의 대회관계자인가
create function views_referee(p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from applications a where a.user_id = p_user and owns_recruitment(a.recruitment_id));
$$;

create policy p_files_qual_insert on storage.objects for insert with check (
  bucket_id = 'files' and name like 'quals/' || auth.uid()::text || '/%');

-- 읽기 권한 재정의: 브리핑은 선발자·관계자, 자격증 사본은 본인·관리자·지원받은 관계자만
drop policy p_files_read on storage.objects;
create policy p_files_read on storage.objects for select using (
  bucket_id = 'files' and auth.uid() is not null and (
    is_admin()
    or (name like 'briefings/%' and split_part(name, '/', 2) ~ '^[0-9]+$' and (
          is_selected_for(split_part(name, '/', 2)::bigint) or owns_competition(split_part(name, '/', 2)::bigint)))
    or (name like 'quals/%' and (
          split_part(name, '/', 2) = auth.uid()::text
          or (split_part(name, '/', 2) ~ '^[0-9a-f-]{36}$' and views_referee(split_part(name, '/', 2)::uuid))))
    or (name not like 'briefings/%' and name not like 'quals/%')
  ));
