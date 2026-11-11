// 갤럭시처럼 하단 내비게이션 바(48dp)가 있는 화면에서 맨 아래 버튼·시트 내용이 바 위에 오는지 확인
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winref/main.dart';

void main() {
  testWidgets('하단 시스템 바에 화면·시트 내용이 가리지 않음', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2340); // 360x780dp
    tester.view.padding = const FakeViewPadding(top: 72, bottom: 144); // 상태바 24dp, 내비게이션 바 48dp
    tester.view.viewPadding = const FakeViewPadding(top: 72, bottom: 144);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      builder: appFrame,
      home: Scaffold(
        body: const Center(child: Text('본문')),
        bottomNavigationBar: Builder(
          builder: (c) => FilledButton(
            onPressed: () => showModalBottomSheet(
              useSafeArea: true,
              context: c,
              isScrollControlled: true,
              builder: (_) => DraggableScrollableSheet(
                expand: false,
                initialChildSize: 1,
                builder: (_, sc) => ListView(controller: sc, children: [
                  for (var i = 0; i < 40; i++) ListTile(title: Text('항목 $i')),
                  const Text('시트 끝'),
                ]),
              ),
            ),
            child: const Text('맨 아래 버튼'),
          ),
        ),
      ),
    ));

    const screenH = 780.0, navBar = 48.0, statusBar = 24.0;
    const room = 12.0; // 바 위 여유
    expect(tester.getBottomLeft(find.text('맨 아래 버튼')).dy, lessThanOrEqualTo(screenH - navBar - room));

    await tester.tap(find.text('맨 아래 버튼'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('시트 끝')).dy, lessThanOrEqualTo(screenH - navBar - room));
    // 시트 맨 위가 상태바 아래에서 시작
    expect(tester.getTopLeft(find.byType(DraggableScrollableSheet)).dy, greaterThanOrEqualTo(statusBar));
  });

  testWidgets('제스처 내비게이션: 제스처 영역 + 여유만큼 올리고, 키보드가 올라오면 여백 없음', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.padding = const FakeViewPadding(bottom: 48); // 제스처 바 16dp
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    tester.view.systemGestureInsets = const FakeViewPadding(bottom: 96); // 제스처 영역 32dp
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: appFrame,
      home: const Scaffold(bottomNavigationBar: Text('맨 아래')),
    ));
    expect(tester.getBottomLeft(find.text('맨 아래')).dy, lessThanOrEqualTo(780 - 32 - 12));

    tester.view.viewInsets = const FakeViewPadding(bottom: 900); // 키보드
    tester.view.padding = FakeViewPadding.zero;
    await tester.pump();
    expect(bottomGap(MediaQueryData.fromView(tester.view)), 0);
  });
}
