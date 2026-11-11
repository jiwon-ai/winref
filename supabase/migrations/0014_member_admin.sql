-- 고객 피드백: 회원 이메일(아이디) 표시, 관리자 회원 탈퇴 처리

-- 1) 프로필에 이메일(아이디) 보관 — 가입·이메일 변경 시 자동 동기화
alter table profiles add column if not exists email text;
update profiles p set email = u.email from auth.users u where u.id = p.id and p.email is distinct from u.email;

create or replace function sync_profile_email() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update profiles set email = new.email where id = new.id and email is distinct from new.email;
  return new;
end $$;
-- 이름순으로 on_auth_user_created(프로필 생성) 다음에 실행
create or replace trigger zz_sync_profile_email after insert or update of email on auth.users
  for each row execute function sync_profile_email();

-- 본인이 이메일 칸을 임의로 바꾸지 못하게 (나머지 규칙은 0005 와 동일)
create or replace function guard_profile_update() returns trigger language plpgsql as $$
begin
  -- 관리자, 서버 내부(보안 함수·SQL Editor) 변경은 허용
  if auth.uid() is null or is_admin() or current_user in ('postgres', 'supabase_admin') then return new; end if;
  new.email := old.email;
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

-- 2) 관리자가 회원 탈퇴 처리 (본인·다른 관리자는 불가)
create or replace function admin_delete_user(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  if p_user = auth.uid() then raise exception '본인 계정은 탈퇴 처리할 수 없습니다'; end if;
  if exists (select 1 from profiles where id = p_user and role = 'admin') then
    raise exception '관리자 계정은 먼저 회원 유형을 바꾼 뒤 탈퇴 처리하세요';
  end if;
  delete from auth.users where id = p_user;  -- 프로필 이하 개인 데이터는 cascade 삭제
end $$;
revoke all on function admin_delete_user(uuid) from public, anon;
grant execute on function admin_delete_user(uuid) to authenticated;

-- 관리자는 탈퇴 회원의 파일(프로필 사진·자격증 사본)도 지울 수 있게
drop policy if exists p_files_admin_delete on storage.objects;
create policy p_files_admin_delete on storage.objects for delete using (bucket_id = 'files' and is_admin());
