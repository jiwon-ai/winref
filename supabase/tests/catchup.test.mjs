// 운영 DB 따라잡기 SQL 검증: 일부 업데이트만 실행된 DB / 전부 실행된 DB 모두에서 오류 없이 적용되는지
import { PGlite } from '@electric-sql/pglite';
import { readFileSync, readdirSync } from 'fs';

const dir = new URL('../migrations/', import.meta.url);
const files = readdirSync(dir).filter((f) => f.endsWith('.sql')).sort();
const sql = (f) => readFileSync(new URL(f, dir), 'utf8');
const catchup = files.filter((f) => !f.startsWith('0001')).map(sql).join('\n');
const stub = `create schema auth; create schema storage;
create table auth.users (id uuid primary key, raw_user_meta_data jsonb, raw_app_meta_data jsonb, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
create table storage.buckets (id text primary key, name text, public boolean);
create table storage.objects (id serial primary key, bucket_id text, name text);
alter table storage.objects enable row level security;
create role authenticated; create role anon;`;

let fail = 0;
for (const [name, already] of [
  ['init+0007 만 실행된 DB', ['0001', '0007']],
  ['init+0003+0007+0008 실행된 DB', ['0001', '0003', '0007', '0008']],
  ['전부 실행된 DB (재실행)', files.map((f) => f.slice(0, 4))],
]) {
  const db = new PGlite();
  await db.exec(stub);
  for (const f of files) if (already.includes(f.slice(0, 4))) await db.exec(sql(f));
  try {
    await db.exec(catchup);
    await db.exec(catchup); // 두 번 실행해도 안전
    const r = await db.query(`select
      to_regprocedure('public.referee_summary(uuid)') is not null as summary,
      to_regprocedure('public.course_seats()') is not null as seats,
      to_regprocedure('public.selection_conflicts(bigint)') is not null as conflicts,
      exists (select 1 from information_schema.columns where table_name='qualifications' and column_name='file_path') as file_path,
      exists (select 1 from information_schema.columns where table_name='qualifications' and column_name='cert_no') as cert_no,
      exists (select 1 from information_schema.columns where table_name='profiles' and column_name='onboarded') as onboarded,
      (select count(*) from pg_policies where tablename='objects') as storage_policies`);
    const v = r.rows[0];
    const ok = v.summary && v.seats && v.conflicts && v.file_path && v.cert_no && v.onboarded;
    console.log(ok ? 'PASS' : 'FAIL', name, JSON.stringify(v));
    if (!ok) fail++;
  } catch (e) { fail++; console.log('FAIL', name, e.message); }
}
// 자동 만료일
{
  const db = new PGlite(); await db.exec(stub); for (const f of files) await db.exec(sql(f));
  await db.exec(`insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000b1','q@t.kr','{"name":"q","role":"referee"}')`);
  const r = await db.query(`insert into qualifications (user_id, name, acquired_on) values ('00000000-0000-0000-0000-0000000000b1','3급','2026-11-01') returning expires_on::text`);
  const ok = r.rows[0].expires_on === '2028-11-01';
  console.log(ok ? 'PASS' : 'FAIL', '만료일 자동 = 취득일 + 2년', r.rows[0].expires_on); if (!ok) fail++;
}
process.exit(fail ? 1 : 0);
