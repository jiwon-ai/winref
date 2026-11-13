-- 심판 활동 평가 · 선발 도우미 · 심판증 QR · 카카오 알림톡 준비
-- 여러 번 실행해도 안전.

-- ============================================================
-- 1. 심판 활동 평가 (비공개: 관리자와 그 대회의 대회관계자만 작성·열람, 심판 본인은 볼 수 없음)
-- ============================================================
create table if not exists evaluations (
  application_id bigint primary key references applications(id) on delete cascade,  -- 활동 1건당 평가 1개
  rating         int not null check (rating between 1 and 5),
  comment        text,
  evaluator_id   uuid,
  updated_at     timestamptz not null default now()
);
alter table evaluations enable row level security;

-- 그 지원 건의 대회를 내가 등록했는가 (활동완료된 건만 평가 가능)
create or replace function can_evaluate(p_application bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from applications a
    where a.id = p_application and a.completed_at is not null
      and (is_admin() or owns_recruitment(a.recruitment_id)));
$$;
drop policy if exists p_eval_all on evaluations;
create policy p_eval_all on evaluations for all
  using (can_evaluate(application_id)) with check (can_evaluate(application_id));

-- 심판의 평균 평가 (모든 대회 합산): 관리자, 또는 그 심판이 내 공고에 지원한 대회관계자만
create or replace function referee_rating(p_user uuid) returns json
language plpgsql stable security definer set search_path = public as $$
begin
  if not (is_admin() or views_referee(p_user)) then return json_build_object('count', 0, 'avg', null); end if;
  return (select json_build_object('count', count(*), 'avg', round(avg(e.rating)::numeric, 1))
          from evaluations e join applications a on a.id = e.application_id where a.user_id = p_user);
end $$;
revoke all on function referee_rating(uuid) from public, anon;
grant execute on function referee_rating(uuid) to authenticated;

-- ============================================================
-- 2. 선발 도우미: 이 대회 지원자들의 활동 경험·불참 이력·평가·자격 등급 (대회관계자·관리자)
-- ============================================================
create or replace function applicant_stats(p_competition bigint)
returns table (user_id uuid, done int, by_position jsonb, absent int, rating numeric, rating_count int, top_grade text, approved_quals int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (owns_competition(p_competition) or is_admin()) then raise exception 'forbidden'; end if;
  return query
  with u as (
    select distinct a.user_id as uid from applications a join recruitments r on r.id = a.recruitment_id
    where r.competition_id = p_competition and a.status <> 'cancelled')
  select u.uid,
    (select count(*)::int from applications a where a.user_id = u.uid and a.completed_at is not null),
    coalesce((select jsonb_object_agg(t.position, t.n) from (
        select r.position, count(*) n from applications a join recruitments r on r.id = a.recruitment_id
        where a.user_id = u.uid and a.completed_at is not null group by r.position) t), '{}'::jsonb),
    (select count(*)::int from applications a where a.user_id = u.uid and a.status = 'selected' and a.attendance = 'absent'),
    (select round(avg(e.rating)::numeric, 1) from evaluations e join applications a on a.id = e.application_id where a.user_id = u.uid),
    (select count(*)::int from evaluations e join applications a on a.id = e.application_id where a.user_id = u.uid),
    (select min(substring(q.grade from '^([1-3])급')) || '급' from qualifications q where q.user_id = u.uid and q.status = 'approved'),
    (select count(*)::int from qualifications q where q.user_id = u.uid and q.status = 'approved')
  from u;
end $$;
revoke all on function applicant_stats(bigint) from public, anon;
grant execute on function applicant_stats(bigint) to authenticated;

-- ============================================================
-- 3. 디지털 심판증 QR: 스캔하면 진위 확인 페이지에서 이름·승인 자격·활동을 볼 수 있다
--    하루 안에 발급한 확인서가 있으면 그 번호를 다시 쓰고, 없으면 새로 발급
-- ============================================================
create or replace function card_certificate() returns json
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); c record;
begin
  if me is null then raise exception 'not signed in'; end if;
  select code, issued_at into c from certificates
  where user_id = me and issued_at > now() - interval '1 day' order by issued_at desc limit 1;
  if found then return json_build_object('code', c.code, 'issued_at', c.issued_at); end if;
  return issue_certificate();
end $$;
revoke all on function card_certificate() from public, anon;
grant execute on function card_certificate() to authenticated;

-- ============================================================
-- 4. 카카오 알림톡 준비: 발송 여부 기록 (실제 발송은 send-push 함수가 발송 업체 키가 설정된 경우에만)
-- ============================================================
alter table notifications add column if not exists alimtalk_at timestamptz;
