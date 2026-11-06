// Flutter 웹 빌드를 실제 브라우저로 조작하는 E2E 시나리오.
// 환경: APP_URL(정적 서버), DB_URL(psql 접속 문자열)
import { chromium } from 'playwright';
import { execSync } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const APP = process.env.APP_URL ?? 'http://127.0.0.1:8080';
const DB = process.env.DB_URL;
mkdirSync('shots', { recursive: true });

const sql = (q) => execSync(`psql "${DB}" -tAc "${q.replace(/"/g, '\\"')}"`).toString().trim();

let step = 0;
const results = [];
const browser = await chromium.launch();
// 405x720 @2x = 810x1440 (9:16) → Play 스토어 휴대전화 스크린샷 규격에 맞춤
const page = await browser.newPage({ viewport: { width: 405, height: 720 }, deviceScaleFactor: 2, locale: 'ko-KR' });
page.on('console', (m) => { if (m.type() === 'error') console.log('[console]', m.text()); });

async function shot(name) {
  step++;
  await page.waitForTimeout(600);
  await page.screenshot({ path: `shots/${String(step).padStart(2, '0')}-${name}.png` });
}

// Flutter 접근성 트리에서 라벨로 요소 찾기
function el(name, role) {
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
  catch (e) { await dumpLabels(); throw new Error(`"${name}" 요소를 찾지 못함`); }
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
  await check('로그인 화면 표시', async () => { await see('WINREF ACADEMY'); await shot('login'); });

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
    const role = sql(`select p.role from profiles p join auth.users u on u.id=p.id where u.email='ref@test.kr'`);
    if (role !== 'referee') throw new Error(`profile role 불일치: '${role}' / users: ${sql(`select string_agg(email||':'||coalesce(raw_user_meta_data::text,''), ' ; ') from auth.users`)}`);
    await shot('referee-home');
  });

  async function goTab(name) {
    await tap(name, 'tab!').catch(() => tap(name, 'button!'));
  }

  await check('대회 조회·심판 지원', async () => {
    await goTab('대회');
    await see('대회 모집');
    await tap('2026 서울 유소년 축구대회');
    await see('잠실 보조경기장');
    await shot('competition-detail');
    await tap('심판 지원하기', 'button');
    await see('지원완료');
    if (sql(`select count(*) from applications a join profiles p on p.id=a.user_id where p.name='김심판'`) !== '1') throw new Error('지원 저장 안 됨');
    await shot('applied');
    await back();
  });

  await check('교육 신청', async () => {
    await goTab('교육');
    await tap('3급 심판 양성과정');
    await tap('교육 신청', 'button');
    await see('신청 취소');
    if (sql(`select count(*) from course_applications where status='applied'`) !== '1') throw new Error('교육 신청 저장 안 됨');
    await shot('course-applied');
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
    await shot('organizer-home');
    await tap('2026 서울 유소년 축구대회');
    await tap('지원자', 'tab');
    await tap('김심판');
    await shot('applicant-sheet');
    await tap('선발', 'checkbox!');
    await page.waitForTimeout(800);
    await tap('김심판');
    await tap('참석', 'checkbox!');
    await page.waitForTimeout(800);
    await tap('김심판');
    await tap('활동완료 처리', 'button');
    await page.waitForTimeout(800);
    const r = sql(`select status||','||attendance||','||(completed_at is not null) from applications a join profiles p on p.id=a.user_id where p.name='김심판'`);
    if (r !== 'selected,attending,true') throw new Error('DB 상태: ' + r);
    await shot('completed');
  });

  await check('대회관계자 화면에서 뒤로가기·로그아웃', async () => {
    await back();
    await logout();
  });

  await check('심판: 선발결과·브리핑·활동이력', async () => {
    await login('ref@test.kr');
    await see('다가오는 일정');
    await see('활동 완료');
    await shot('referee-dashboard');
    await goTab('내 활동');
    await see('선발');
    await tap('2026 서울 유소년 축구대회');
    await see('경기 일정 안내');
    await shot('briefing');
    await back();
    await tap('활동 이력', 'tab');
    await see('주심');
    await shot('history');
    await logout();
  });

  await check('회원 탈퇴', async () => {
    await login('ref2@test.kr');
    await see('D-1');             // 선발된 내일 대회
    await see('마감 임박 모집');  // 3일 내 마감, 미지원 공고
    await shot('dashboard-closing');
    await tap('메뉴 표시', 'button');
    await tap('회원 탈퇴', 'menuitem');
    await tap('탈퇴', 'button!');
    await see('WINREF ACADEMY');
    if (sql(`select count(*) from auth.users where email='ref2@test.kr'`) !== '0') throw new Error('계정이 삭제되지 않음');
  });

  await check('관리자: 대시보드·통계', async () => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await login('admin@test.kr');
    await see('대시보드');
    await see('활동완료 누적');
    await shot('admin-dashboard');
  });

  await check('관리자: 알림 일괄 발송', async () => {
    await tap('공지·알림');
    await tap('알림 발송', 'button');
    await type('제목', '테스트 알림');
    await tap('저장', 'button');
    await tap('전체 회원');
    await page.waitForTimeout(1000);
    const n = sql(`select count(*) from notifications where title='테스트 알림'`);
    if (n !== '3') throw new Error('발송 건수 ' + n); // 관리자·관계자·김심판 (이심판은 탈퇴)
    await shot('admin-broadcast');
  });
} catch (e) {
  // 첫 실패에서 멈춤 (뒤 단계는 앞 단계 결과에 의존)
} finally {
  await browser.close();
  const fail = results.filter((r) => r[0] === 'FAIL').length;
  console.log(`\n결과: ${results.length - fail} 통과 / ${fail} 실패 (총 시나리오 ${results.length})`);
  process.exit(fail || results.length < 11 ? 1 : 0);
}
