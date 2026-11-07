-- 구글·카카오 가입: 첫 로그인 때 회원 유형·연락처·개인정보 동의를 받는다.
alter table profiles
  add column onboarded boolean not null default true,  -- 가입 정보 입력 완료 (이메일 가입은 가입 화면에서 입력)
  add column agreed_at timestamptz;                    -- 개인정보 수집·이용 동의 시각

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r user_role;
  social boolean := coalesce(new.raw_app_meta_data->>'provider', 'email') <> 'email';
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  -- 소셜 가입은 유형을 고를 수 없으므로 일단 심판으로 만들고, 가입 정보 화면에서 확정한다
  r := case when not social and m->>'role' = 'organizer' then 'organizer'::user_role else 'referee'::user_role end;
  insert into profiles (id, role, name, phone, organization, org_status, onboarded, agreed_at)
  values (new.id, r,
          coalesce(m->>'name', m->>'full_name', m->>'user_name', m->>'nickname', m->>'preferred_username',
                   split_part(coalesce(new.email, ''), '@', 1), ''),
          m->>'phone',
          m->>'organization',
          case when r = 'organizer' then 'pending'::approval_status end,
          not social,
          case when not social then now() end);
  return new;
end $$;

-- 일반 사용자는 role/org_status/onboarded 를 바꿀 수 없다.
-- 예외: 소셜 가입자가 최초 1회 가입 정보를 확정할 때 (심판 또는 승인대기 대회관계자로만)
create or replace function guard_profile_update() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_admin() then return new; end if;
  if old.onboarded = false and new.onboarded = true
     and ((new.role = 'referee' and new.org_status is null)
          or (new.role = 'organizer' and new.org_status = 'pending')) then
    return new;
  end if;
  if new.role <> old.role or new.org_status is distinct from old.org_status
     or new.onboarded is distinct from old.onboarded then
    raise exception 'role/org_status 는 관리자만 변경 가능';
  end if;
  return new;
end $$;
