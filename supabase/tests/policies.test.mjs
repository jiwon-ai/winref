import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'fs';

const db = new PGlite();
// Supabase 환경 최소 스텁
await db.exec(`
create schema auth; create schema storage;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb);
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
 ('${ADMIN}', '{"name":"관리자","role":"admin"}'),
 ('${REF}', '{"name":"심판1"}'),
 ('${REF2}', '{"name":"심판2"}'),
 ('${ORG}', '{"name":"관계자","role":"organizer","organization":"OO협회"}');`);
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

ok((await as(ADMIN, `select delete_my_account()`)).err, '관리자 탈퇴 차단');
ok(!(await as(REF, `select delete_my_account()`)).err, '심판 탈퇴');
ok((await db.query(`select count(*)::int n from applications where user_id='${REF}'`)).rows[0].n === 0, '탈퇴 시 지원·이력 삭제');
ok(!(await as(ORG, `select delete_my_account()`)).err, '관계자 탈퇴');
ok((await db.query(`select count(*)::int n from competitions where organizer_id is null`)).rows[0].n === 1, '관계자 탈퇴 후 대회 보존');
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
