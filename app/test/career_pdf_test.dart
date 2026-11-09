import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:winref/career_pdf.dart';

// 앱이 쓰는 것과 같은 Noto Sans KR (printing 패키지의 PdfGoogleFonts 주소)
const _regular = 'https://fonts.gstatic.com/s/notosanskr/v36/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzzuoyeLTq8H4hfeE.ttf';
const _bold = 'https://fonts.gstatic.com/s/notosanskr/v36/PbyxFmXiEBPT4ITbgNA5Cgms3VYcOA-vvnIzzg01eLTq8H4hfeE.ttf';

Future<pw.Font> _font(String url) async {
  final res = await (await HttpClient().getUrl(Uri.parse(url))).close();
  final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
  return pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(bytes)));
}

void main() {
  test('심판 활동 이력 PDF 생성 (한글·여러 페이지)', () async {
    final regular = await _font(_regular);
    final bold = await _font(_bold);
    final history = [
      for (var i = 0; i < 40; i++) // 40건 → 여러 페이지로 넘어가는지 확인
        {
          'competition_name': '2026 용평컵 알파인 스키대회 $i',
          'starts_on': '2026-11-0${(i % 9) + 1}',
          'ends_on': i.isEven ? '2026-11-0${(i % 9) + 1}' : null,
          'venue': '용평리조트 레인보우 슬로프',
          'position': i % 3 == 0 ? '기문심판' : '출발심판',
        },
    ];
    final bytes = await buildCareerPdf(
      profile: {'id': '1234abcd-0000-0000-0000-000000000000', 'name': '김심판', 'region': '강원', 'sport': '대회전 (GS)', 'birth_date': '1990-05-01'},
      history: history,
      quals: [{'name': '대한스키협회 알파인 심판', 'grade': '3급', 'cert_no': 'KSA-AL-2024-0123', 'acquired_on': '2024-03-01', 'expires_on': '2027-02-28'}],
      regular: regular,
      bold: bold,
      issuedAt: DateTime(2026, 11, 8),
    );
    expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, greaterThanOrEqualTo(2));
    Directory('build').createSync(recursive: true);
    File('build/career_sample.pdf').writeAsBytesSync(bytes); // CI 결과물로 확인용
  }, timeout: const Timeout(Duration(minutes: 2)));
}
