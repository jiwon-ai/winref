// Flutter 웹 빌드를 실제 브라우저로 조작하는 E2E 시나리오.
// 환경: APP_URL(정적 서버), DB_URL(psql 접속 문자열)
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';

const APP = process.env.APP_URL ?? 'http://127.0.0.1:8080';
const DB = process.env.DB_URL;
mkdirSync('shots', { recursive: true });

const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`).toString().trim();

let step = 0;
const results = [];
const browser = await chromium.launch();
// 405x720 @8/3 = 1080x1920 (9:16) → Play 스토어 휴대전화 스크린샷 권장 규격
const page = await browser.newPage({ viewport: { width: 405, height: 720 }, deviceScaleFactor: 8 / 3, locale: 'ko-KR' });
page.on('console', (m) => { if (m.type() === 'error') console.log('[console]', m.text()); });

async function shot(name) {
  step++;
  await page.waitForTimeout(600);
  await page.screenshot({ path: `shots/${String(step).padStart(2, '0')}-${name}.png` });
}

// Play 스토어용: 알림(스낵바)·툴팁이 사라진 깨끗한 화면
let storeN = 0;
async function store(name) {
  await page.mouse.move(398, 380); // 툴팁 없는 화면 가장자리
  await page.waitForTimeout(3300);
  storeN++;
  await page.screenshot({ path: `shots/store-${String(storeN).padStart(2, '0')}-${name}.png` });
}

// Flutter 접근성 트리에서 라벨로 요소 찾기
function el(name, role) {
  if (role === 'exact') // 정확히 그 글자인 요소 (목록 항목 등 버튼 역할이 없는 것)
    return page.getByText(name, { exact: true }).or(page.locator(`[aria-label="${name}"]`)).first();
  if (role === 'any!') // 탭/메뉴: 접근성 이름이 '라벨' 또는 '라벨 탭 n개 중 m번째'
    return page.getByRole('button', { name: new RegExp(`^${name}(\\s|$)`) })
      .or(page.getByRole('tab', { name: new RegExp(`^${name}(\\s|$)`) })).first();
  if (role?.endsWith('!')) return page.getByRole(role.slice(0, -1), { name, exact: true }).first();
  return role ? page.getByRole(role, { name, exact: false }).first() : page.getByText(name, { exact: false }).first();
}
async function dumpLabels() {
  const labels = await page.$$eval('flt-semantics, [role]', (ns) =>
    ns.map((n) => `${n.getAttribute('role') ?? ''}:${(n.getAttribute('aria-label') ?? n.textContent ?? '').trim()}`)
      .filter((s) => s.length > 1).slice(0, 80));
  console.log('  화면 요소:', labels.join(' | '));
}
async function tap(name, role) {
  const l = el(name, role);
  try { await l.waitFor({ state: 'visible', timeout: 15000 }); }
  catch (e) {
    await dumpLabels();
    const found = await page.$$eval('*', (ns, t) => ns
      .filter((n) => (n.getAttribute('aria-label') ?? '').includes(t) || ([...n.childNodes].some((c) => c.nodeType === 3 && c.textContent.includes(t))))
      .map((n) => `<${n.tagName.toLowerCase()} role=${n.getAttribute('role')} aria-label=${JSON.stringify(n.getAttribute('aria-label'))} text=${JSON.stringify(n.textContent.slice(0, 40))}>`)
      .slice(0, 15), name);
    console.log('  후보:', found.join(' | '));
    throw new Error(`"${name}" 요소를 찾지 못함`);
  }
  console.log('  tap', name);
  await l.click({ timeout: 10000 });
  await page.waitForTimeout(500);
}
async function type(label, text) {
  const l = page.getByRole('textbox', { name: label, exact: false }).first();
  try { await l.waitFor({ state: 'visible', timeout: 15000 }); }
  catch (e) { await dumpLabels(); throw new Error(`입력칸 "${label}" 을 찾지 못함`); }
  await l.click();
  await page.waitForTimeout(400); // Flutter 입력창 포커스 대기 (첫 글자 유실 방지)
  await page.keyboard.type(text, { delay: 20 });
}
async function retype(label, text) {  // 기존 값을 지우고 새로 입력
  const l = page.getByRole('textbox', { name: label, exact: false }).first();
  await l.waitFor({ state: 'visible', timeout: 15000 });
  await l.click();
  await page.waitForTimeout(400);
  await page.keyboard.press('Control+A');
  await page.keyboard.type(text, { delay: 20 });
}
async function see(text) {
  // Flutter 는 정적 텍스트를 textContent 또는 aria-label 로 노출하므로 둘 다 찾는다
  const l = page.getByText(text, { exact: false }).or(page.locator(`[aria-label*="${text}"]`)).first();
  try { await l.waitFor({ state: 'visible', timeout: 15000 }); }
  catch (e) { await dumpLabels(); throw new Error(`"${text}" 가 화면에 없음`); }
}
async function check(name, fn) {
  try { await fn(); results.push(['PASS', name]); console.log('PASS', name); }
  catch (e) { results.push(['FAIL', name, e.message]); console.log('FAIL', name, '-', e.message); await shot('FAIL-' + name.replace(/[^\p{L}\p{N}]+/gu, '_')); throw e; }
}
async function login(email) {
  await type('이메일', email);
  await type('비밀번호', 'Test1234!');
  await tap('로그인', 'button');
}
async function back() {
  await tap('뒤로', 'button').catch(() => tap('Back', 'button'));
}
async function logout() {
  await tap('메뉴 표시', 'button').catch(() => tap('Show menu', 'button'));
  await tap('로그아웃', 'menuitem');
  await see('WINREF ACADEMY');
}

try {
  await page.goto(APP);
  await check('로그인 화면 표시 (로고·지원사업 표기)', async () => { await see('WINREF ACADEMY'); await see('사회적기업 창업지원사업'); await shot('login'); await store('login'); });

  // 기기별 화면 높이: 갤럭시 S24(384x832, 시스템 바 제외 약 384x760)·소형(360x640)에서 스크롤 없이 들어오는지
  await check('로그인 화면 한 화면 맞춤 (S24·소형)', async () => {
    for (const [w, h, name] of [[384, 760, 'login-s24'], [360, 640, 'login-small']]) {
      await page.setViewportSize({ width: w, height: h });
      await page.waitForTimeout(800);
      const box = await page.getByText('사회적기업 창업지원사업', { exact: false }).or(page.locator('[aria-label*="사회적기업 창업지원사업"]')).first().boundingBox();
      await shot(name);
      if (name === 'login-s24' && (!box || box.y + box.height > h)) throw new Error(`S24 높이에서 하단 표기가 화면 밖 (${box && Math.round(box.y)})`);
    }
    await page.setViewportSize({ width: 405, height: 720 });
    await page.waitForTimeout(500);
  });

  await check('잘못된 비밀번호 안내(한국어)', async () => {
    await type('이메일', 'org@test.kr');
    await type('비밀번호', 'wrong-password');
    await tap('로그인', 'button');
    await see('이메일 또는 비밀번호가 올바르지 않습니다');
  });

  await check('회원가입(심판·교육신청자)', async () => {
    await tap('회원가입', 'button');
    await type('이름', '김심판');
    await type('이메일', 'ref@test.kr');
    await type('비밀번호', 'Test1234!');
    await type('휴대폰', '01012345678');
    await tap('개인정보 수집', 'checkbox');
    await shot('signup');
    await tap('가입하기', 'button');
    await see('다가오는 일정');
    await see('마감 임박 모집');  // 3일 안에 마감되는, 아직 지원 안 한 공고
    const role = sql(`select p.role from profiles p join auth.users u on u.id=p.id where u.email='ref@test.kr'`);
    if (role !== 'referee') throw new Error(`profile role 불일치: '${role}' / users: ${sql(`select string_agg(email||':'||coalesce(raw_user_meta_data::text,''), ' ; ') from auth.users`)}`);
    await shot('referee-home');
  });

  await check('프로필 편집·사진 업로드', async () => {
    await tap('내 프로필·경력 보기');
    await see('보유 자격');
    await tap('편집', 'button');
    await type('활동 지역', '서울');
    await type('주 종목', '축구');
    await type('소개', 'K3리그 부심 3년');
    await tap('저장', 'button');
    await see('서울 · 축구');
    const [chooser] = await Promise.all([page.waitForEvent('filechooser', { timeout: 15000 }), tap('사진 변경', 'button')]);
    await chooser.setFiles('../store/icon-512.png');
    await see('프로필 사진을 변경했습니다');
    const av = sql(`select avatar_path from profiles where name='김심판'`);
    if (!av.startsWith('avatars/')) throw new Error('avatar_path: ' + av);
    if (sql(`select region||'/'||sport from profiles where name='김심판'`) !== '서울/축구') throw new Error('지역·종목 저장 안 됨');
    await shot('profile');
    await back();
  });

  async function goTab(name) {
    await tap(name, 'tab!').catch(() => tap(name, 'button!'));
  }

  await check('대회 조회·심판 지원', async () => {
    await goTab('대회');
    await see('대회 모집');
    await shot('competitions'); await store('competitions');
    await tap('2026 서울 유소년 축구대회');
    await see('잠실 보조경기장');
    await see('서울 송파구 올림픽로 25');
    await see('네이버 지도에서 크게 보기');
    await shot('competition-detail');
    await tap('심판 지원하기', 'button');
    await tap('동의하고 지원', 'button');
    await see('지원완료');
    if (sql(`select count(*) from applications a join profiles p on p.id=a.user_id where p.name='김심판'`) !== '1') throw new Error('지원 저장 안 됨');
    await shot('applied');
    await back();
  });

  await check('검색·필터·캘린더', async () => {
    await tap('내 지역 (서울)', 'checkbox').catch(() => tap('내 지역 (서울)'));
    await see('2026 서울 유소년 축구대회');
    await tap('내 지역 (서울)', 'checkbox').catch(() => tap('내 지역 (서울)'));
    await type('대회명', '부산');
    await see('조건에 맞는 모집 대회가 없습니다');
    await page.keyboard.press('Control+A');
    await page.keyboard.type('잠실', { delay: 20 });
    await see('2026 서울 유소년 축구대회');
    await tap('7일 이내', 'checkbox').catch(() => tap('7일 이내'));
    await see('2026 서울 유소년 축구대회');
    await tap('캘린더 보기', 'button');
    await see('날짜를 선택하면');
    await shot('calendar'); await store('calendar');
    const d = new Date(Date.now() + 864e5);
    await tap(`${d.getMonth() + 1}월 ${d.getDate()}일 일정 1건`, 'button');
    await see('대회 1건');
    await tap('목록 보기', 'button');
  });

  await check('교육 신청', async () => {
    await goTab('교육');
    await see('3급 심판 양성과정');
    await shot('courses');
    await tap('3급 심판 양성과정');
    await tap('교육 신청', 'button');
    await see('신청 취소');
    if (sql(`select count(*) from course_applications a join profiles p on p.id=a.user_id where p.name='김심판' and a.status='applied'`) !== '1')
      throw new Error('교육 신청 저장 안 됨');
    await see('정원 마감');      // 정원 1명 과정 (다른 사람이 신청함)
    await shot('course-applied');
  });

  await check('자격 등록·자격증 사본 업로드', async () => {
    await goTab('자격');
    await tap('자격 등록', 'button');
    await type('자격명', '대한축구협회 심판');
    await type('등급', '3급');
    const [chooser] = await Promise.all([
      page.waitForEvent('filechooser', { timeout: 15000 }),
      page.getByRole('textbox', { name: '자격증 사본', exact: false }).first().click(),
    ]);
    await chooser.setFiles('../store/icon-512.png');
    await page.waitForTimeout(2500);  // 업로드
    await tap('저장', 'button');
    await see('관리자 확인 후 승인됩니다');
    const fp = sql(`select file_path from qualifications q join profiles p on p.id=q.user_id where p.name='김심판'`);
    if (!fp.startsWith('quals/')) throw new Error('사본 경로: ' + fp);
    if (sql(`select count(*) from notifications n join profiles p on p.id=n.user_id where p.role='admin' and n.kind='qual_request'`) !== '1')
      throw new Error('관리자 확인 요청 알림 없음');
    await shot('qualification');
  });

  await check('공지·알림 화면', async () => {
    await tap('알림', 'button');
    await see('알림이 없습니다');
    await back();
  });

  await logout();

  await check('대회관계자: 지원자 선발·참석·활동완료', async () => {
    await login('org@test.kr');
    await see('내 대회');
    await see('검토 대기 3명');   // 홈 보드: 대회별 검토 대기 인원
    await shot('organizer-home'); await store('organizer-home');
    await tap('2026 서울 유소년 축구대회', 'button');
    await see('모집 포지션').catch(() => {});
    await shot('org-recruitments');
    await tap('지원자', 'tab');
    await see('일정 겹침: 경기도 생활체육 리그');   // 같은 날 다른 대회에 선발된 지원자
    await see('주심 선발 0/2');
    await tap('일괄 선택', 'button');
    await tap('김심판', 'checkbox');
    await tap('박심판', 'checkbox');
    await shot('bulk-select'); await store('bulk-select');
    await tap('일괄 선발', 'button');
    await see('주심 선발 2/2');
    if (sql(`select count(*) from applications where status='selected' and user_id in (select id from profiles where name in ('김심판','박심판'))`) !== '2')
      throw new Error('일괄 선발 저장 안 됨');
    if (sql(`select count(*) from notifications n join profiles p on p.id=n.user_id where n.kind='selection' and p.name in ('김심판','박심판')`) !== '2')
      throw new Error('선발 알림 생성 안 됨');
    await tap('김심판');
    await see('활동 완료');      // 경력 카드
    await see('010');            // 연락처
    await shot('applicant-sheet');
    await tap('참석', 'checkbox!');
    await page.waitForTimeout(800);
    await tap('김심판');
    await tap('활동완료 처리', 'button');
    await page.waitForTimeout(800);
    const r = sql(`select status||','||attendance||','||(completed_at is not null) from applications a join profiles p on p.id=a.user_id where p.name='김심판'`);
    if (r !== 'selected,attending,true') throw new Error('DB 상태: ' + r);
    await shot('completed');
  });

  await check('대회관계자 화면에서 뒤로가기', async () => {
    await tap('브리핑', 'tab');
    await see('경기 일정 안내');
    await shot('org-briefings');
    await back();
    await see('선발 2/2');        // 홈 보드 진행률 갱신
    if (Number(sql(`select count(*) from notifications n join profiles p on p.id=n.user_id where p.name='박관계' and n.kind='new_applicant'`)) < 1)
      throw new Error('새 지원자 알림 없음');
    await el('알림 읽지 않음', 'button').waitFor({ state: 'visible', timeout: 10000 });
    await tap('알림 읽지 않음', 'button');
    await see('새 심판 지원');
    await shot('org-notifications');
    await back();
  });

  await check('대회 등록·수정·삭제', async () => {
    await tap('대회 등록', 'button');
    await type('대회명', '삭제 테스트 대회');
    await shot('org-new-competition');
    await page.getByRole('textbox', { name: '시작일', exact: false }).first().click();
    await tap('확인', 'button!');           // 날짜 선택 (오늘)
    await tap('저장', 'button');
    await see('대회를 등록했습니다');
    await tap('삭제 테스트 대회', 'button');
    await tap('대회 수정', 'button');
    await retype('대회명', '삭제 테스트 대회 수정본');
    await tap('저장', 'button');
    await see('대회 정보를 수정했습니다');
    if (sql(`select count(*) from competitions where name='삭제 테스트 대회 수정본'`) !== '1') throw new Error('수정 저장 안 됨');
    await tap('대회 삭제', 'button');
    await tap('삭제', 'button!');
    await see('대회를 삭제했습니다');
    if (sql(`select count(*) from competitions where name like '삭제 테스트%'`) !== '0') throw new Error('삭제 안 됨');
    await logout();
  });

  await check('선발 심판: 참석 응답(불참) → 관계자 알림', async () => {
    await login('ref3@test.kr');
    await see('참석 응답 필요');
    await tap('참석 응답 필요', 'button');
    await see('참석 여부를 알려주세요');
    await el('캘린더에 추가', 'button').waitFor({ state: 'visible', timeout: 10000 });
    await shot('rsvp'); await store('rsvp');
    await tap('불참', 'button!');
    await tap('불참 응답', 'button!');
    await see('불참으로 응답했습니다');
    if (sql(`select attendance from applications a join profiles p on p.id=a.user_id where p.name='박심판'`) !== 'absent')
      throw new Error('불참 저장 안 됨');
    if (sql(`select count(*) from notifications n join profiles p on p.id=n.user_id where p.name='박관계' and n.kind='attendance'`) !== '1')
      throw new Error('관계자 불참 알림 없음');
    await back();
    await logout();
  });

  await check('심판: 선발결과·브리핑·활동이력', async () => {
    await login('ref@test.kr');
    await see('다가오는 일정');
    await tap('알림 읽지 않음 1건', 'button');   // 배지
    await see('심판 선발 안내');
    await tap('모두 읽음', 'button');
    await see('모두 읽음으로 표시했습니다');
    await shot('notifications');
    if (sql(`select count(*) from notifications n join profiles p on p.id=n.user_id where p.name='김심판' and n.read_at is null`) !== '0')
      throw new Error('모두 읽음 저장 안 됨');
    await back();
    await el('알림', 'button!').waitFor({ state: 'visible', timeout: 10000 });  // 배지 사라짐
    await see('활동 완료');
    await shot('referee-dashboard'); await store('referee-dashboard');
    await goTab('내 활동');
    await see('선발');
    await shot('my-applications');
    await tap('2026 서울 유소년 축구대회');
    await see('경기 일정 안내');
    await shot('briefing');
    await el('캘린더에 추가', 'button').waitFor({ state: 'visible', timeout: 10000 });
    await back();
    await tap('활동 이력', 'tab');
    await see('주심');
    await shot('history');
    await goTab('홈');
    await tap('내 프로필·경력 보기');
    await see('포지션별 활동');
    await see('활동 이력 PDF');
    await see('1회');
    await shot('career'); await store('career');
    await back();
    await logout();
  });

  await check('회원 탈퇴', async () => {
    await login('ref2@test.kr');
    await see('D-1');             // 선발된 내일 대회
    await shot('dashboard-closing');
    await goTab('대회');
    await tap('2026 서울 유소년 축구대회');
    await see('같은 날 선발된 대회가 있습니다');
    await shot('clash-warning');
    await back();
    await goTab('홈');
    await tap('메뉴 표시', 'button');
    await tap('회원 탈퇴', 'menuitem');
    await tap('탈퇴', 'button!');
    await see('WINREF ACADEMY');
    if (sql(`select count(*) from auth.users where email='ref2@test.kr'`) !== '0') throw new Error('계정이 삭제되지 않음');
  });

  await check('소셜 로그인 버튼 표시', async () => {
    await see('카카오로 계속하기');
    await see('Google로 계속하기');
  });

  await check('소셜 첫 가입: 가입 정보 입력', async () => {
    await login('social@test.kr');
    await see('가입 정보 입력');
    await shot('onboarding');
    await tap('대회관계자');
    await type('휴대폰', '01099998888');
    await type('소속 기관', '부산시축구협회');
    await tap('개인정보 수집', 'checkbox');
    await tap('가입 완료', 'button');
    await see('기관 승인 대기');
    const r = sql(`select role||','||org_status||','||onboarded||','||(agreed_at is not null) from profiles where name='최소셜'`);
    if (r !== 'organizer,pending,true,true') throw new Error('DB 상태: ' + r);
    await logout();
  });

  await check('관리자: 대시보드·통계', async () => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await login('admin@test.kr');
    await see('대시보드');
    await see('활동완료 누적');
    await shot('admin-dashboard');
  });

  await check('관리자: 자격 확인(사본)·승인', async () => {
    await tap('자격 승인', 'any!');
    await tap('대한축구협회 심판');
    await see('자격증 사본 보기');
    await shot('admin-qualification');
    await tap('승인', 'exact');
    await page.waitForTimeout(800);
    if (sql(`select status from qualifications where name='대한축구협회 심판'`) !== 'approved') throw new Error('승인 저장 안 됨');
  });

  await check('관리자: 회원 검색·엑셀 내보내기', async () => {
    await tap('회원', 'any!');
    await type('이름·연락처', '박관계');
    await see('서울시축구협회');
    const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 15000 }), tap('엑셀 내보내기', 'button')]);
    const name = dl.suggestedFilename();
    const csv = readFileSync(await dl.path(), 'utf8');
    if (!name.startsWith('회원목록_') || !name.endsWith('.csv')) throw new Error('파일명 ' + name);
    if (csv.charCodeAt(0) !== 0xfeff) throw new Error('BOM 없음 (엑셀 한글 깨짐)');
    if (!csv.includes('박관계') || csv.includes('김심판')) throw new Error('검색 결과와 내보낸 내용 불일치');
    await shot('admin-members');
  });

  await check('관리자: 알림 일괄 발송', async () => {
    await tap('공지·알림');
    await tap('알림 발송', 'button');
    await type('제목', '테스트 알림');
    await tap('저장', 'button');
    await tap('전체 회원');
    await page.waitForTimeout(1000);
    const n = sql(`select count(*) from notifications where title='테스트 알림'`);
    if (n !== '5') throw new Error('발송 건수 ' + n); // 관리자·관계자·김심판·박심판·최소셜 (이심판은 탈퇴)
    await shot('admin-broadcast');
  });

  await check('관리자: 교육·대회·공지 화면', async () => {
    await tap('교육', 'any!');
    await see('3급 심판 양성과정');
    await shot('admin-courses');
    await tap('대회', 'any!');
    await see('2026 서울 유소년 축구대회');
    await shot('admin-competitions');
    await tap('공지·알림', 'any!');
    await see('WINREF 인재은행 오픈');
    await shot('admin-notices');
  });
} catch (e) {
  // 첫 실패에서 멈춤 (뒤 단계는 앞 단계 결과에 의존)
} finally {
  await browser.close();
  const fail = results.filter((r) => r[0] === 'FAIL').length;
  console.log(`\n결과: ${results.length - fail} 통과 / ${fail} 실패 (총 시나리오 ${results.length})`);
  process.exit(fail || results.length < 22 ? 1 : 0);
}
