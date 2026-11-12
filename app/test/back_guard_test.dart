// 휴대폰 '뒤로' 버튼: 다른 탭 → 홈 탭, 홈 → 안내 후 두 번째에만 종료, 상세 화면 → 이전 화면
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winref/common.dart';

class _Home extends StatefulWidget {
  const _Home();
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int tab = 1;
  @override
  Widget build(BuildContext context) => BackGuard(
        atHome: tab == 0,
        onHome: () => setState(() => tab = 0),
        child: Scaffold(
          body: Column(children: [
            Text('탭 $tab'),
            TextButton(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const Scaffold(body: Text('상세')))),
              child: const Text('열기'),
            ),
          ]),
        ),
      );
}

void main() {
  testWidgets('뒤로 버튼 동작', (tester) async {
    final exits = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      exits.add(call.method);
      return null;
    });
    await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: messengerKey, home: const _Home()));

    // 상세 화면에서 뒤로 → 이전 화면
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(find.text('상세'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('상세'), findsNothing);

    // 다른 탭에서 뒤로 → 홈 탭
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('탭 0'), findsOneWidget);
    expect(exits, isNot(contains('SystemNavigator.pop')));

    // 홈에서 첫 번째 뒤로 → 안내만, 종료 안 함
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.textContaining('한 번 더 누르면'), findsOneWidget);
    expect(exits, isNot(contains('SystemNavigator.pop')));

    // 2초 안에 한 번 더 → 종료
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exits, contains('SystemNavigator.pop'));
  });
}
