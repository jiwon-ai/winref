-- 현장 QR 출석 · 활동확인서 진위 확인 · 성과 리포트 · 처리 기록(감사 로그) · 오류 수집
-- 여러 번 실행해도 안전.

-- ============================================================
-- 0. 처리 기록 (감사 로그) — 다른 기능들이 여기에 기록하므로 먼저 만든다
-- ============================================================
create table if not exists audit_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_id    uuid,          -- 처리자 (탈퇴해도 기록은 남도록 FK 없음)
  actor_name  text,
  actor_role  text,
  action      text not null, -- qual_approved / qual_rejected / qual_deleted / role_changed / org_approved / org_rejected /
                             -- member_deleted / member_left / selection / activity_completed / checkin / competition_deleted
  target      text,          -- 대상 (회원 이름·대회명 등)
  detail      text,
  subject_id  uuid           -- 대상 회원 (탈퇴하면 이 기록의 이름을 지우기 위한 표시)
);
alter table audit_log add column if not exists subject_id uuid;
create index if not exists audit_log_at on audit_log (at desc);
alter table audit_log enable row level security;
drop policy if exists p_audit_select on audit_log;
create policy p_audit_select on audit_log for select using (is_admin());  -- 조회는 관리자만, 직접 쓰기·수정·삭제 불가

drop function if exists audit(text, text, text);
create or replace function audit(p_action text, p_target text, p_detail text default null, p_subject uuid default null) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); nm text; rl text;
begin
  select name, role::text into nm, rl from profiles where id = me;
  insert into audit_log (actor_id, actor_name, actor_role, action, target, detail, subject_id)
  values (me, coalesce(nm, case when me is null then '시스템' else '(탈퇴 회원)' end), rl, p_action, p_target, p_detail, p_subject);
  delete from audit_log where at < now() - interval '1 year';  -- 보관 기간 1년
end $$;
revoke all on function audit(text, text, text, uuid) from public, anon, authenticated;

-- 회원이 탈퇴하면(본인 탈퇴·관리자 탈퇴 처리 모두) 처리 기록에 남은 그 사람의 이름을 지운다
create or replace function audit_scrub_member() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update audit_log set target = replace(target, old.name, '(탈퇴 회원)') where subject_id = old.id and old.name <> '';
  update audit_log set actor_name = '(탈퇴 회원)' where actor_id = old.id;
  return old;
end $$;
drop trigger if exists profiles_audit_scrub on profiles;
create trigger profiles_audit_scrub before delete on profiles for each row execute function audit_scrub_member();

-- 자격 승인·반려·관리자 삭제
create or replace function audit_qualification() returns trigger
language plpgsql security definer set search_path = public as $$
declare who text;
begin
  if tg_op = 'UPDATE' then
    if new.status is distinct from old.status and new.status in ('approved', 'rejected') then
      select name into who from profiles where id = new.user_id;
      perform audit('qual_' || new.status::text, coalesce(who, '') || ' · ' || new.name || coalesce(' ' || new.grade, ''), null, new.user_id);
    end if;
    return new;
  end if;
  -- 삭제: 관리자가 남의 자격을 지운 경우만 (회원 탈퇴로 함께 지워지는 건 제외)
  if auth.uid() is distinct from old.user_id and exists (select 1 from profiles where id = old.user_id) then
    select name into who from profiles where id = old.user_id;
    perform audit('qual_deleted', coalesce(who, '') || ' · ' || old.name || coalesce(' ' || old.grade, ''), null, old.user_id);
  end if;
  return old;
end $$;
drop trigger if exists qualifications_audit on qualifications;
create trigger qualifications_audit after update or delete on qualifications
  for each row execute function audit_qualification();

-- 회원 유형 변경 · 기관 승인/반려
create or replace function audit_profile() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is distinct from new.id then  -- 본인이 가입 정보를 확정하는 경우는 제외
    if new.role <> old.role then
      perform audit('role_changed', new.name, old.role::text || ' → ' || new.role::text, new.id);
    end if;
    if new.org_status is distinct from old.org_status and new.org_status in ('approved', 'rejected') then
      perform audit('org_' || new.org_status::text, new.name || coalesce(' · ' || new.organization, ''), null, new.id);
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_audit on profiles;
create trigger profiles_audit after update on profiles for each row execute function audit_profile();

-- 선발 처리 · 활동완료 · 출석 (대회관계자·관리자가 한 것만. 심판 본인의 지원·취소·참석 응답은 제외)
create or replace function audit_application() returns trigger
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if auth.uid() is not distinct from new.user_id then return new; end if;
  if new.status is distinct from old.status or new.completed_at is distinct from old.completed_at
     or new.checked_in_at is distinct from old.checked_in_at then
    select p.name || ' · ' || c.name || ' ' || r.position into t
    from recruitments r join competitions c on c.id = r.competition_id, profiles p
    where r.id = new.recruitment_id and p.id = new.user_id;
    if new.status is distinct from old.status then
      perform audit('selection', t, old.status::text || ' → ' || new.status::text, new.user_id);
    end if;
    if new.completed_at is distinct from old.completed_at then
      perform audit('activity_completed', t, case when new.completed_at is null then '완료 취소' else '완료' end, new.user_id);
    end if;
    if new.checked_in_at is distinct from old.checked_in_at and new.checked_in_at is not null then
      perform audit('checkin', t, 'QR·코드 출석', new.user_id);
    end if;
  end if;
  return new;
end $$;

-- 대회 삭제
create or replace function audit_competition_delete() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform audit('competition_deleted', old.name, to_char(old.starts_on, 'YYYY.MM.DD'));
  return old;
end $$;
drop trigger if exists competitions_audit on competitions;
create trigger competitions_audit after delete on competitions for each row execute function audit_competition_delete();

-- 관리자 탈퇴 처리 · 본인 탈퇴
create or replace function admin_delete_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare nm text; em text;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if p_user = auth.uid() then raise exception '본인 계정은 탈퇴 처리할 수 없습니다'; end if;
  if exists (select 1 from profiles where id = p_user and role = 'admin') then
    raise exception '관리자 계정은 먼저 회원 유형을 바꾼 뒤 탈퇴 처리하세요';
  end if;
  select name, email into nm, em from profiles where id = p_user;
  -- 기록에는 일부를 가린 이메일만 남긴다 (예: ab***@gmail.com). 이름은 삭제와 함께 지워진다.
  perform audit('member_deleted', coalesce(nm, ''),
    case when em is null then null else left(split_part(em, '@', 1), 2) || '***@' || split_part(em, '@', 2) end, p_user);
  delete from auth.users where id = p_user;  -- 프로필 이하 개인 데이터는 cascade 삭제
end $$;
revoke all on function admin_delete_user(uuid) from public, anon;
grant execute on function admin_delete_user(uuid) to authenticated;

create or replace function delete_my_account() returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); rl text;
begin
  if me is null then raise exception 'not signed in'; end if;
  select role::text into rl from profiles where id = me;
  if rl = 'admin' then raise exception '관리자 계정은 앱에서 탈퇴할 수 없습니다'; end if;
  delete from auth.users where id = me;   -- profiles 이하 개인 데이터는 cascade 삭제
  -- 탈퇴한 사람의 개인정보는 남기지 않고 '본인 탈퇴' 사실만 기록
  insert into audit_log (actor_name, actor_role, action, target) values ('(탈퇴 회원)', rl, 'member_left', '본인 탈퇴');
end $$;
revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;

-- ============================================================
-- 1. 현장 QR 출석 체크
-- ============================================================
alter table applications add column if not exists checkin_code text;      -- 심판 QR 에 담기는 8자리 코드
alter table applications add column if not exists checked_in_at timestamptz;
alter table applications add column if not exists checked_in_by uuid;      -- 스캔한 대회관계자·관리자
update applications set checkin_code = upper(substr(md5(gen_random_uuid()::text), 1, 8)) where checkin_code is null;
alter table applications alter column checkin_code set default upper(substr(md5(gen_random_uuid()::text), 1, 8));
create unique index if not exists applications_checkin_code on applications (checkin_code);

drop trigger if exists applications_audit on applications;
create trigger applications_audit after update on applications for each row execute function audit_application();

-- 지원자 본인은 출석 기록·코드를 바꿀 수 없다 (기존 규칙에 추가)
create or replace function guard_application_update() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_admin() or owns_recruitment(old.recruitment_id) then return new; end if;  -- uid null = 서버/SQL 콘솔
  if new.user_id <> old.user_id or new.recruitment_id <> old.recruitment_id
     or new.completed_at is distinct from old.completed_at
     or new.checked_in_at is distinct from old.checked_in_at
     or new.checked_in_by is distinct from old.checked_in_by
     or new.checkin_code is distinct from old.checkin_code
     or (new.status <> old.status
         and not (new.status = 'cancelled' and old.status = 'applied')
         and not (new.status = 'applied' and old.status = 'cancelled')) then
    raise exception '지원자는 지원 취소·재지원만 가능';
  end if;
  if new.attendance <> old.attendance
     and not (old.status = 'selected' and new.status = 'selected' and old.completed_at is null
              and new.attendance in ('attending', 'absent')) then
    raise exception '참석 응답은 선발된 뒤 활동완료 전까지만 가능';
  end if;
  if new.status = 'applied' and old.status = 'cancelled' and not exists (
       select 1 from recruitments r where r.id = new.recruitment_id and r.is_open
       and (r.deadline is null or r.deadline > now())) then
    raise exception '모집이 마감되었습니다';
  end if;
  return new;
end $$;

-- 출석 처리: 대회관계자(내 대회)·관리자가 심판의 QR/코드를 읽어 호출
create or replace function check_in(p_code text) returns json
language plpgsql security definer set search_path = public as $$
declare
  a record;
  -- 'WINREF:1A2B-3C4D' 처럼 접두어·하이픈·소문자가 섞여 와도 마지막 8자리만 사용
  code text := right(upper(regexp_replace(coalesce(p_code, ''), '[^0-9A-Za-z]', '', 'g')), 8);
  today date := (now() at time zone 'Asia/Seoul')::date;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select ap.id, ap.status, ap.checked_in_at, ap.recruitment_id, p.name, p.avatar_path,
         r.position, c.name as competition, c.starts_on, coalesce(c.ends_on, c.starts_on) as ends_on
    into a
  from applications ap
  join profiles p on p.id = ap.user_id
  join recruitments r on r.id = ap.recruitment_id
  join competitions c on c.id = r.competition_id
  where ap.checkin_code = code;
  if not found then raise exception '등록되지 않은 출석 코드입니다.'; end if;
  if not (is_admin() or owns_recruitment(a.recruitment_id)) then
    raise exception '내가 등록한 대회의 심판만 출석 처리할 수 있습니다.';
  end if;
  if a.status <> 'selected' then raise exception '선발된 심판이 아닙니다.'; end if;
  if today < a.starts_on - 1 or today > a.ends_on then
    raise exception '출석 체크는 대회 전날부터 종료일까지 가능합니다.';
  end if;
  if a.checked_in_at is null then
    update applications set checked_in_at = now(), checked_in_by = auth.uid(), attendance = 'attending' where id = a.id;
  end if;
  return json_build_object(
    'name', a.name, 'avatar_path', a.avatar_path, 'position', a.position, 'competition', a.competition,
    'already', a.checked_in_at is not null, 'checked_in_at', coalesce(a.checked_in_at, now()));
end $$;
revoke all on function check_in(text) from public, anon;
grant execute on function check_in(text) to authenticated;

-- ============================================================
-- 2. 활동확인서 발급·진위 확인
-- ============================================================
create table if not exists certificates (
  code       text primary key,                 -- 발급번호 (문서·QR 에 인쇄)
  user_id    uuid not null references profiles(id) on delete cascade,  -- 탈퇴하면 함께 삭제
  issued_at  timestamptz not null default now(),
  name       text not null,                    -- 발급 시점의 이름
  items      jsonb not null,                   -- 발급 시점의 활동 내역
  quals      jsonb not null default '[]'       -- 발급 시점의 승인 자격
);
alter table certificates enable row level security;
drop policy if exists p_cert_select on certificates;
create policy p_cert_select on certificates for select using (user_id = auth.uid() or is_admin());

-- 본인 활동확인서 발급: 지금의 활동 이력·승인 자격을 그대로 기록하고 발급번호를 돌려준다
create or replace function issue_certificate() returns json
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  v_code text := 'WR' || to_char(now() at time zone 'Asia/Seoul', 'YYMM') || '-' || upper(substr(md5(gen_random_uuid()::text), 1, 8));
  v_name text;
  v_items jsonb;
  v_quals jsonb;
  v_at timestamptz := now();
begin
  if me is null then raise exception 'not signed in'; end if;
  select name into v_name from profiles where id = me;
  select coalesce(jsonb_agg(jsonb_build_object(
           'competition', c.name, 'starts_on', c.starts_on, 'ends_on', c.ends_on, 'venue', c.venue, 'position', r.position)
           order by c.starts_on desc), '[]')
    into v_items
  from applications a join recruitments r on r.id = a.recruitment_id join competitions c on c.id = r.competition_id
  where a.user_id = me and a.completed_at is not null;
  select coalesce(jsonb_agg(jsonb_build_object('name', q.name, 'grade', q.grade, 'expires_on', q.expires_on)
           order by q.acquired_on), '[]')
    into v_quals
  from qualifications q where q.user_id = me and q.status = 'approved';
  insert into certificates (code, user_id, issued_at, name, items, quals) values (v_code, me, v_at, v_name, v_items, v_quals);
  return json_build_object('code', v_code, 'issued_at', v_at);
end $$;
revoke all on function issue_certificate() from public, anon;
grant execute on function issue_certificate() to authenticated;

-- 진위 확인: 발급번호를 아는 누구나(문서를 받은 기관) 발급 내용 조회. 연락처 등 다른 개인정보는 주지 않는다.
create or replace function verify_certificate(p_code text) returns json
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select json_build_object('valid', true, 'code', code, 'issued_at', issued_at, 'name', name,
                              'count', jsonb_array_length(items), 'items', items, 'quals', quals)
     from certificates where code = upper(trim(coalesce(p_code, '')))),
    json_build_object('valid', false));
$$;
grant execute on function verify_certificate(text) to anon, authenticated;

-- ============================================================
-- 3. 성과 리포트 (관리자) — 기간은 한국 시간 기준, 양 끝 날짜 포함
-- ============================================================
create or replace function admin_report(p_from date, p_to date) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  t0 timestamptz := (p_from::timestamp at time zone 'Asia/Seoul');
  t1 timestamptz := ((p_to + 1)::timestamp at time zone 'Asia/Seoul');
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if p_to < p_from then raise exception '종료일은 시작일보다 빠를 수 없습니다.'; end if;
  return json_build_object(
    'from', p_from, 'to', p_to,
    'members_total', (select count(*) from profiles where onboarded),
    'members_referee', (select count(*) from profiles where onboarded and role = 'referee'),
    'members_organizer', (select count(*) from profiles where onboarded and role = 'organizer'),
    'new_members', (select count(*) from profiles where created_at >= t0 and created_at < t1),
    'new_referees', (select count(*) from profiles where role = 'referee' and created_at >= t0 and created_at < t1),
    'new_organizers', (select count(*) from profiles where role = 'organizer' and created_at >= t0 and created_at < t1),
    'quals_submitted', (select count(*) from qualifications where created_at >= t0 and created_at < t1),
    'quals_approved', (select count(*) from audit_log where action = 'qual_approved' and at >= t0 and at < t1),
    'quals_rejected', (select count(*) from audit_log where action = 'qual_rejected' and at >= t0 and at < t1),
    'quals_approved_total', (select count(*) from qualifications where status = 'approved'),
    'courses', (select count(*) from courses where starts_at >= t0 and starts_at < t1),
    'course_applications', (select count(*) from course_applications where status <> 'cancelled' and created_at >= t0 and created_at < t1),
    'competitions', (select count(*) from competitions where starts_on between p_from and p_to),
    'recruitments', (select count(*) from recruitments r join competitions c on c.id = r.competition_id where c.starts_on between p_from and p_to),
    'headcount', (select coalesce(sum(r.headcount), 0) from recruitments r join competitions c on c.id = r.competition_id where c.starts_on between p_from and p_to),
    'applications', (select count(*) from applications where status <> 'cancelled' and created_at >= t0 and created_at < t1),
    'selected', (select count(*) from applications a join recruitments r on r.id = a.recruitment_id
                 join competitions c on c.id = r.competition_id where a.status = 'selected' and c.starts_on between p_from and p_to),
    'checked_in', (select count(*) from applications where checked_in_at >= t0 and checked_in_at < t1),
    'completed', (select count(*) from applications where completed_at >= t0 and completed_at < t1),
    'certificates', (select count(*) from certificates where issued_at >= t0 and issued_at < t1),
    'notices', (select count(*) from notices where created_at >= t0 and created_at < t1),
    'by_competition', (select coalesce(json_agg(t order by t.starts_on), '[]') from (
        select c.name, c.starts_on,
               (select coalesce(sum(r2.headcount), 0) from recruitments r2 where r2.competition_id = c.id) headcount,
               count(a.id) filter (where a.status <> 'cancelled') applied,
               count(a.id) filter (where a.status = 'selected') selected,
               count(a.id) filter (where a.checked_in_at is not null) checked_in,
               count(a.id) filter (where a.completed_at is not null) completed
        from competitions c left join recruitments r on r.competition_id = c.id
        left join applications a on a.recruitment_id = r.id
        where c.starts_on between p_from and p_to group by c.id) t)
  );
end $$;
revoke all on function admin_report(date, date) from public, anon;
grant execute on function admin_report(date, date) to authenticated;

-- ============================================================
-- 4. 오류 수집 — 사용자 기기에서 난 앱 오류를 관리자가 볼 수 있게 저장 (90일 보관)
-- ============================================================
create table if not exists error_logs (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  user_id   uuid,          -- 로그인 상태였다면 (FK 없음: 탈퇴해도 오류 자체는 남김, 이름·연락처는 저장 안 함)
  build     text,
  platform  text,
  message   text not null,
  stack     text
);
create index if not exists error_logs_at on error_logs (at desc);
alter table error_logs enable row level security;
drop policy if exists p_errlog_select on error_logs;
create policy p_errlog_select on error_logs for select using (is_admin());
drop policy if exists p_errlog_delete on error_logs;
create policy p_errlog_delete on error_logs for delete using (is_admin());

create or replace function log_error(p_message text, p_stack text default null, p_build text default null, p_platform text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if coalesce(trim(p_message), '') = '' then return; end if;
  -- 폭주 방지: 10분에 200건까지만
  if (select count(*) from error_logs where at > now() - interval '10 minutes') >= 200 then return; end if;
  insert into error_logs (user_id, build, platform, message, stack)
  values (auth.uid(), left(p_build, 40), left(p_platform, 40), left(p_message, 500), left(p_stack, 4000));
  delete from error_logs where at < now() - interval '90 days';
end $$;
grant execute on function log_error(text, text, text, text) to anon, authenticated;
