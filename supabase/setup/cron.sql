-- 배포 후 1회 실행 (Supabase SQL Editor). <PROJECT_REF>, <CRON_SECRET> 를 실제 값으로 바꾼다.
-- 사전: Dashboard > Database > Extensions 에서 pg_cron, pg_net 활성화

-- 매일 09:00 KST(= 00:00 UTC) 자동알림 생성: 교육 마감 D-1, 대회 D-1, 자격 만료 30일 전
select cron.schedule('winref-auto-notifications', '0 0 * * *', $$ select public.enqueue_auto_notifications(); $$);

-- 5분마다 미발송 알림을 FCM 으로 발송
select cron.schedule('winref-send-push', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-push',
    headers := jsonb_build_object('x-cron-secret', '<CRON_SECRET>', 'Content-Type', 'application/json'),
    body := '{}'::jsonb
  );
$$);

-- 첫 관리자 지정: 관리자 계정으로 앱에서 (심판 유형으로) 가입한 뒤 실행
-- update public.profiles set role = 'admin' where id = (select id from auth.users where email = '관리자이메일');
