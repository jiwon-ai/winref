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
  if exists (select 1 from competitions where name = '[시연] 2026 용평컵 알파인 스키대회') then
    raise notice '시연 데이터가 이미 있습니다.'; return;
  end if;

  update profiles set role = 'admin' where id = v_admin;
  update profiles set org_status = 'approved', organization = coalesce(organization, '평창알파인클럽') where id = v_org;
  update profiles set region = '강원', sport = '대회전 (GS)', bio = '전국동계체전 기문심판 3년, 주니어 대회 출발심판 다수' where id = v_ref;

  insert into competitions (organizer_id, name, starts_on, ends_on, venue, address, host_org)
  values (v_org, '[시연] 2026 용평컵 알파인 스키대회', current_date + 3, current_date + 4, '용평리조트 레인보우 슬로프', '강원 평창군 대관령면 올림픽로 715', '평창알파인클럽')
  returning id into c1;
  insert into competitions (organizer_id, name, starts_on, venue, host_org)
  values (v_org, '[시연] 하이원 주니어 알파인 챌린지', current_date + 12, '하이원리조트 아테나 슬로프', '정선알파인클럽')
  returning id into c2;
  insert into competitions (organizer_id, name, starts_on, venue, host_org)
  values (v_org, '[시연] 2025 무주 알파인 스키대회', current_date - 20, '무주덕유산리조트 실크로드 슬로프', '무주스키클럽')
  returning id into c3;

  update competitions set discipline = '대회전 (GS), 회전 (SL)' where id = c1;
  update competitions set discipline = '회전 (SL)' where id = c2;
  update competitions set discipline = '슈퍼대회전 (SG)' where id = c3;

  insert into recruitments (competition_id, position, headcount, requirements, deadline, preparation)
  values (c1, '기문심판', 4, '알파인 심판 3급 이상', now() + interval '2 days', '스키복·헬멧·무전기 지참, 07:30 레이스 오피스 집결')
  returning id into r1;
  insert into recruitments (competition_id, position, headcount, requirements, deadline, preparation)
  values (c1, '출발심판', 8, '알파인 심판 자격 보유', now() + interval '2 days', '스키복·헬멧 지참, 출발 구역 근무')
  returning id into r2;
  insert into recruitments (competition_id, position, headcount, requirements, deadline)
  values (c2, '기문심판', 6, '알파인 심판 3급 이상', now() + interval '9 days')
  returning id into r3;
  insert into recruitments (competition_id, position, headcount, is_open)
  values (c3, '기문심판', 2, false)
  returning id into r4;

  -- 심판: 지난 대회 활동완료 1건, 이번 대회 선발 1건
  insert into applications (recruitment_id, user_id, status, attendance, completed_at)
  values (r4, v_ref, 'selected', 'attending', now() - interval '19 days');
  insert into applications (recruitment_id, user_id, status) values (r1, v_ref, 'selected');

  insert into briefings (competition_id, title, body)
  values (c1, '경기 일정 및 배정표', '07:30 레이스 오피스 집결 → 08:00 코스 점검 → 09:00 1차 레이스 출발. 기문 배정표는 현장 배포.');

  insert into qualifications (user_id, name, grade, acquired_on, expires_on, refresher_done, status)
  values (v_ref, '대한스키협회 알파인 심판', '3급', current_date - 700, current_date + 60, false, 'approved');

  insert into courses (title, description, location, starts_at, ends_at, apply_deadline, capacity, is_refresher) values
    ('[시연] 알파인 심판 3급 양성과정', 'FIS 알파인 경기규칙 이론 + 기문심판 실기 평가', 'WINREF 교육장', now() + interval '14 days', now() + interval '15 days', now() + interval '7 days', 30, false),
    ('[시연] 2026 하반기 보수교육', '자격 유지를 위한 필수 보수교육', '온라인(줌)', now() + interval '20 days', now() + interval '20 days 3 hours', now() + interval '10 days', 100, true);

  insert into notices (title, body) values
    ('WINREF 인재은행 앱 오픈 안내', '교육 신청, 대회 심판 지원, 활동이력 관리를 앱에서 할 수 있습니다.');
end $$;
