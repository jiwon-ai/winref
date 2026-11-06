-- 관리자 알림 일괄 발송: 대상 회원 수 반환 (p_role null = 전체)
create function admin_broadcast(p_title text, p_body text, p_role user_role default null)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not is_admin() then raise exception 'forbidden'; end if;
  insert into notifications (user_id, kind, title, body)
  select id, 'notice', p_title, p_body from profiles where p_role is null or role = p_role;
  get diagnostics n = row_count;
  return n;
end $$;

-- 브리핑 첨부(briefings/<대회id>/...)는 선발 심판·해당 관계자·관리자만 열람
drop policy p_files_read on storage.objects;
create policy p_files_read on storage.objects for select using (
  bucket_id = 'files' and auth.uid() is not null and (
    name not like 'briefings/%'
    or is_admin()
    or (split_part(name, '/', 2) ~ '^[0-9]+$' and (
          is_selected_for(split_part(name, '/', 2)::bigint)
          or owns_competition(split_part(name, '/', 2)::bigint)))
  ));
