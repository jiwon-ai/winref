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
    expect(tester.getBottomLeft(find.text('맨 아래 버튼')).dy, lessThanOrEqualTo(screenH - navBar));

    await tester.tap(find.text('맨 아래 버튼'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -5000));
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.text('시트 끝')).dy, lessThanOrEqualTo(screenH - navBar));
    expect(tester.getTopLeft(find.text('항목 0', skipOffstage: false)).dy, greaterThanOrEqualTo(-10000)); // 존재 확인
    // 시트 맨 위가 상태바 아래에서 시작
    expect(tester.getTopLeft(find.byType(DraggableScrollableSheet)).dy, greaterThanOrEqualTo(statusBar));
  });
}
