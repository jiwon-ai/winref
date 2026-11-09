-- 회원 탈퇴 시 본인이 올린 자격증 사본도 지울 수 있게 (프로필 사진 삭제 정책은 0004 에 있음)
drop policy if exists p_files_qual_delete on storage.objects;
create policy p_files_qual_delete on storage.objects for delete using (
  bucket_id = 'files' and name like 'quals/' || auth.uid()::text || '/%');
