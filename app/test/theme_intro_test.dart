// 다크 모드 테마와 첫 실행 안내 3장
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:winref/screens/intro.dart';
import 'package:winref/theme.dart';

void main() {
  tearDown(() => Brand.dark = false);

  test('밝은·어두운 테마가 만들어지고 색이 서로 다르다', () {
    Brand.dark = false;
    final light = buildTheme();
    final lightInk = Brand.ink;
    Brand.dark = true;
    final dark = buildTheme();
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, isNot(light.scaffoldBackgroundColor));
    expect(Brand.ink, isNot(lightInk));
    // 어두운 바탕 위 본문 글자는 밝아야 한다
    expect(Brand.ink.computeLuminance(), greaterThan(Brand.card.computeLuminance() + 0.5));
  });

  for (final dark in [false, true]) {
    testWidgets('첫 실행 안내 3장: 다음 → 다음 → 시작하기 (${dark ? '다크' : '라이트'})', (tester) async {
      Brand.dark = dark;
      var done = 0;
      await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: IntroScreen(role: 'organizer', onDone: () => done++)));
      expect(find.text('대회와 모집공고 등록'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('지원자 확인과 선발'), findsOneWidget);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('현장 출석과 활동 기록'), findsOneWidget);
      expect(done, 0);
      await tester.tap(find.text('시작하기'));
      expect(done, 1);
      await tester.tap(find.text('건너뛰기'));
      expect(done, 2);
    });
  }

  test('회원 유형별 안내는 3장씩, 관리자는 없음', () {
    expect(introSlides['referee']!.length, 3);
    expect(introSlides['organizer']!.length, 3);
    expect(introSlides['admin'], isNull);
    expect(introSeen('admin'), isTrue);
  });
}
