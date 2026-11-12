-- 자격 확인 요청 알림은 관리자에게만 (앱 알림 + 푸시)
-- 신규 등록뿐 아니라 반려된 자격을 본인이 고쳐 다시 제출(반려→대기)할 때도 관리자에게 알린다.
-- 요청한 본인(심판)에게는 확인 요청 알림을 보내지 않는다. (여러 번 실행해도 안전)

create or replace function notify_qual_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    perform notify_admins('qual_request', '자격 확인 요청',
      coalesce((select name from profiles where id = new.user_id), '') || ' · ' || new.name || coalesce(' ' || new.grade, ''));
  elsif tg_op = 'UPDATE' and new.status = 'pending' and old.status = 'rejected' then
    perform notify_admins('qual_request', '자격 재확인 요청',
      coalesce((select name from profiles where id = new.user_id), '') || ' · ' || new.name || coalesce(' ' || new.grade, '') || ' (수정 후 재제출)');
  end if;
  return new;
end $$;
drop trigger if exists qualifications_request on qualifications;
create trigger qualifications_request after insert or update of status on qualifications
  for each row execute function notify_qual_request();
