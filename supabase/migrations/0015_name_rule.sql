-- 이름 규칙(한글만, 띄어쓰기 없이 2~10자)을 서버에서도 강제
-- 앱 화면에서 막아도 예전 버전 앱·직접 API 호출로 들어오는 이름을 막기 위함.

-- 1) 가입: 규칙에 안 맞는 이름(카카오 닉네임 'Jiwon' 등)이면 가입 정보 입력 화면을 거치게 한다
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r user_role;
  social boolean := coalesce(new.raw_app_meta_data->>'provider', 'email') <> 'email';
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  nm text := coalesce(m->>'name', m->>'full_name', m->>'user_name', m->>'nickname', m->>'preferred_username',
                      split_part(coalesce(new.email, ''), '@', 1), '');
  valid boolean := nm ~ '^[가-힣]{2,10}$';
begin
  -- 소셜 가입은 유형을 고를 수 없으므로 일단 심판으로 만들고, 가입 정보 화면에서 확정한다
  r := case when not social and m->>'role' = 'organizer' then 'organizer'::user_role else 'referee'::user_role end;
  insert into profiles (id, role, name, phone, organization, org_status, onboarded, agreed_at)
  values (new.id, r, nm,
          m->>'phone',
          m->>'organization',
          case when r = 'organizer' then 'pending'::approval_status end,
          not social and valid,
          case when not social then now() end);
  return new;
end $$;

-- 2) 수정: 앱 사용자가 이름을 바꾸거나 가입 정보를 확정할 때 규칙 검사 (서버 내부·SQL 콘솔은 제외)
create or replace function check_profile_name() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or current_user in ('postgres', 'supabase_admin') then return new; end if;
  if new.onboarded and (new.name is distinct from old.name or not old.onboarded)
     and coalesce(new.name, '') !~ '^[가-힣]{2,10}$' then
    raise exception '이름은 한글로만, 띄어쓰기 없이 2~10자로 입력해 주세요.';
  end if;
  return new;
end $$;
drop trigger if exists profiles_name_rule on profiles;
create trigger profiles_name_rule before update on profiles
  for each row execute function check_profile_name();
