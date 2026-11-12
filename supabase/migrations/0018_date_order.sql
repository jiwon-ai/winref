-- 날짜 순서를 서버에서도 강제 (종료일 ≥ 시작일 등). 기존 데이터는 검사하지 않고(NOT VALID) 새로 저장·수정하는 값부터 적용.
-- 여러 번 실행해도 안전.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'competitions_date_order') then
    alter table competitions add constraint competitions_date_order
      check (ends_on is null or ends_on >= starts_on) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'courses_date_order') then
    alter table courses add constraint courses_date_order
      check ((ends_at is null or starts_at is null or ends_at >= starts_at)
         and (apply_deadline is null or starts_at is null or apply_deadline <= starts_at)) not valid;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'qualifications_date_order') then
    alter table qualifications add constraint qualifications_date_order
      check (expires_on is null or acquired_on is null or expires_on >= acquired_on) not valid;
  end if;
end $$;
