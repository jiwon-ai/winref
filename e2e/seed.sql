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

-- 홈 대시보드 D-day 확인용: 이심판이 선발된 내일 대회
insert into competitions (organizer_id, name, starts_on, venue)
select id, '경기도 생활체육 리그', current_date + 1, '수원 종합운동장' from auth.users where email = 'org@test.kr';
insert into recruitments (competition_id, position, headcount, is_open)
select id, '부심', 1, false from competitions where name = '경기도 생활체육 리그';
insert into applications (recruitment_id, user_id, status)
select r.id, u.id, 'selected' from recruitments r, auth.users u
where r.position = '부심' and u.email = 'ref2@test.kr';

-- 일괄 선발 확인용: 박심판이 서울 대회 주심에 지원
insert into applications (recruitment_id, user_id)
select r.id, u.id from recruitments r join competitions c on c.id = r.competition_id, auth.users u
where c.name = '2026 서울 유소년 축구대회' and r.position = '주심' and u.email = 'ref3@test.kr';

-- 소셜(구글·카카오) 첫 가입 상태 재현: 가입 정보 미입력
update profiles set onboarded = false, agreed_at = null, name = '최소셜'
where id = (select id from auth.users where email = 'social@test.kr');

-- 정원 마감 표시 확인용: 정원 1명 과정에 박심판이 이미 신청
insert into courses (title, description, location, starts_at, apply_deadline, capacity)
values ('소규모 실기 특강', '정원 1명', 'WINREF 교육장', now() + interval '8 days', now() + interval '4 days', 1);
insert into course_applications (course_id, user_id)
select c.id, u.id from courses c, auth.users u where c.title = '소규모 실기 특강' and u.email = 'ref3@test.kr';

-- 지도 표시용 주소
update competitions set address = '서울 송파구 올림픽로 25' where name = '2026 서울 유소년 축구대회';

-- 일정 겹침 확인용: 내일 경기도 리그에 선발된 이심판이 같은 날 서울 대회에도 지원
insert into applications (recruitment_id, user_id)
select r.id, u.id from recruitments r join competitions c on c.id = r.competition_id, auth.users u
where c.name = '2026 서울 유소년 축구대회' and r.position = '주심' and u.email = 'ref2@test.kr';
