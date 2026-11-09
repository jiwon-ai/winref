-- 고객 피드백 반영: 자격번호, 유효기간 자동(취득일 + 2년), 본인 수정(승인 전)

alter table qualifications add column if not exists cert_no text;  -- 자격번호

-- 만료일을 비워 두면 취득일 기준 2년으로 자동 설정
create or replace function qual_default_expiry() returns trigger language plpgsql as $$
begin
  if new.expires_on is null and new.acquired_on is not null then
    new.expires_on := (new.acquired_on + interval '2 years')::date;
  end if;
  return new;
end $$;
create or replace trigger qualifications_default_expiry before insert or update on qualifications
  for each row execute function qual_default_expiry();

-- 본인은 승인 전(대기·반려)인 자격만 고칠 수 있고, 고치면 다시 승인 대기
drop policy if exists p_q_update_own on qualifications;
create policy p_q_update_own on qualifications for update
  using (user_id = auth.uid() and status <> 'approved')
  with check (user_id = auth.uid() and status = 'pending');

-- 반려된 자격도 본인이 삭제 가능 (승인된 자격은 관리자만)
drop policy if exists p_q_delete on qualifications;
create policy p_q_delete on qualifications for delete
  using ((user_id = auth.uid() and status <> 'approved') or is_admin());
