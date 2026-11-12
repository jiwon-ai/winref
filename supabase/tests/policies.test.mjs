import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'fs';

const db = new PGlite();
// Supabase 환경 최소 스텁
await db.exec(`
create schema auth; create schema storage;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb, raw_app_meta_data jsonb, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id serial primary key, bucket_id text, name text);
alter table storage.objects enable row level security;
create role authenticated; create role anon;
`);
await db.exec(readFileSync(process.argv[2], 'utf8'));
await db.exec(`grant usage on schema public, auth to authenticated;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant execute on all functions in schema public, auth to authenticated;`);

const ADMIN = '00000000-0000-0000-0000-00000000000a';
const REF = '00000000-0000-0000-0000-00000000000b';
const REF2 = '00000000-0000-0000-0000-00000000000d';
const ORG = '00000000-0000-0000-0000-00000000000c';

let pass = 0, fail = 0;
const ok = (c, m) => { if (c) { pass++; console.log('PASS', m); } else { fail++; console.log('FAIL', m); } };
async function as(uid, sql, params = []) {
  await db.exec(`reset role; select set_config('test.uid', '${uid ?? ''}', false); set role authenticated;`);
  try { return { rows: (await db.query(sql, params)).rows }; }
  catch (e) { return { err: e.message }; }
  finally { await db.exec('reset role'); }
}

// 가입
await db.exec(`insert into auth.users values
 ('${ADMIN}', '{"name":"관리자","role":"admin","phone":"01011110004"}'),
 ('${REF}', '{"name":"심판일","phone":"01011110001"}'),
 ('${REF2}', '{"name":"심판이","phone":"01011110002"}'),
 ('${ORG}', '{"name":"관계자","role":"organizer","organization":"OO협회","phone":"01011110003"}');`);
let r = (await db.query(`select id, role, org_status from profiles order by id`)).rows;
ok(r.find(x => x.id === ADMIN).role === 'referee', '가입으로 admin 권한 획득 불가');
ok(r.find(x => x.id === ORG).org_status === 'pending', '대회관계자 가입 시 승인 대기');
await db.exec(`update profiles set role='admin' where id='${ADMIN}'`); // 운영자가 콘솔에서 지정

ok((await as(REF, `update profiles set role='admin' where id=$1`, [REF])).err, '사용자가 자기 role 변경 불가');
ok((await as(REF, `select * from profiles`)).rows.length === 1, '타인 프로필 조회 불가');

ok((await as(ORG, `insert into competitions (organizer_id,name,starts_on) values ($1,'대회A', current_date+1)`, [ORG])).err, '미승인 관계자 대회 등록 불가');
ok(!(await as(ADMIN, `update profiles set org_status='approved' where id=$1`, [ORG])).err, '관리자 기관 승인');
let c = await as(ORG, `insert into competitions (organizer_id,name,starts_on,venue) values ($1,'대회A', current_date+1,'잠실') returning id`, [ORG]);
ok(c.rows?.length === 1, '승인 관계자 대회 등록');
let rec = await as(ORG, `insert into recruitments (competition_id,position,headcount) values (${c.rows[0].id},'주심',2) returning id`);
ok(rec.rows?.length === 1, '모집공고 작성');
const RID = rec.rows[0].id;

ok((await as(ORG, `insert into applications (recruitment_id,user_id) values (${RID},$1)`, [ORG])).err, '관계자는 심판 지원 불가');
ok(!(await as(REF, `insert into applications (recruitment_id,user_id) values (${RID},$1)`, [REF])).err, '심판 지원');
ok(!(await as(REF2, `insert into applications (recruitment_id,user_id) values (${RID},$1)`, [REF2])).err, '심판2 지원');
ok((await as(REF, `update applications set status='selected' where user_id=$1`, [REF])).err, '심판 셀프 선발 불가');
ok(!(await as(REF2, `update applications set status='cancelled' where user_id=$1`, [REF2])).err, '지원 취소');
ok(!(await as(REF2, `update applications set status='applied' where user_id=$1`, [REF2])).err, '재지원');
ok((await as(REF2, `update applications set status='selected' where user_id=$1`, [REF2])).err, '재지원 후 셀프선발 불가');
ok((await as(ORG, `select * from profiles where role='referee'`)).rows.length === 2, '관계자가 지원자 프로필 조회');

ok((await as(ORG, `update applications set completed_at=now() where user_id=$1`, [REF])).err, '미선발자 활동완료 불가');
await as(ORG, `update applications set status='selected', attendance='attending' where user_id=$1`, [REF]);
await as(ORG, `update applications set status='rejected' where user_id=$1`, [REF2]);

await as(ORG, `insert into briefings (competition_id,title) values (${c.rows[0].id},'브리핑')`);
ok((await as(REF, `select * from briefings`)).rows.length === 1, '선발 심판 브리핑 열람');
ok((await as(REF2, `select * from briefings`)).rows.length === 0, '미선발 심판 브리핑 차단');

await db.exec(`select enqueue_auto_notifications(); select enqueue_auto_notifications();`);
ok((await db.query(`select count(*)::int n from notifications where kind='competition_d1'`)).rows[0].n === 1, 'D-1 알림 1건(중복 방지)');

ok(!(await as(ORG, `update applications set completed_at=now() where user_id=$1`, [REF])).err, '선발자 활동완료');
ok((await as(REF, `select * from activity_history`)).rows.length === 1, '활동이력 반영');
ok((await as(REF2, `select * from activity_history`)).rows.length === 0, '타인 이력 미노출');

ok((await as(REF, `select admin_stats()`)).err, '비관리자 통계 차단');
const s = await as(ADMIN, `select admin_stats() s`);
console.log(JSON.stringify(s.rows?.[0]?.s));
ok(s.rows?.[0]?.s?.completed_activities === 1, '관리자 통계');


ok((await as(REF, `select admin_broadcast('t','b',null)`)).err, '비관리자 알림발송 차단');
ok((await as(ADMIN, `select admin_broadcast('t','b','referee') n`)).rows?.[0]?.n === 2, '관리자 심판 대상 발송 2명');
await db.exec(`insert into storage.objects (bucket_id,name) values ('files','briefings/${c.rows[0].id}/a.pdf'),('files','notices/x.pdf')`);
await db.exec(`grant all on storage.objects to authenticated; grant usage on schema storage to authenticated; grant usage on all sequences in schema storage to authenticated;`);
ok((await as(REF, `select * from storage.objects`)).rows.length === 2, '선발 심판: 브리핑+공지 파일 열람');
ok((await as(REF2, `select * from storage.objects`)).rows.length === 1, '미선발 심판: 공지 파일만');

await db.exec(`create role anon`).catch(()=>{});
// --- 0004: 경력 요약·알림 트리거·프로필 사진 ---
const notiCount = async (u, kind) => (await db.query(`select count(*)::int n from notifications where user_id='${u}' and kind='${kind}'`)).rows[0].n;
ok(await notiCount(REF, 'selection') === 1, '선발 시 심판에게 선발 알림');
ok(await notiCount(REF2, 'selection') === 1, '미선발 시 결과 알림');
ok(await notiCount(REF, 'briefing') === 1 && await notiCount(REF2, 'briefing') === 0, '브리핑 등록 알림은 선발자만');
const sum = await as(REF, `select referee_summary($1) s`, [REF]);
ok(sum.rows?.[0]?.s?.completed === 1 && sum.rows[0].s.by_position['주심'] === 1, '본인 경력 요약 (활동 1회·주심)');
ok(!(await as(ORG, `select referee_summary($1)`, [REF])).err, '관계자: 자기 공고 지원자 경력 조회');
ok((await as(REF2, `select referee_summary($1)`, [REF])).err, '다른 심판 경력 조회 차단');
const qid = (await as(REF, `insert into qualifications (user_id,name,grade) values ($1,'축구심판','3급') returning id`, [REF])).rows[0].id;
await as(ADMIN, `update qualifications set status='approved' where id=${qid}`);
ok(await notiCount(REF, 'qualification') === 1, '자격 승인 알림');
ok(!(await as(REF, `insert into storage.objects (bucket_id,name) values ('files','avatars/${REF}/me.png')`)).err, '본인 프로필 사진 업로드');
ok((await as(REF, `insert into storage.objects (bucket_id,name) values ('files','avatars/${REF2}/x.png')`)).err, '타인 폴더 업로드 차단');
ok((await as(REF, `insert into storage.objects (bucket_id,name) values ('files','notices/x2.pdf')`)).err, '심판의 일반 파일 업로드 차단');
ok(!(await as(REF, `update profiles set region='서울', sport='축구', bio='K리그 3년' where id=$1`, [REF])).err, '프로필 확장 필드 수정');

// --- 0005: 소셜 가입 ---
const SOC = '00000000-0000-0000-0000-0000000000e1';
await db.exec(`insert into auth.users values ('${SOC}', '{"full_name":"구글 사용자","role":"organizer"}', '{"provider":"google"}', 'g@test.kr')`);
let sp = (await db.query(`select role, onboarded, name, org_status from profiles where id='${SOC}'`)).rows[0];
ok(sp.onboarded === false && sp.role === 'referee' && sp.org_status === null, '소셜 가입: 가입정보 미입력·메타데이터 role 무시');
ok(sp.name === '구글 사용자', '소셜 가입: 제공자 이름 사용');
ok((await as(SOC, `update profiles set role='admin', onboarded=true where id=$1`, [SOC])).err, '소셜 가입자 관리자 자가지정 차단');
ok((await as(SOC, `update profiles set role='organizer', org_status='approved', onboarded=true where id=$1`, [SOC])).err, '소셜 가입자 기관 자가승인 차단');
ok((await as(SOC, `update profiles set role='organizer', org_status='pending', onboarded=true, phone='01011112222', agreed_at=now() where id=$1`, [SOC])).err, '이름 규칙 위반(공백 포함) 상태로 가입 확정 차단');
ok(!(await as(SOC, `update profiles set name='구글사용자', role='organizer', org_status='pending', onboarded=true, phone='01011112222', agreed_at=now() where id=$1`, [SOC])).err, '소셜 가입 정보 확정(대회관계자·승인대기)');
ok((await as(SOC, `update profiles set role='referee', org_status=null where id=$1`, [SOC])).err, '확정 후 유형 재변경 차단');
ok((await as(REF2, `update profiles set onboarded=false where id=$1`, [REF2])).err, '이메일 가입자 onboarded 조작 차단');
ok((await db.query(`select onboarded from profiles where id='${REF2}'`)).rows[0].onboarded === true, '이메일 가입은 가입정보 완료 상태');

// --- 0015: 이름 규칙 (한글만, 띄어쓰기 없이 2~10자) ---
const EN = '00000000-0000-0000-0000-0000000000e2';
await db.exec(`insert into auth.users values ('${EN}', '{"name":"Jiwon"}', '{"provider":"email"}', 'en@test.kr')`);
ok((await db.query(`select onboarded from profiles where id='${EN}'`)).rows[0].onboarded === false, '이메일 가입 이름이 영문이면 가입 정보 입력 화면으로');
const KK = '00000000-0000-0000-0000-0000000000e3';
await db.exec(`insert into auth.users values ('${KK}', '{"nickname":"지원😊"}', '{"provider":"kakao"}', 'kk@test.kr')`);
ok((await as(KK, `update profiles set name='지원😊', phone='01012345678', onboarded=true, agreed_at=now() where id=$1`, [KK])).err, '이모지 이름으로 가입 확정 차단');
ok((await as(KK, `update profiles set name='김지원', phone='23252', onboarded=true, agreed_at=now() where id=$1`, [KK])).err, '잘못된 번호로 가입 확정 차단');
ok(!(await as(KK, `update profiles set name='김지원', phone='01012345678', onboarded=true, agreed_at=now() where id=$1`, [KK])).err, '한글 이름·올바른 번호로 가입 확정');
for (const bad of ['Jiwon', '김 지원', '김', '김지원1', '김-지원']) {
  ok((await as(KK, `update profiles set name=$2 where id=$1`, [KK, bad])).err, `이름 수정 차단: ${bad}`);
}
ok(!(await as(KK, `update profiles set region='강원' where id=$1`, [KK])).err, '이름 외 항목 수정은 영향 없음');
ok(!(await as(ADMIN, `update profiles set name='박지원' where id=$1`, [KK])).err, '관리자 이름 수정(규칙 준수)');
for (const bad of ['23252', '010-1234-5678', '0101234567', '010123456789', '02123456789', '01212345678']) {
  ok((await as(KK, `update profiles set phone=$2 where id=$1`, [KK, bad])).err, `번호 수정 차단: ${bad}`);
}
ok(!(await as(KK, `update profiles set phone='0111234567' where id=$1`, [KK])).err, '011 10자리 허용');
const BADPH = '00000000-0000-0000-0000-0000000000e4';
await db.exec(`insert into auth.users values ('${BADPH}', '{"name":"홍길동","phone":"23252"}', '{"provider":"email"}', 'ph@test.kr')`);
ok((await db.query(`select onboarded from profiles where id='${BADPH}'`)).rows[0].onboarded === false, '이메일 가입 번호가 잘못되면 가입 정보 입력 화면으로');

// --- 0006: 정원·대회 삭제 보호·처리자 알림·자격증 사본 ---
const nc = async (u, kind) => (await db.query(`select count(*)::int n from notifications where user_id='${u}' and kind='${kind}'`)).rows[0].n;
ok(await nc(ORG, 'new_applicant') === 2, '새 지원자 → 관계자 알림 (2명)');
ok(await nc(ADMIN, 'org_request') === 1, '기관 승인 요청 → 관리자 알림');
ok(await nc(ADMIN, 'qual_request') === 1, '자격 등록 → 관리자 확인 요청 알림');
const q2 = (await as(REF2, `insert into qualifications (user_id,name,grade) values ($1,'알파인스키 국내심판','2급 신규') returning id`, [REF2])).rows[0].id;
ok(await nc(ADMIN, 'qual_request') === 2, '두 번째 자격 등록 → 관리자 알림');
await as(ADMIN, `update qualifications set status='rejected' where id=${q2}`);
ok(!(await as(REF2, `update qualifications set grade='2급 보수', status='pending' where id=${q2}`)).err, '반려된 자격 수정 후 재제출');
ok(await nc(ADMIN, 'qual_request') === 3, '재제출 → 관리자 재확인 요청 알림');
ok(await nc(REF2, 'qual_request') === 0, '재제출해도 본인에게 확인 요청 알림 없음');
ok(await nc(REF, 'qual_request') === 0, '자격 확인 요청 알림은 요청한 심판에게 가지 않음');
ok((await db.query(`select count(*)::int n from notifications where kind='qual_request' and user_id not in (select id from profiles where role='admin')`)).rows[0].n === 0, '자격 확인 요청 알림은 관리자에게만');
const cid = (await as(ADMIN, `insert into courses (title, capacity) values ('정원1 과정', 1) returning id`)).rows[0].id;
ok(!(await as(REF, `insert into course_applications (course_id,user_id) values (${cid},$1)`, [REF])).err, '정원 내 신청');
const full = await as(REF2, `insert into course_applications (course_id,user_id) values (${cid},$1)`, [REF2]);
ok(full.err?.includes('정원'), '정원 초과 신청 차단');
ok(Number((await as(REF2, `select taken from course_seats() where course_id=${cid}`)).rows?.[0]?.taken) === 1, '잔여석 계산(타인 신청 수 노출, 개인정보 없음)');
await as(REF, `update course_applications set status='cancelled' where course_id=${cid} and user_id=$1`, [REF]);
ok(!(await as(REF2, `insert into course_applications (course_id,user_id) values (${cid},$1)`, [REF2])).err, '취소로 생긴 자리에 신청');
ok(!(await as(ADMIN, `update course_applications set status='confirmed' where course_id=${cid} and user_id='${REF2}'`)).err, '신청→확정은 정원 재검사 없이 허용');
ok((await as(ADMIN, `update course_applications set status='confirmed' where course_id=${cid} and user_id='${REF}'`)).err, '정원 찬 상태에서 취소건 되살리기 차단');
ok((await as(ORG, `delete from competitions where id=${c.rows[0].id}`)).err, '활동완료 기록 있는 대회 삭제 차단');
const cB = (await as(ORG, `insert into competitions (organizer_id,name,starts_on) values ($1,'삭제용', current_date+5) returning id`, [ORG])).rows[0].id;
ok(!(await as(ORG, `delete from competitions where id=${cB}`)).err, '기록 없는 대회 삭제');
ok(!(await as(REF, `insert into storage.objects (bucket_id,name) values ('files','quals/${REF}/c.png')`)).err, '본인 자격증 사본 업로드');
ok((await as(REF2, `insert into storage.objects (bucket_id,name) values ('files','quals/${REF}/x.png')`)).err, '타인 폴더 사본 업로드 차단');
const qn = async (u) => (await as(u, `select count(*)::int n from storage.objects where name like 'quals/%'`)).rows[0].n;
ok(await qn(REF) === 1 && await qn(ADMIN) === 1 && await qn(ORG) === 1, '사본 열람: 본인·관리자·지원받은 관계자');
ok(await qn(REF2) === 0, '사본 열람 차단: 다른 심판');
ok(await qn(SOC) === 0, '사본 열람 차단: 지원받지 않은 관계자');

// --- 0008: 참석 응답·일정 겹침 ---
const c2 = (await as(ORG, `insert into competitions (organizer_id,name,starts_on) values ($1,'같은날 대회', current_date+1) returning id`, [ORG])).rows[0].id;
const r2 = (await as(ORG, `insert into recruitments (competition_id,position,headcount) values (${c2},'부심',1) returning id`)).rows[0].id;
await as(REF2, `insert into applications (recruitment_id,user_id) values (${r2},$1)`, [REF2]);
ok((await as(REF2, `update applications set attendance='attending' where recruitment_id=${r2} and user_id=$1`, [REF2])).err, '선발 전 참석 응답 차단');
await as(ORG, `update applications set status='selected' where recruitment_id=${r2}`);
ok(!(await as(REF2, `update applications set attendance='absent' where recruitment_id=${r2} and user_id=$1`, [REF2])).err, '선발 후 본인 불참 응답');
ok((await db.query(`select count(*)::int n from notifications where user_id='${ORG}' and kind='attendance' and title='심판 불참 응답'`)).rows[0].n === 1, '불참 응답 → 관계자 알림');
ok((await as(REF2, `update applications set attendance='unknown' where recruitment_id=${r2} and user_id=$1`, [REF2])).err, '참석 응답은 참석/불참만');
ok((await as(REF, `update applications set attendance='absent' where user_id=$1 and completed_at is not null`, [REF])).err, '활동완료 후 참석 응답 변경 차단');
const conf = await as(ORG, `select * from selection_conflicts(${c.rows[0].id})`);
ok(conf.rows?.length === 1 && conf.rows[0].user_id === REF2 && conf.rows[0].competition_name === '같은날 대회', '일정 겹침: 같은 날 다른 대회 선발자 표시');
ok((await as(ORG, `select * from selection_conflicts(${c2})`)).rows?.length === 0, '일정 겹침 없음');
ok((await as(REF, `select * from selection_conflicts(${c2})`)).err, '일정 겹침 조회는 관계자·관리자만');

// 이메일(아이디) 동기화·보호, 관리자 탈퇴 처리
await db.exec(`update auth.users set email='ref2@x.kr' where id='${REF2}'`);
ok((await db.query(`select email from profiles where id='${REF2}'`)).rows[0].email === 'ref2@x.kr', '가입 이메일이 프로필에 동기화');
await as(REF2, `update profiles set email='fake@x.kr' where id=$1`, [REF2]);
ok((await db.query(`select email from profiles where id='${REF2}'`)).rows[0].email === 'ref2@x.kr', '본인이 이메일 칸 임의 변경 불가');
ok((await as(REF, `select admin_delete_user($1)`, [REF2])).err, '일반 회원은 다른 회원 탈퇴 불가');
ok((await as(ADMIN, `select admin_delete_user($1)`, [ADMIN])).err, '관리자 본인 탈퇴 처리 불가');
ok(!(await as(ADMIN, `select admin_delete_user($1)`, [REF2])).err, '관리자가 회원 탈퇴 처리');
ok((await db.query(`select count(*)::int n from profiles where id='${REF2}'`)).rows[0].n === 0, '탈퇴 처리 후 프로필 삭제');

ok((await as(ADMIN, `select delete_my_account()`)).err, '관리자 탈퇴 차단');
ok(!(await as(REF, `select delete_my_account()`)).err, '심판 탈퇴');
ok((await db.query(`select count(*)::int n from applications where user_id='${REF}'`)).rows[0].n === 0, '탈퇴 시 지원·이력 삭제');
ok(!(await as(ORG, `select delete_my_account()`)).err, '관계자 탈퇴');
ok((await db.query(`select count(*)::int n from competitions where organizer_id is null`)).rows[0].n === 2, '관계자 탈퇴 후 대회 보존 (2개)');
// --- 0019: 휴대폰 번호 중복 가입 방지 ---
const G1 = '00000000-0000-0000-0000-0000000000f1';
await db.exec(`insert into auth.users values ('${G1}', '{"full_name":"구글중복"}', '{"provider":"google"}', 'g1@test.kr')`);
const used = (await db.query(`select phone from profiles where onboarded and phone is not null limit 1`)).rows[0].phone;
ok((await as(null, `select phone_in_use($1) v`, [used])).rows?.[0]?.v === true, '가입 전 확인: 사용 중인 번호');
ok((await as(null, `select phone_in_use('01099990000') v`)).rows?.[0]?.v === false, '가입 전 확인: 새 번호');
{ const r = await as(G1, `update profiles set name='구글중복', phone=$2, onboarded=true, agreed_at=now() where id=$1`, [G1, used]); ok(r.err?.includes('이미 가입된 휴대폰'), '구글 가입 확정 시 기존 번호 차단'); }
ok(!(await as(G1, `update profiles set name='구글중복', phone='01099990000', onboarded=true, agreed_at=now() where id=$1`, [G1])).err, '새 번호로 가입 확정');
ok((await as(G1, `update profiles set phone=$2 where id=$1`, [G1, used])).err?.includes('이미 가입된 휴대폰'), '내 정보에서 타인 번호로 변경 차단');
const E2 = '00000000-0000-0000-0000-0000000000f2';
await db.exec(`insert into auth.users values ('${E2}', '{"name":"이메일중복","phone":"01099990000"}', '{"provider":"email"}', 'e2@test.kr')`);
const e2 = (await db.query(`select onboarded, phone from profiles where id='${E2}'`)).rows[0];
ok(e2.onboarded === false && e2.phone === null, '이메일 가입 번호 중복 → 가입 정보 입력 화면으로, 번호 비움');

// --- 0018: 날짜 순서 ---
ok((await as(ADMIN, `insert into competitions (name, starts_on, ends_on) values ('순서오류', '2027-01-06', '2026-12-02')`)).err?.includes('competitions_date_order'), '대회 종료일 < 시작일 차단');
ok(!(await as(ADMIN, `insert into competitions (name, starts_on, ends_on) values ('순서정상', '2027-01-06', '2027-01-07')`)).err, '대회 정상 날짜 저장');
ok((await as(ADMIN, `insert into courses (title, starts_at, ends_at) values ('과정', '2027-01-06 09:00+09', '2027-01-05 09:00+09')`)).err?.includes('courses_date_order'), '교육 종료 < 시작 차단');
ok((await as(ADMIN, `insert into courses (title, starts_at, apply_deadline) values ('과정', '2027-01-06 09:00+09', '2027-01-07 09:00+09')`)).err?.includes('courses_date_order'), '교육 신청마감 > 시작 차단');
ok((await as(REF2, `insert into qualifications (user_id,name,acquired_on,expires_on) values ($1,'알파인스키 국내심판','2026-01-01','2025-01-01')`, [REF2])).err?.includes('qualifications_date_order'), '자격 만료일 < 취득일 차단');

// --- 0020: QR 출석 · 활동확인서 · 성과 리포트 · 처리 기록 · 오류 수집 ---
const O2 = '00000000-0000-0000-0000-0000000000a1', R3 = '00000000-0000-0000-0000-0000000000a2', R4 = '00000000-0000-0000-0000-0000000000a3', O3 = '00000000-0000-0000-0000-0000000000a4';
await db.exec(`insert into auth.users values
 ('${O2}', '{"name":"출석관계","role":"organizer","organization":"출석협회","phone":"01022220001"}', '{"provider":"email"}', 'o2@test.kr'),
 ('${R3}', '{"name":"출석심판","phone":"01022220002"}', '{"provider":"email"}', 'r3@test.kr'),
 ('${R4}', '{"name":"미선발자","phone":"01022220003"}', '{"provider":"email"}', 'r4@test.kr'),
 ('${O3}', '{"name":"남의관계","role":"organizer","organization":"다른협회","phone":"01022220004"}', '{"provider":"email"}', 'o3@test.kr')`);
const auditN = async (action) => (await db.query(`select count(*)::int n from audit_log where action='${action}'`)).rows[0].n;
const orgApprovedBefore = await auditN('org_approved');
await as(ADMIN, `update profiles set org_status='approved' where id in ('${O2}','${O3}')`);
ok(await auditN('org_approved') === orgApprovedBefore + 2, '처리 기록: 기관 승인');
const kst = (await db.query(`select (now() at time zone 'Asia/Seoul')::date::text d`)).rows[0].d;
const c20 = (await as(O2, `insert into competitions (organizer_id,name,starts_on) values ($1,'출석대회',$2) returning id`, [O2, kst])).rows[0].id;
const r20 = (await as(O2, `insert into recruitments (competition_id,position,headcount) values (${c20},'기문심판',2) returning id`)).rows[0].id;
await as(R3, `insert into applications (recruitment_id,user_id) values (${r20},$1)`, [R3]);
await as(R4, `insert into applications (recruitment_id,user_id) values (${r20},$1)`, [R4]);
const code3 = (await as(R3, `select checkin_code from applications where user_id=$1 and recruitment_id=${r20}`, [R3])).rows[0].checkin_code;
const code4 = (await as(R4, `select checkin_code from applications where user_id=$1 and recruitment_id=${r20}`, [R4])).rows[0].checkin_code;
ok(/^[0-9A-F]{8}$/.test(code3) && code3 !== code4, '지원마다 서로 다른 8자리 출석 코드');
ok((await as(O2, `select check_in($1)`, [code3])).err?.includes('선발된 심판이 아닙니다'), '선발 전 출석 차단');
const selBefore = await auditN('selection');
await as(O2, `update applications set status='selected' where user_id=$1 and recruitment_id=${r20}`, [R3]);
ok(await auditN('selection') === selBefore + 1, '처리 기록: 선발 처리');
ok((await as(R3, `update applications set checked_in_at=now() where user_id=$1 and recruitment_id=${r20}`, [R3])).err, '심판 본인이 출석 기록 조작 불가');
ok((await as(R3, `select check_in($1)`, [code3])).err?.includes('내가 등록한 대회'), '심판 본인이 자기 QR 로 출석 처리 불가');
ok((await as(O3, `select check_in($1)`, [code3])).err?.includes('내가 등록한 대회'), '다른 대회관계자는 출석 처리 불가');
ok((await as(O2, `select check_in('ZZZZZZZZ')`)).err?.includes('등록되지 않은'), '없는 코드 안내');
const ci = (await as(O2, `select check_in($1) j`, ['wr:' + code3.toLowerCase().slice(0, 4) + '-' + code3.toLowerCase().slice(4)])).rows?.[0]?.j;
ok(ci?.name === '출석심판' && ci?.already === false && ci?.position === '기문심판', '출석 처리 (소문자·하이픈 입력 허용)');
const row3 = (await db.query(`select checked_in_at is not null ok, checked_in_by, attendance from applications where user_id='${R3}' and recruitment_id=${r20}`)).rows[0];
ok(row3.ok && row3.checked_in_by === O2 && row3.attendance === 'attending', '출석 시각·처리자 기록, 참석으로 표시');
ok((await as(O2, `select check_in($1) j`, [code3])).rows?.[0]?.j?.already === true, '두 번째 스캔은 "이미 출석"');
ok(await auditN('checkin') === 1, '처리 기록: 출석 1건 (중복 스캔은 기록 안 함)');
ok((await as(ADMIN, `select check_in($1) j`, [code3])).rows?.[0]?.j?.already === true, '관리자도 출석 처리 가능');
await db.exec(`update competitions set starts_on = starts_on + 5 where id=${c20}`);
await db.exec(`update applications set checked_in_at=null where user_id='${R3}' and recruitment_id=${r20}`);
ok((await as(O2, `select check_in($1)`, [code3])).err?.includes('대회 전날부터'), '대회 기간 밖 출석 차단');
await db.exec(`update competitions set starts_on = '${kst}' where id=${c20}`);
await as(O2, `select check_in($1)`, [code3]);

// 활동확인서
await as(O2, `update applications set completed_at=now() where user_id=$1 and recruitment_id=${r20}`, [R3]);
ok(await auditN('activity_completed') >= 1, '처리 기록: 활동완료');
const cert = (await as(R3, `select issue_certificate() j`)).rows?.[0]?.j;
ok(/^WR\d{4}-[0-9A-F]{8}$/.test(cert?.code ?? ''), '활동확인서 발급번호 형식');
const ver = (await as(null, `select verify_certificate($1) j`, [cert.code.toLowerCase()])).rows?.[0]?.j;
ok(ver?.valid === true && ver.name === '출석심판' && ver.count === 1 && ver.items[0].competition === '출석대회', '진위 확인: 로그인 없이 발급 내용 조회');
ok(!JSON.stringify(ver).includes('0102222'), '진위 확인 결과에 연락처 없음');
ok((await as(null, `select verify_certificate('WR0000-00000000') j`)).rows?.[0]?.j?.valid === false, '진위 확인: 없는 번호');
ok((await as(R4, `select * from certificates`)).rows.length === 0, '남의 확인서 목록 조회 불가');
ok((await as(null, `select issue_certificate()`)).err, '비로그인 발급 불가');

// 성과 리포트
const rep = (await as(ADMIN, `select admin_report($1::date, $2::date) j`, [kst, kst])).rows?.[0]?.j;
ok(rep?.competitions >= 1 && rep.checked_in === 1 && rep.completed >= 1 && rep.certificates === 1 && rep.new_members >= 4, '성과 리포트 집계');
ok(rep.by_competition.some((x) => x.name === '출석대회' && x.selected === 1 && x.checked_in === 1 && x.completed === 1), '성과 리포트: 대회별 표');
ok((await as(R3, `select admin_report($1::date, $2::date)`, [kst, kst])).err?.includes('forbidden'), '성과 리포트는 관리자만');

// 처리 기록
const q20 = (await as(R4, `insert into qualifications (user_id,name,grade) values ($1,'알파인스키 국내심판','3급 신규') returning id`, [R4])).rows[0].id;
await as(ADMIN, `update qualifications set status='approved' where id=${q20}`);
const al = (await as(ADMIN, `select actor_name, target from audit_log where action='qual_approved' order by id desc limit 1`)).rows[0];
ok(al.actor_name === '관리자' && al.target.includes('미선발자') && al.target.includes('3급 신규'), '처리 기록: 자격 승인 (처리자·대상)');
ok((await as(R3, `select * from audit_log`)).rows.length === 0, '처리 기록은 관리자만 조회');
ok((await as(ADMIN, `delete from audit_log`)).rows?.length === 0 && (await db.query(`select count(*)::int n from audit_log`)).rows[0].n > 0, '처리 기록은 관리자도 삭제 불가');
ok((await as(ADMIN, `insert into audit_log (action) values ('fake')`)).err, '처리 기록 직접 쓰기 불가');
await as(ADMIN, `update profiles set role='organizer', org_status='approved' where id=$1`, [R4]);
ok(await auditN('role_changed') >= 1, '처리 기록: 회원 유형 변경');
await as(ADMIN, `update profiles set role='referee', org_status=null where id=$1`, [R4]);
const qd = await auditN('qual_deleted');
ok(!(await as(ADMIN, `select admin_delete_user($1)`, [R4])).err, '관리자 탈퇴 처리');
const md = (await db.query(`select target, detail from audit_log where action='member_deleted' order by id desc limit 1`)).rows[0];
ok(md.target === '(탈퇴 회원)' && md.detail === 'r4***@test.kr', '처리 기록: 탈퇴 처리 (이름은 지우고 가린 이메일만)');
ok((await db.query(`select count(*)::int n from audit_log where target like '%미선발자%'`)).rows[0].n === 0, '탈퇴 처리된 회원의 이름은 이전 처리 기록에서도 지워짐');
ok(await auditN('qual_deleted') === qd, '탈퇴로 함께 지워진 자격은 "자격 삭제"로 기록하지 않음');
ok(!(await as(R3, `select delete_my_account()`)).err, '본인 탈퇴');
ok((await db.query(`select count(*)::int n from certificates`)).rows[0].n === 0, '탈퇴 시 활동확인서 기록 삭제');
ok((await as(null, `select verify_certificate($1) j`, [cert.code])).rows?.[0]?.j?.valid === false, '탈퇴 후 진위 확인 불가');
const ml = (await db.query(`select actor_name, target from audit_log where action='member_left' order by id desc limit 1`)).rows[0];
ok(ml.target === '본인 탈퇴' && !JSON.stringify(ml).includes('출석심판'), '본인 탈퇴 기록에 개인정보 없음');
ok((await db.query(`select count(*)::int n from audit_log where target like '%출석심판%'`)).rows[0].n === 0, '본인 탈퇴 시 선발·출석 기록의 이름도 지워짐');
ok((await db.query(`select count(*)::int n from audit_log where target like '(탈퇴 회원) · 출석대회%'`)).rows[0].n >= 2, '처리 사실(선발·출석)은 남음');
ok(!(await as(O2, `delete from competitions where id=${c20}`)).err && await auditN('competition_deleted') >= 1, '처리 기록: 대회 삭제');

// 오류 수집
ok(!(await as(null, `select log_error('TypeError: x', 'stack...', '120', 'android')`)).err, '오류 기록: 비로그인도 전송 가능');
ok(!(await as(O2, `select log_error($1, $2, '120', 'web')`, ['E'.repeat(900), 'S'.repeat(9000)])).err, '오류 기록: 로그인 사용자');
const el = (await as(ADMIN, `select user_id, length(message) m, length(stack) s from error_logs order by id desc limit 1`)).rows[0];
ok(el.user_id === O2 && el.m === 500 && el.s === 4000, '오류 기록: 길이 제한·사용자 식별자만 저장');
ok((await as(O2, `select * from error_logs`)).rows.length === 0, '오류 기록은 관리자만 조회');
ok((await as(O2, `insert into error_logs (message) values ('x')`)).err, '오류 기록 직접 쓰기 불가');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
