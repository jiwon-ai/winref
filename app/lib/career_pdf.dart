import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// 심판 활동 이력 PDF (앱 기록 출력본).
/// profile: profiles 행, history: activity_history 행, quals: 승인된 qualifications 행
Future<Uint8List> buildCareerPdf({
  required Map<String, dynamic> profile,
  required List<Map<String, dynamic>> history,
  required List<Map<String, dynamic>> quals,
  required pw.Font regular,
  required pw.Font bold,
  Uint8List? logoPng,
  DateTime? issuedAt,
}) async {
  const blue = PdfColor.fromInt(0xFF2560AC);
  const line = PdfColor.fromInt(0xFFC3D0E0);
  const muted = PdfColor.fromInt(0xFF5D6B7E);
  final issued = issuedAt ?? DateTime.now();
  String d(dynamic v) {
    final t = DateTime.tryParse(v?.toString() ?? '');
    return t == null ? '-' : DateFormat('yyyy.MM.dd').format(t);
  }

  final id = (profile['id'] ?? '').toString();
  final docNo = 'WR-${DateFormat('yyyyMMdd').format(issued)}-${id.length >= 8 ? id.substring(0, 8).toUpperCase() : id}';
  final byPos = <String, int>{};
  for (final h in history) {
    byPos[h['position']] = (byPos[h['position']] ?? 0) + 1;
  }

  pw.Widget infoRow(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(children: [
          pw.SizedBox(width: 80, child: pw.Text(k, style: const pw.TextStyle(color: muted))),
          pw.Expanded(child: pw.Text(v)),
        ]),
      );
  pw.Widget head(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 8),
        child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 12, color: blue)),
      );

  final doc = pw.Document(title: '심판 활동 이력 - ${profile['name']}', author: 'WINREF ACADEMY');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
    theme: pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
      defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10, lineSpacing: 2),
    ),
    footer: (ctx) => pw.Column(children: [
      pw.Divider(color: line, thickness: 0.5),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('문서번호 $docNo · 발급 ${DateFormat('yyyy.MM.dd').format(issued)}',
            style: const pw.TextStyle(fontSize: 8, color: muted)),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: muted)),
      ]),
    ]),
    build: (ctx) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logoPng != null) pw.Image(pw.MemoryImage(logoPng), width: 34, height: 34),
        if (logoPng != null) pw.SizedBox(width: 10),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('WINREF ACADEMY', style: pw.TextStyle(font: bold, fontSize: 11, color: blue, letterSpacing: 2)),
          pw.Text('스포츠 인재은행', style: const pw.TextStyle(fontSize: 9, color: muted)),
        ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('심판 활동 이력', style: pw.TextStyle(font: bold, fontSize: 20)),
      pw.SizedBox(height: 4),
      pw.Container(width: 40, height: 2, color: blue),
      head('인적 사항'),
      infoRow('성명', '${profile['name'] ?? '-'}'),
      infoRow('생년월일', d(profile['birth_date'])),
      infoRow('활동 지역', '${profile['region'] ?? '-'}'),
      infoRow('주 종목', '${profile['sport'] ?? '-'}'),
      head('보유 자격 (관리자 확인 완료)'),
      if (quals.isEmpty)
        pw.Text('확인된 자격이 없습니다.', style: const pw.TextStyle(color: muted))
      else
        pw.TableHelper.fromTextArray(
          headers: ['자격명', '등급', '취득일', '유효기간'],
          data: [for (final q in quals) [q['name'], q['grade'] ?? '-', d(q['acquired_on']), d(q['expires_on'])]],
          headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: blue),
          cellStyle: const pw.TextStyle(fontSize: 9),
          border: pw.TableBorder.all(color: line, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        ),
      head('활동 요약'),
      pw.Text('활동 완료 ${history.length}회'
          '${byPos.isEmpty ? '' : ' · ${byPos.entries.map((e) => '${e.key} ${e.value}회').join(' · ')}'}'),
      head('대회 활동 내역'),
      if (history.isEmpty)
        pw.Text('완료된 활동이 없습니다.', style: const pw.TextStyle(color: muted))
      else
        pw.TableHelper.fromTextArray(
          headers: ['No', '대회명', '기간', '장소', '포지션'],
          data: [
            for (var i = 0; i < history.length; i++)
              [
                '${i + 1}',
                history[i]['competition_name'],
                history[i]['ends_on'] != null && history[i]['ends_on'] != history[i]['starts_on']
                    ? '${d(history[i]['starts_on'])} ~ ${d(history[i]['ends_on'])}'
                    : d(history[i]['starts_on']),
                history[i]['venue'] ?? '-',
                history[i]['position'],
              ],
          ],
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2.2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(1.1),
          },
          headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: blue),
          cellStyle: const pw.TextStyle(fontSize: 9),
          border: pw.TableBorder.all(color: line, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        ),
      pw.SizedBox(height: 24),
      pw.Text('본 문서는 WINREF 인재은행 앱에 기록된 활동완료 내역과 관리자가 확인한 자격 정보를 출력한 것입니다.',
          style: const pw.TextStyle(fontSize: 8.5, color: muted)),
      pw.SizedBox(height: 4),
      pw.Text('사회적기업 창업지원사업', style: const pw.TextStyle(fontSize: 8, color: muted)),
    ],
  ));
  return doc.save();
}
