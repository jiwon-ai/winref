-- 자동 알림 생성 함수는 예약 작업(pg_cron)만 실행. 앱·외부에서 직접 호출 못 하게.
revoke all on function enqueue_auto_notifications() from public, anon, authenticated;
