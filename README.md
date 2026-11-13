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

1. supabase.com 에서 프로젝트 생성 (현재 운영: 리전 eu-west-1 아일랜드 — 개인정보처리방침 국외이전 항목과 일치해야 함).
2. SQL Editor 에서 `supabase/migrations/` 의 파일을 번호 순서대로(0001 → 마지막 번호(현재 0021)) 모두 실행. 모든 파일은 여러 번 실행해도 안전(idempotent).
3. Authentication > Providers > Email 사용. (가입 확인 메일을 끄면 바로 로그인)
   - Email OTP Length = 6 (임시 비밀번호 6자리), 메일 템플릿 'Reset password' 는 `{{ .Token }}` 사용
   - SMTP Settings: smtp.gmail.com:465, 회사 Gmail + 앱 비밀번호 (발신 주소가 회사 메일이 되도록)
   - URL Configuration: Site URL = 관리자 웹 주소, Redirect URLs = 관리자 웹 주소, `주소/**`, `kr.co.winref.app://login-callback`
   - 소셜 로그인: Google, Kakao(REST API 키 + 카카오 로그인 Client Secret, 동의항목 닉네임·이메일 필수). 카카오 버튼은 빌드 옵션 `--dart-define=KAKAO=true` 일 때만 표시
4. Database > Extensions 에서 `pg_cron`, `pg_net` 활성화 후 `supabase/setup/cron.sql` 실행.
5. 관리자 계정: 앱에서 가입 → SQL Editor 에서 `cron.sql` 맨 아래 주석의 update 문 실행.

## 2. Firebase (푸시)

1. console.firebase.google.com 에서 프로젝트 생성 → Android 앱 추가 (패키지명 `kr.co.winref.app`).
2. 프로젝트 설정 > 일반 에서 API 키, 앱 ID, 발신자 ID(Sender ID), 프로젝트 ID 를 GitHub Secrets 에 등록 (아래 표).
3. 프로젝트 설정 > 서비스 계정 > 새 비공개 키 생성 → JSON 전체를 Supabase Edge Function Secret `FCM_SERVICE_ACCOUNT` 로 등록.
4. Supabase 에 `send-push` 함수 배포, Secret `CRON_SECRET`(임의 문자열, cron.sql 과 동일) 등록.

### 카카오 알림톡 (선택, 2차)
코드는 준비돼 있고(`send-push` 함수), 아래 준비가 끝난 뒤 Secrets 만 넣으면 켜진다. 실제 발송 테스트는 템플릿 승인 후 필요.
1. 카카오 비즈니스 채널 개설 (회사 명의) → 솔라피(solapi.com) 가입·채널 연동(pfId 발급), 발신번호 등록.
2. 알림톡 템플릿 등록·카카오 심사: 본문에 변수 `#{제목}`, `#{내용}` 두 개를 쓰는 정보성 템플릿.
3. Supabase Edge Function Secrets 에 `SOLAPI_API_KEY`, `SOLAPI_API_SECRET`, `SOLAPI_PFID`, `SOLAPI_TEMPLATE_ID`, `SOLAPI_SENDER` 등록 후 `send-push` 재배포.
4. 대상 알림(기본): 선발 결과, 대회 D-1, 자격 만료(보수교육), 교육 마감. `ALIMTALK_KINDS` 로 변경. 건당 요금 발생.
5. 켜기 전에 개인정보처리방침의 처리 위탁에 발송 업체(솔라피)와 카카오를 추가할 것.

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

## 5. 웹 (고객 시연·관리자)

main 에 push 하면 GitHub Pages 로 자동 배포된다: https://jiwon.fr/winref/
Supabase > Authentication > URL Configuration > Site URL 을 이 주소로 설정해야 인증 메일 링크가 올바로 열린다.

## 범위 (과업지시서 기준)

- 포함: 홈 대시보드, 대회 검색·필터·캘린더, 심판 프로필·경력(사진·포지션별 통계), 일괄 선발·엑셀 내보내기, 선발/자격/브리핑 자동 알림, 회원 탈퇴, 회원가입·로그인·비밀번호 재설정, 회원 유형 선택, 교육 조회·신청, 자격정보, 대회 조회·지원·선발결과, 브리핑 자료, 활동이력, 대회 등록·모집공고·지원자 선발·참석·활동완료, 관리자(회원·기관승인·자격승인·교육·대회·공지·알림·통계), 앱 푸시, 자동알림(교육 마감 D-1, 대회 D-1, 자격 만료 30일 전)
- 제외(과업지시서 6항): 동영상 업로드, 실시간 채팅, 앱 내 결제
- 별도: 카카오 알림톡(2차 개발), SMS/LMS 는 발송 업체 계약·발신번호 등록 후 연동
