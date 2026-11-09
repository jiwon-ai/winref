-- 지도 표시용 대회 장소 주소 (도로명/지번). 장소명(venue)은 화면 표시용으로 그대로 둔다.
alter table competitions add column if not exists address text;
