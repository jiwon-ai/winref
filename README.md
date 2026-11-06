# WINREF ACADEMY 스포츠 인재은행 (MVP)

Flutter 안드로이드 앱 + 관리자 웹(같은 코드, Flutter Web) + Supabase 공통 서버.

| 폴더 | 내용 |
|---|---|
| `app/` | Flutter 앱. 로그인한 회원 유형에 따라 심판·교육신청자 / 대회관계자 / 관리자 화면 |
| `supabase/migrations/` | DB 스키마, 권한(RLS), 자동알림·통계 함수 |
| `supabase/functions/send-push/` | 알림 큐 → FCM 푸시 발송 |
| `supabase/setup/cron.sql` | 매일 자동알림 생성 + 5분마다 푸시 발송 스케줄 |
| `.github/workflows/android.yml` | APK·AAB·관리자 웹 자동 빌드 (main 에 push 할 때마다) |

## 1. Supabase (서버)

1. supabase.com 에서 프로젝트 생성 (WINREF 가 관리하는 계정, 리전 Seoul).
2. SQL Editor 에서 `supabase/migrations/0001_init.sql`, `0002_broadcast_storage.sql` 순서대로 실행.
3. Authentication > Providers > Email 사용. (가입 확인 메일을 끄면 바로 로그인)
4. Database > Extensions 에서 `pg_cron`, `pg_net` 활성화 후 `supabase/setup/cron.sql` 실행.
5. 관리자 계정: 앱에서 가입 → SQL Editor 에서 `cron.sql` 맨 아래 주석의 update 문 실행.

## 2. Firebase (푸시)

1. console.firebase.google.com 에서 프로젝트 생성 → Android 앱 추가 (패키지명 `kr.co.winref.app`).
2. 프로젝트 설정 > 일반 에서 API 키, 앱 ID, 발신자 ID(Sender ID), 프로젝트 ID 를 GitHub Secrets 에 등록 (아래 표).
3. 프로젝트 설정 > 서비스 계정 > 새 비공개 키 생성 → JSON 전체를 Supabase Edge Function Secret `FCM_SERVICE_ACCOUNT` 로 등록.
4. Supabase 에 `send-push` 함수 배포, Secret `CRON_SECRET`(임의 문자열, cron.sql 과 동일) 등록.

## 3. GitHub Secrets (Settings > Secrets and variables > Actions)

| 이름 | 값 |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase API 키 (anon / publishable) |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | Firebase Android 앱 값 |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | 업로드 키 (없으면 debug 서명 → Play 업로드 불가) |

## 4. Google Play 출시

1. Actions 실행 결과의 `winref-android` 에서 `app-release.aab` 다운로드.
2. Play Console (WINREF 조직 계정) > 앱 만들기 > 내부 테스트 트랙에 AAB 업로드.
3. 스토어 등록정보, 개인정보처리방침 URL, 데이터 보안 설문, 콘텐츠 등급 작성.
4. 프로덕션 출시 검토 제출.

## 5. 관리자 웹

Actions 결과의 `winref-admin-web` 을 정적 호스팅(Vercel, Netlify, Firebase Hosting 등)에 올리면 됩니다.

## 범위 (과업지시서 기준)

- 포함: 회원가입·로그인·비밀번호 재설정, 회원 유형 선택, 교육 조회·신청, 자격정보, 대회 조회·지원·선발결과, 브리핑 자료, 활동이력, 대회 등록·모집공고·지원자 선발·참석·활동완료, 관리자(회원·기관승인·자격승인·교육·대회·공지·알림·통계), 앱 푸시, 자동알림(교육 마감 D-1, 대회 D-1, 자격 만료 30일 전)
- 제외(과업지시서 6항): 동영상 업로드, 실시간 채팅, 앱 내 결제
- 별도: 카카오 알림톡(2차 개발), SMS/LMS 는 발송 업체 계약·발신번호 등록 후 연동
