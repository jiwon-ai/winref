-- 고객 시연용 데이터. 앱에서 아래 3개 이메일로 먼저 가입한 뒤 SQL Editor 에서 실행한다.
--   관리자    : 심판 유형으로 가입 (아래에서 관리자로 바꿈)
--   대회관계자 : '대회관계자' 유형으로 가입
--   심판      : '심판·교육신청자' 유형으로 가입
-- 이메일 3개만 실제 가입한 주소로 바꾸면 된다. 여러 번 실행해도 시연 데이터는 중복되지 않는다.
do $$
declare
  admin_email text := 'admin@example.com';      -- ← 바꾸기
  org_email   text := 'organizer@example.com';  -- ← 바꾸기
  ref_email   text := 'referee@example.com';    -- ← 바꾸기
  v_admin uuid; v_org uuid; v_ref uuid;
  c1 bigint; c2 bigint; c3 bigint; r1 bigint; r2 bigint; r3 bigint; r4 bigint;
begin
  select id into v_admin from auth.users where email = admin_email;
  select id into v_org   from auth.users where email = org_email;
  select id into v_ref   from auth.users where email = ref_email;
  if v_admin is null or v_org is null or v_ref is null then
    raise exception '가입되지 않은 이메일이 있습니다. 관리자=%, 관계자=%, 심판=%', v_admin, v_org, v_ref;
  end if;
  if exists (select 1 from competitions where name = '[시연] 2026 서울 유소년 축구 페스티벌') then
    raise notice '시연 데이터가 이미 있습니다.'; return;
  end if;

  update profiles set role = 'admin' where id = v_admin;
  update profiles set org_status = 'approved', organization = coalesce(organization, '서울시축구협회') where id = v_org;
  update profiles set region = '서울', sport = '축구', bio = 'K3리그 부심 3년, 유소년 대회 주심 다수' where id = v_ref;

  insert into competitions (organizer_id, name, starts_on, ends_on, venue, host_org)
  values (v_org, '[시연] 2026 서울 유소년 축구 페스티벌', current_date + 3, current_date + 4, '잠실 보조경기장', '서울시축구협회')
  returning id into c1;
  insert into competitions (organizer_id, name, starts_on, venue, host_org)
  values (v_org, '[시연] 경기도 생활체육 축구 리그', current_date + 12, '수원 종합운동장', '경기도체육회')
  returning id into c2;
  insert into competitions (organizer_id, name, starts_on, venue, host_org)
  values (v_org, '[시연] 전국 대학 풋살 챔피언십', current_date - 20, '인천 남동체육관', '대학스포츠협의회')
  returning id into c3;

  insert into recruitments (competition_id, position, headcount, requirements, deadline, preparation)
  values (c1, '주심', 4, '3급 이상 자격 보유', now() + interval '2 days', '심판복·호루라기 지참, 08:30 집결')
  returning id into r1;
  insert into recruitments (competition_id, position, headcount, requirements, deadline, preparation)
  values (c1, '부심', 8, '4급 이상 자격 보유', now() + interval '2 days', '심판복·깃발 지참')
  returning id into r2;
  insert into recruitments (competition_id, position, headcount, requirements, deadline)
  values (c2, '주심', 6, '3급 이상', now() + interval '9 days')
  returning id into r3;
  insert into recruitments (competition_id, position, headcount, is_open)
  values (c3, '주심', 2, false)
  returning id into r4;

  -- 심판: 지난 대회 활동완료 1건, 이번 대회 선발 1건
  insert into applications (recruitment_id, user_id, status, attendance, completed_at)
  values (r4, v_ref, 'selected', 'attending', now() - interval '19 days');
  insert into applications (recruitment_id, user_id, status) values (r1, v_ref, 'selected');

  insert into briefings (competition_id, title, body)
  values (c1, '경기 일정 및 배정표', '08:30 본부석 집결 → 09:00 1경기 킥오프. 배정표는 현장 배포.');

  insert into qualifications (user_id, name, grade, acquired_on, expires_on, refresher_done, status)
  values (v_ref, '대한축구협회 심판', '3급', current_date - 700, current_date + 60, false, 'approved');

  insert into courses (title, description, location, starts_at, ends_at, apply_deadline, capacity, is_refresher) values
    ('[시연] 3급 심판 양성과정', '경기규칙 이론 + 실기 평가', 'WINREF 교육장', now() + interval '14 days', now() + interval '15 days', now() + interval '7 days', 30, false),
    ('[시연] 2026 하반기 보수교육', '자격 유지를 위한 필수 보수교육', '온라인(줌)', now() + interval '20 days', now() + interval '20 days 3 hours', now() + interval '10 days', 100, true);

  insert into notices (title, body) values
    ('WINREF 인재은행 앱 오픈 안내', '교육 신청, 대회 심판 지원, 활동이력 관리를 앱에서 할 수 있습니다.');
end $$;
