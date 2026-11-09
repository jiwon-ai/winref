-- 관리자 대시보드: 처리할 일·월별 가입·정원 대비 신청
create or replace function admin_stats() returns json language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  return json_build_object(
    'members_by_role', (select coalesce(json_object_agg(role, n), '{}') from (select role, count(*) n from profiles group by role) t),
    'new_members_30d', (select count(*) from profiles where created_at > now() - interval '30 days'),
    'course_applicants', (select coalesce(json_agg(t), '[]') from (
        select c.id, c.title, c.capacity, c.starts_at, count(ca.id) filter (where ca.status <> 'cancelled') applicants
        from courses c left join course_applications ca on ca.course_id = c.id group by c.id order by c.starts_at desc limit 8) t),
    'competitions', (select count(*) from competitions),
    'open_recruitments', (select count(*) from recruitments where is_open),
    'competition_applications', (select coalesce(json_agg(t), '[]') from (
        select c.id, c.name, c.starts_on,
               (select coalesce(sum(r2.headcount), 0) from recruitments r2 where r2.competition_id = c.id) headcount,
               count(a.id) filter (where a.status <> 'cancelled') applied,
               count(a.id) filter (where a.status = 'selected') selected
        from competitions c left join recruitments r on r.competition_id = c.id
        left join applications a on a.recruitment_id = r.id group by c.id order by c.starts_on desc limit 8) t),
    'completed_activities', (select count(*) from applications where completed_at is not null),
    'expiring_90d', (select count(distinct user_id) from qualifications
                     where status = 'approved' and expires_on between current_date and current_date + 90),
    -- 처리할 일
    'pending_quals', (select count(*) from qualifications where status = 'pending'),
    'pending_orgs', (select count(*) from profiles where role = 'organizer' and org_status = 'pending'),
    'upcoming_14d', (select count(*) from competitions where starts_on between current_date and current_date + 14),
    'courses_closing_7d', (select count(*) from courses where apply_deadline between now() and now() + interval '7 days'),
    -- 최근 6개월 신규 가입 (월별)
    'monthly_signups', (select json_agg(json_build_object('month', to_char(m, 'YYYY-MM'), 'n',
        (select count(*) from profiles where date_trunc('month', created_at) = m)) order by m)
        from generate_series(date_trunc('month', now()) - interval '5 months', date_trunc('month', now()), interval '1 month') m)
  );
end $$;
