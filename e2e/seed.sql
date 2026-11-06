-- E2E 시드: 사용자(auth)는 스크립트가 Admin API 로 먼저 만든다.
update profiles set role = 'admin' where id = (select id from auth.users where email = 'admin@test.kr');
update profiles set org_status = 'approved' where id = (select id from auth.users where email = 'org@test.kr');

insert into competitions (organizer_id, name, starts_on, venue, host_org)
select id, '2026 서울 유소년 축구대회', current_date + 1, '잠실 보조경기장', '서울시축구협회'
from auth.users where email = 'org@test.kr';

insert into recruitments (competition_id, position, headcount, requirements, deadline, preparation)
select id, '주심', 2, '3급 이상', now() + interval '3 days', '심판복 지참'
from competitions where name = '2026 서울 유소년 축구대회';

insert into briefings (competition_id, title, body)
select id, '경기 일정 안내', '08:30 집결, 09:00 킥오프' from competitions where name = '2026 서울 유소년 축구대회';

insert into courses (title, description, location, starts_at, apply_deadline, capacity)
values ('3급 심판 양성과정', '이론·실기', 'WINREF 교육장', now() + interval '10 days', now() + interval '5 days', 30);

insert into notices (title, body) values ('WINREF 인재은행 오픈', '앱 오픈을 알려드립니다.');
