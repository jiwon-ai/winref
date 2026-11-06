-- WINREF 인재은행 MVP 스키마 (과업지시서 3~5항 기준)

-- ===== 열거형 =====
create type user_role as enum ('referee', 'organizer', 'admin');      -- 심판·교육신청자 / 대회관계자 / 관리자
create type approval_status as enum ('pending', 'approved', 'rejected');
create type application_status as enum ('applied', 'selected', 'reserve', 'rejected', 'cancelled'); -- 선발·예비·미선발
create type attendance_status as enum ('unknown', 'attending', 'absent');

-- ===== 회원 =====
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  role          user_role not null,
  name          text not null,
  phone         text,
  birth_date    date,
  organization  text,                         -- 대회관계자 소속기관
  org_status    approval_status,              -- 대회관계자 계정·기관 승인 (관리자 기능)
  fcm_token     text,
  created_at    timestamptz not null default now()
);

-- ===== 자격정보 =====
create table qualifications (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references profiles(id) on delete cascade,
  name           text not null,               -- 보유 자격
  grade          text,                        -- 등급
  acquired_on    date,                        -- 취득일
  expires_on     date,                        -- 유효기간
  refresher_done boolean not null default false, -- 보수교육 상태
  status         approval_status not null default 'pending', -- 관리자 확인·승인
  created_at     timestamptz not null default now()
);

-- ===== 교육 =====
create table courses (
  id            bigint generated always as identity primary key,
  title         text not null,
  description   text,
  location      text,
  starts_at     timestamptz,
  ends_at       timestamptz,
  apply_deadline timestamptz,
  capacity      int,
  is_refresher  boolean not null default false,  -- 보수교육 여부
  created_at    timestamptz not null default now()
);

create table course_applications (
  id          bigint generated always as identity primary key,
  course_id   bigint not null references courses(id) on delete cascade,
  user_id     uuid not null references profiles(id) on delete cascade,
  status      text not null default 'applied' check (status in ('applied','confirmed','cancelled')),
  created_at  timestamptz not null default now(),
  unique (course_id, user_id)
);

-- ===== 대회 =====
create table competitions (
  id            bigint generated always as identity primary key,
  organizer_id  uuid not null references profiles(id),
  name          text not null,
  starts_on     date not null,
  ends_on       date,
  venue         text,
  host_org      text,                         -- 주최·주관기관
  poster_path   text,                         -- storage 경로
  created_at    timestamptz not null default now()
);

-- 심판 모집공고
create table recruitments (
  id              bigint generated always as identity primary key,
  competition_id  bigint not null references competitions(id) on delete cascade,
  position        text not null,              -- 모집 포지션
  headcount       int not null check (headcount > 0),
  requirements    text,                       -- 자격조건
  deadline        timestamptz,
  preparation     text,                       -- 준비사항
  is_open         boolean not null default true,
  created_at      timestamptz not null default now()
);

-- 지원·선발·활동
create table applications (
  id              bigint generated always as identity primary key,
  recruitment_id  bigint not null references recruitments(id) on delete cascade,
  user_id         uuid not null references profiles(id) on delete cascade,
  status          application_status not null default 'applied',
  attendance      attendance_status not null default 'unknown',
  completed_at    timestamptz,                -- 활동완료 처리 시각 → 활동이력
  created_at      timestamptz not null default now(),
  unique (recruitment_id, user_id)
);

-- 브리핑 자료 (선발 심판 전용)
create table briefings (
  id              bigint generated always as identity primary key,
  competition_id  bigint not null references competitions(id) on delete cascade,
  title           text not null,
  body            text,
  file_path       text,                       -- PDF·이미지
  created_at      timestamptz not null default now()
);

-- 공지사항
create table notices (
  id          bigint generated always as identity primary key,
  title       text not null,
  body        text,
  file_path   text,
  created_at  timestamptz not null default now()
);

-- 알림 (앱 내 알림함 + 푸시 발송 큐)
create table notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references profiles(id) on delete cascade,
  kind        text not null,                  -- course_deadline / competition_d1 / refresher / notice / selection
  title       text not null,
  body        text,
  dedupe_key  text unique,                    -- 자동알림 중복 방지
  read_at     timestamptz,
  pushed_at   timestamptz,
  created_at  timestamptz not null default now()
);

-- 활동이력 뷰: 활동완료 처리된 지원 건
create view activity_history with (security_invoker = true) as
select a.user_id, c.id as competition_id, c.name as competition_name,
       c.starts_on, c.ends_on, c.venue, r.position, a.completed_at
from applications a
join recruitments r on r.id = a.recruitment_id
join competitions c on c.id = r.competition_id
where a.completed_at is not null;

-- ===== 헬퍼 =====
create function is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

create function is_approved_organizer() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'organizer' and org_status = 'approved');
$$;

create function owns_competition(cid bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from competitions where id = cid and organizer_id = auth.uid());
$$;

create function owns_recruitment(rid bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from recruitments r join competitions c on c.id = r.competition_id
                 where r.id = rid and c.organizer_id = auth.uid());
$$;

create function is_selected_for(cid bigint) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from applications a join recruitments r on r.id = a.recruitment_id
                 where r.competition_id = cid and a.user_id = auth.uid() and a.status = 'selected');
$$;

-- 회원가입 시 profile 자동 생성 (role 은 가입 metadata 에서, admin 은 가입으로 불가)
create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare r user_role;
begin
  r := case when new.raw_user_meta_data->>'role' = 'organizer' then 'organizer'::user_role else 'referee'::user_role end;
  insert into profiles (id, role, name, phone, organization, org_status)
  values (new.id, r,
          coalesce(new.raw_user_meta_data->>'name', ''),
          new.raw_user_meta_data->>'phone',
          new.raw_user_meta_data->>'organization',
          case when r = 'organizer' then 'pending'::approval_status end);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- 일반 사용자가 자기 role/승인상태를 바꾸지 못하게 막음
create function guard_profile_update() returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and not is_admin() and (new.role <> old.role or new.org_status is distinct from old.org_status) then
    raise exception 'role/org_status 는 관리자만 변경 가능';
  end if;
  return new;
end $$;
create trigger profiles_guard before update on profiles for each row execute function guard_profile_update();

-- 지원자는 status/attendance/completed_at 를 직접 바꿀 수 없음 (취소만 허용)
create function guard_application_update() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_admin() or owns_recruitment(old.recruitment_id) then return new; end if;  -- uid null = 서버/SQL 콘솔
  if new.user_id <> old.user_id or new.recruitment_id <> old.recruitment_id
     or new.completed_at is distinct from old.completed_at
     or (new.status <> old.status
         and not (new.status = 'cancelled' and old.status = 'applied')
         and not (new.status = 'applied' and old.status = 'cancelled'))
     or new.attendance <> old.attendance then
    raise exception '지원자는 지원 취소·재지원만 가능';
  end if;
  if new.status = 'applied' and old.status = 'cancelled' and not exists (
       select 1 from recruitments r where r.id = new.recruitment_id and r.is_open
       and (r.deadline is null or r.deadline > now())) then
    raise exception '모집이 마감되었습니다';
  end if;
  return new;
end $$;
create trigger applications_guard before update on applications for each row execute function guard_application_update();

-- 활동완료는 선발된 건만
create function check_completion() returns trigger language plpgsql as $$
begin
  if new.completed_at is not null and new.status <> 'selected' then
    raise exception '선발된 지원 건만 활동완료 처리 가능';
  end if;
  return new;
end $$;
create trigger applications_completion before insert or update on applications for each row execute function check_completion();

-- ===== RLS =====
alter table profiles enable row level security;
alter table qualifications enable row level security;
alter table courses enable row level security;
alter table course_applications enable row level security;
alter table competitions enable row level security;
alter table recruitments enable row level security;
alter table applications enable row level security;
alter table briefings enable row level security;
alter table notices enable row level security;
alter table notifications enable row level security;

-- profiles
create policy p_profiles_self on profiles for select using (id = auth.uid() or is_admin());
create policy p_profiles_applicant on profiles for select using (   -- 대회관계자: 자기 공고 지원자 열람
  exists (select 1 from applications a where a.user_id = profiles.id and owns_recruitment(a.recruitment_id)));
create policy p_profiles_update on profiles for update using (id = auth.uid() or is_admin());

-- qualifications
create policy p_q_select on qualifications for select using (
  user_id = auth.uid() or is_admin()
  or exists (select 1 from applications a where a.user_id = qualifications.user_id and owns_recruitment(a.recruitment_id)));
create policy p_q_insert on qualifications for insert with check (user_id = auth.uid() and status = 'pending');
create policy p_q_update_admin on qualifications for update using (is_admin());
create policy p_q_delete on qualifications for delete using ((user_id = auth.uid() and status = 'pending') or is_admin());

-- courses: 로그인 사용자 조회, 관리자 관리
create policy p_courses_read on courses for select using (auth.uid() is not null);
create policy p_courses_admin on courses for all using (is_admin()) with check (is_admin());

create policy p_ca_select on course_applications for select using (user_id = auth.uid() or is_admin());
create policy p_ca_insert on course_applications for insert with check (
  user_id = auth.uid()
  and exists (select 1 from courses c where c.id = course_id and (c.apply_deadline is null or c.apply_deadline > now())));
create policy p_ca_update on course_applications for update using (user_id = auth.uid() or is_admin());

-- competitions / recruitments: 로그인 사용자 조회, 승인된 관계자는 자기 것만 관리
create policy p_comp_read on competitions for select using (auth.uid() is not null);
create policy p_comp_insert on competitions for insert with check (
  (is_approved_organizer() and organizer_id = auth.uid()) or is_admin());
create policy p_comp_modify on competitions for update using (organizer_id = auth.uid() or is_admin());
create policy p_comp_delete on competitions for delete using (organizer_id = auth.uid() or is_admin());

create policy p_rec_read on recruitments for select using (auth.uid() is not null);
create policy p_rec_write on recruitments for all
  using (owns_competition(competition_id) or is_admin())
  with check ((owns_competition(competition_id) and is_approved_organizer()) or is_admin());

-- applications
create policy p_app_select on applications for select using (
  user_id = auth.uid() or owns_recruitment(recruitment_id) or is_admin());
create policy p_app_insert on applications for insert with check (
  user_id = auth.uid() and status = 'applied' and completed_at is null
  and exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'referee')
  and exists (select 1 from recruitments r where r.id = recruitment_id and r.is_open
              and (r.deadline is null or r.deadline > now())));
create policy p_app_update on applications for update using (
  user_id = auth.uid() or owns_recruitment(recruitment_id) or is_admin());

-- briefings: 선발된 심판 + 해당 관계자 + 관리자
create policy p_brief_read on briefings for select using (
  is_selected_for(competition_id) or owns_competition(competition_id) or is_admin());
create policy p_brief_write on briefings for all
  using (owns_competition(competition_id) or is_admin())
  with check (owns_competition(competition_id) or is_admin());

-- notices
create policy p_notice_read on notices for select using (auth.uid() is not null);
create policy p_notice_admin on notices for all using (is_admin()) with check (is_admin());

-- notifications: 본인 조회·읽음처리, 생성은 관리자 또는 서버(service_role, RLS 우회)
create policy p_noti_read on notifications for select using (user_id = auth.uid() or is_admin());
create policy p_noti_update on notifications for update using (user_id = auth.uid());
create policy p_noti_admin on notifications for insert with check (is_admin());

-- ===== 통계 (관리자 대시보드, 과업지시서 5항) =====
create function admin_stats() returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  return json_build_object(
    'members_by_role', (select coalesce(json_object_agg(role, n), '{}') from (select role, count(*) n from profiles group by role) t),
    'new_members_30d', (select count(*) from profiles where created_at > now() - interval '30 days'),
    'course_applicants', (select coalesce(json_agg(t), '[]') from (
        select c.id, c.title, count(ca.id) filter (where ca.status <> 'cancelled') applicants
        from courses c left join course_applications ca on ca.course_id = c.id group by c.id order by c.id desc) t),
    'competitions', (select count(*) from competitions),
    'open_recruitments', (select count(*) from recruitments where is_open),
    'competition_applications', (select coalesce(json_agg(t), '[]') from (
        select c.id, c.name,
               count(a.id) filter (where a.status <> 'cancelled') applied,
               count(a.id) filter (where a.status = 'selected') selected
        from competitions c left join recruitments r on r.competition_id = c.id
        left join applications a on a.recruitment_id = r.id group by c.id order by c.starts_on desc) t),
    'completed_activities', (select count(*) from applications where completed_at is not null),
    'expiring_90d', (select count(distinct user_id) from qualifications
                     where status = 'approved' and expires_on between current_date and current_date + 90)
  );
end $$;

-- ===== 자동알림 생성 (pg_cron 으로 매일 실행; 푸시 발송은 Edge Function 이 pushed_at null 건을 처리) =====
create function enqueue_auto_notifications() returns void language plpgsql security definer set search_path = public as $$
begin
  -- 교육 신청 마감 1일 전: 아직 신청하지 않은 심판·교육신청자
  insert into notifications (user_id, kind, title, body, dedupe_key)
  select p.id, 'course_deadline', '교육 신청 마감 임박', c.title || ' 신청이 내일 마감됩니다.',
         'course_deadline:' || c.id || ':' || p.id
  from courses c cross join profiles p
  where p.role = 'referee'
    and c.apply_deadline >= now() + interval '1 day' and c.apply_deadline < now() + interval '2 days'
    and not exists (select 1 from course_applications ca where ca.course_id = c.id and ca.user_id = p.id)
  on conflict (dedupe_key) do nothing;

  -- 대회 D-1: 선발된 심판
  insert into notifications (user_id, kind, title, body, dedupe_key)
  select a.user_id, 'competition_d1', '내일 대회 일정 안내',
         c.name || ' / ' || coalesce(c.venue, '') || ' / ' || r.position,
         'competition_d1:' || c.id || ':' || a.user_id
  from applications a join recruitments r on r.id = a.recruitment_id
  join competitions c on c.id = r.competition_id
  where a.status = 'selected' and c.starts_on = current_date + 1
  on conflict (dedupe_key) do nothing;

  -- 자격 유효기간 만료 30일 전: 보수교육 안내
  insert into notifications (user_id, kind, title, body, dedupe_key)
  select q.user_id, 'refresher', '자격 만료 예정 · 보수교육 안내',
         q.name || ' 자격이 ' || to_char(q.expires_on, 'YYYY-MM-DD') || '에 만료됩니다.',
         'refresher:' || q.id || ':' || q.expires_on
  from qualifications q
  where q.status = 'approved' and q.expires_on = current_date + 30
  on conflict (dedupe_key) do nothing;
end $$;

-- ===== 파일 저장소 (포스터·브리핑·공지 자료) =====
insert into storage.buckets (id, name, public) values ('files', 'files', false)
  on conflict (id) do nothing;
create policy p_files_read on storage.objects for select using (bucket_id = 'files' and auth.uid() is not null);
create policy p_files_write on storage.objects for insert with check (
  bucket_id = 'files' and (is_admin() or is_approved_organizer()));
