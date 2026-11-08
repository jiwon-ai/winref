-- ===== 심판 본인 참석 응답 =====
-- 지원자는 지원 취소·재지원, 그리고 선발된 뒤(활동완료 전) 참석/불참 응답만 할 수 있다.
create or replace function guard_application_update() returns trigger language plpgsql as $$
begin
  if auth.uid() is null or is_admin() or owns_recruitment(old.recruitment_id) then return new; end if;  -- uid null = 서버/SQL 콘솔
  if new.user_id <> old.user_id or new.recruitment_id <> old.recruitment_id
     or new.completed_at is distinct from old.completed_at
     or (new.status <> old.status
         and not (new.status = 'cancelled' and old.status = 'applied')
         and not (new.status = 'applied' and old.status = 'cancelled')) then
    raise exception '지원자는 지원 취소·재지원만 가능';
  end if;
  if new.attendance <> old.attendance
     and not (old.status = 'selected' and new.status = 'selected' and old.completed_at is null
              and new.attendance in ('attending', 'absent')) then
    raise exception '참석 응답은 선발된 뒤 활동완료 전까지만 가능';
  end if;
  if new.status = 'applied' and old.status = 'cancelled' and not exists (
       select 1 from recruitments r where r.id = new.recruitment_id and r.is_open
       and (r.deadline is null or r.deadline > now())) then
    raise exception '모집이 마감되었습니다';
  end if;
  return new;
end $$;

-- 심판이 직접 참석/불참을 응답하면 대회관계자에게 알림
create function notify_attendance() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.attendance is distinct from old.attendance and auth.uid() = new.user_id then
    insert into notifications (user_id, kind, title, body)
    select c.organizer_id, 'attendance',
           case new.attendance when 'absent' then '심판 불참 응답' else '심판 참석 확정' end,
           p.name || ' · ' || c.name || ' ' || r.position
    from recruitments r join competitions c on c.id = r.competition_id, profiles p
    where r.id = new.recruitment_id and p.id = new.user_id and c.organizer_id is not null;
  end if;
  return new;
end $$;
create trigger applications_attendance_notify after update on applications
  for each row execute function notify_attendance();

-- ===== 일정 겹침 =====
-- 이 대회 지원자 중, 기간이 겹치는 다른 대회에 이미 선발된 사람 (대회관계자·관리자용)
create function selection_conflicts(p_competition bigint)
returns table (user_id uuid, competition_name text, starts_on date)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (owns_competition(p_competition) or is_admin()) then raise exception 'forbidden'; end if;
  return query
  with me as (select c.starts_on s, coalesce(c.ends_on, c.starts_on) e from competitions c where c.id = p_competition)
  select distinct a.user_id, c.name, c.starts_on
  from applications a
  join recruitments r on r.id = a.recruitment_id
  join competitions c on c.id = r.competition_id, me
  where a.status = 'selected' and c.id <> p_competition
    and c.starts_on <= me.e and coalesce(c.ends_on, c.starts_on) >= me.s
    and a.user_id in (select a3.user_id from applications a3 join recruitments r3 on r3.id = a3.recruitment_id
                      where r3.competition_id = p_competition and a3.status <> 'cancelled');
end $$;
revoke all on function selection_conflicts(bigint) from public, anon;
grant execute on function selection_conflicts(bigint) to authenticated;
