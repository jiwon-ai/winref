-- 회원 탈퇴 (Google Play 계정 삭제 요건). 본인 계정과 개인 데이터를 삭제한다.
-- 대회관계자가 탈퇴해도 대회·심판 활동이력은 남도록 organizer_id 를 비운다.
alter table competitions alter column organizer_id drop not null;
alter table competitions drop constraint competitions_organizer_id_fkey;
alter table competitions add constraint competitions_organizer_id_fkey
  foreign key (organizer_id) references profiles(id) on delete set null;

create function delete_my_account() returns void language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if exists (select 1 from profiles where id = me and role = 'admin') then
    raise exception '관리자 계정은 앱에서 탈퇴할 수 없습니다';
  end if;
  delete from auth.users where id = me;   -- profiles 이하 개인 데이터는 cascade 삭제
end $$;
revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
