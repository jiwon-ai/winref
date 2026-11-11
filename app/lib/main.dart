import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'common.dart';
import 'push.dart';
import 'screens/admin.dart';
import 'screens/auth.dart';
import 'screens/organizer.dart';
import 'screens/referee.dart';
import 'theme.dart';

// 빌드 시 --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

const _e2e = bool.fromEnvironment('E2E'); // 자동 테스트 빌드: 접근성 트리를 켜서 브라우저가 화면 요소를 찾게 함

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('서버 설정(SUPABASE_URL/KEY)이 빌드에 없습니다.')))));
    return;
  }
  if (_e2e) SemanticsBinding.instance.ensureSemantics();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  if (!kIsWeb) await Push.init();
  runApp(const WinrefApp());
}

class WinrefApp extends StatelessWidget {
  const WinrefApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WINREF',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: buildTheme(),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // 휴대폰 글자 크기 설정은 반영하되, 화면이 깨질 만큼 커지지 않게 상한(1.2배)을 둔다.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final scaled = mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.2));
        // PC 브라우저에서는 심판·대회관계자 화면을 휴대폰 폭으로 가운데 표시(관리자 화면만 전체 폭)
        return ValueListenableBuilder<bool>(
          valueListenable: fullWidth,
          builder: (context, full, _) {
            // 위젯 구조를 항상 같게 유지해 폭이 바뀌어도 화면 상태가 초기화되지 않게 한다
            final narrow = !full && mq.size.width > 600;
            const w = 440.0;
            return ColoredBox(
              color: const Color(0xFFE3EAF3),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: narrow ? w : mq.size.width,
                  height: mq.size.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: narrow
                          ? const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 6))]
                          : const [],
                    ),
                    child: ClipRect(
                      child: MediaQuery(
                        data: narrow ? scaled.copyWith(size: Size(w, mq.size.height)) : scaled,
                        // 갤럭시 하단 내비게이션·제스처 바에 맨 아래 버튼·목록이 가려지지 않게 모든 화면을 그 위까지만 사용
                        child: ColoredBox(
                          color: Colors.white,
                          child: SafeArea(top: false, left: false, right: false, child: child!),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
      home: const AuthGate(),
    );
  }
}

/// 로그인 상태와 회원 유형(role)에 따라 첫 화면을 고른다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _recovery = false; // 비밀번호 재설정 링크로 진입
  int _profileVersion = 0; // 가입 정보 입력 후 프로필 다시 읽기

  @override
  void initState() {
    super.initState();
    // 메일 링크가 만료됐거나 다른 기기·브라우저에서 열려 로그인에 실패한 경우 빈 화면 대신 안내
    final u = Uri.base;
    final failed = '${u.query}&${u.fragment}'.contains('error_code=') ||
        (u.queryParameters.containsKey('code') && db.auth.currentSession == null);
    if (failed) {
      Future.delayed(const Duration(seconds: 2), () {
        if (db.auth.currentSession != null) return;
        messengerKey.currentState?.showSnackBar(const SnackBar(
          duration: Duration(seconds: 10),
          content: Text('메일 링크가 만료되었거나 다른 기기에서 열렸습니다. 로그인 화면의 \'비밀번호 재설정\'에서 '
              '메일로 받은 인증코드를 입력해 주세요.'),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, snap) {
        if (snap.data?.event == AuthChangeEvent.passwordRecovery && !otpRecovery) _recovery = true;
        final user = db.auth.currentUser;
        if (user == null) return const LoginScreen();
        if (_recovery) return NewPasswordScreen(onDone: () => setState(() => _recovery = false));
        return FutureBuilder<Map<String, dynamic>>(
          key: ValueKey('${user.id}-$_profileVersion'),
          future: db.from('profiles').select().eq('id', user.id).single(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(
                body: SafeArea(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    ErrorView(error: snap.error, onRetry: () => setState(() => _profileVersion++)),
                    TextButton(onPressed: signOut, child: const Text('로그아웃')),
                  ]),
                ),
              );
            }
            if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final profile = snap.data!;
            if (profile['onboarded'] == false) {
              return OnboardingScreen(profile: profile, onDone: () => setState(() => _profileVersion++));
            }
            if (!kIsWeb) Push.registerToken();
            switch (profile['role']) {
              case 'admin':
                return AdminHome(profile: profile);
              case 'organizer':
                return OrganizerHome(profile: profile);
              default:
                return RefereeHome(profile: profile);
            }
          },
        );
      },
    );
  }
}
