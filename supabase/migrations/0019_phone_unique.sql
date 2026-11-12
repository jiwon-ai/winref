-- 휴대폰 번호 1개 = 계정 1개 (이메일·카카오·구글로 중복 가입 방지). 여러 번 실행해도 안전.

-- 1) 가입 전 확인용: 이미 다른 계정이 쓰는 번호인가 (번호만 확인, 누구인지는 알려주지 않음)
create or replace function phone_in_use(p_phone text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where phone = regexp_replace(coalesce(p_phone, ''), '\D', '', 'g')
      and onboarded
      and id is distinct from auth.uid());
$$;
grant execute on function phone_in_use(text) to anon, authenticated;

-- 트리거용: RLS 와 무관하게 다른 계정의 번호 사용 여부 확인 (본인 제외)
create or replace function phone_taken(p_phone text, p_self uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where phone = p_phone and onboarded and id <> p_self);
$$;
revoke all on function phone_taken(text, uuid) from public, anon;
grant execute on function phone_taken(text, uuid) to authenticated;

-- 2) 가입: 이미 쓰는 번호로 이메일 가입하면 가입 정보 입력 화면으로 보내 다시 입력받는다
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  r user_role;
  social boolean := coalesce(new.raw_app_meta_data->>'provider', 'email') <> 'email';
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  nm text := coalesce(m->>'name', m->>'full_name', m->>'user_name', m->>'nickname', m->>'preferred_username',
                      split_part(coalesce(new.email, ''), '@', 1), '');
  ph text := m->>'phone';
  dup boolean := ph is not null and exists (select 1 from profiles where phone = ph and onboarded);
  valid boolean := nm ~ '^[가-힣]{2,10}$' and coalesce(ph, '') ~ '^(010[0-9]{8}|01[16789][0-9]{7,8})$' and not dup;
begin
  r := case when not social and m->>'role' = 'organizer' then 'organizer'::user_role else 'referee'::user_role end;
  insert into profiles (id, role, name, phone, organization, org_status, onboarded, agreed_at)
  values (new.id, r, nm, case when dup then null else ph end,
          m->>'organization',
          case when r = 'organizer' then 'pending'::approval_status end,
          not social and valid,
          case when not social then now() end);
  return new;
end $$;

-- 3) 수정·가입 확정: 이름·번호 규칙 + 번호 중복 검사
create or replace function check_profile_name() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or current_user in ('postgres', 'supabase_admin') or not new.onboarded then return new; end if;
  if (new.name is distinct from old.name or not old.onboarded)
     and coalesce(new.name, '') !~ '^[가-힣]{2,10}$' then
    raise exception '이름은 한글로만, 띄어쓰기 없이 2~10자로 입력해 주세요.';
  end if;
  if (new.phone is distinct from old.phone or not old.onboarded) then
    if coalesce(new.phone, '') !~ '^(010[0-9]{8}|01[16789][0-9]{7,8})$' then
      raise exception '휴대폰 번호를 정확히 입력해 주세요. (예: 01012345678)';
    end if;
    if phone_taken(new.phone, new.id) then
      raise exception '이미 가입된 휴대폰 번호입니다. 처음 가입한 방법(이메일·카카오·구글)으로 로그인해 주세요.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists profiles_name_rule on profiles;
create trigger profiles_name_rule before update on profiles
  for each row execute function check_profile_name();

-- 4) 최종 보장: 같은 번호의 가입 완료 계정은 1개만 (기존 데이터에 중복이 있으면 건너뛰고 알림)
do $$
begin
  if exists (select phone from profiles where phone is not null and onboarded group by phone having count(*) > 1) then
    raise notice '중복 번호가 있어 고유 인덱스를 만들지 않았습니다. 관리자 화면에서 중복 계정을 정리한 뒤 이 파일을 다시 실행하세요.';
  else
    create unique index if not exists profiles_phone_unique on profiles (phone) where phone is not null and onboarded;
  end if;
end $$;
