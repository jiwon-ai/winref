-- 알파인 스키 대회: 경기 종목 (회전·대회전·슈퍼대회전·활강 등)
alter table competitions add column if not exists discipline text;
