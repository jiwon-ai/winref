import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
                    TextButton(onPressed: () => db.auth.signOut(), child: const Text('로그아웃')),
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
