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
      home: const AuthGate(),
    );
  }
}

/// 로그인 상태와 회원 유형(role)에 따라 첫 화면을 고른다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: db.auth.onAuthStateChange,
      builder: (context, _) {
        final user = db.auth.currentUser;
        if (user == null) return const LoginScreen();
        return FutureBuilder<Map<String, dynamic>>(
          key: ValueKey(user.id),
          future: db.from('profiles').select().eq('id', user.id).single(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Scaffold(
                body: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('프로필을 불러오지 못했습니다.\n${snap.error}', textAlign: TextAlign.center),
                    TextButton(onPressed: signOut, child: const Text('로그아웃')),
                  ]),
                ),
              );
            }
            if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            final profile = snap.data!;
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
