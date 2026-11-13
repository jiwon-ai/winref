import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../common.dart';
import '../theme.dart';

// ---------- 성과 리포트 ----------

/// 리포트 항목 (화면·PDF·엑셀이 같은 목록을 쓴다): (구분, 항목, json 키, 단위)
const reportRows = <(String, String, String, String)>[
  ('회원', '신규 가입', 'new_members', '명'),
  ('회원', '  · 심판·교육신청자', 'new_referees', '명'),
  ('회원', '  · 대회관계자', 'new_organizers', '명'),
  ('회원', '현재 전체 회원', 'members_total', '명'),
  ('자격', '자격 등록 신청', 'quals_submitted', '건'),
  ('자격', '자격 승인', 'quals_approved', '건'),
  ('자격', '자격 반려', 'quals_rejected', '건'),
  ('자격', '현재 승인된 자격', 'quals_approved_total', '건'),
  ('교육', '교육과정 (기간 내 시작)', 'courses', '개'),
  ('교육', '교육 신청', 'course_applications', '건'),
  ('대회', '대회 (기간 내 개최)', 'competitions', '개'),
  ('대회', '모집공고', 'recruitments', '건'),
  ('대회', '모집 인원', 'headcount', '명'),
  ('대회', '심판 지원', 'applications', '건'),
  ('대회', '선발', 'selected', '명'),
  ('대회', '현장 출석 확인 (QR)', 'checked_in', '명'),
  ('대회', '활동 완료', 'completed', '건'),
  ('기타', '활동확인서 발급', 'certificates', '건'),
  ('기타', '공지사항', 'notices', '건'),
];

class ReportPage extends StatefulWidget {
  const ReportPage({super.key});
  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late DateTimeRange _range;
  late Future<Map<String, dynamic>> _f;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31)); // 올해 전체
    _f = _load();
  }

  String _d(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String get _period => '${fmtDate(_range.start.toIso8601String())} ~ ${fmtDate(_range.end.toIso8601String())}';

  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
      await db.rpc('admin_report', params: {'p_from': _d(_range.start), 'p_to': _d(_range.end)}) as Map);

  void _set(DateTimeRange r) => setState(() {
        _range = r;
        _f = _load();
      });

  Future<void> _pick() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      helpText: '리포트 기간',
      saveText: '적용',
    );
    if (r != null) _set(r);
  }

  Future<void> _csv(Map<String, dynamic> r) => exportCsv(context, 'WINREF_성과리포트_${_d(_range.start)}_${_d(_range.end)}', [
        '구분',
        '항목',
        '값',
        '단위'
      ], [
        ['기간', _period, '', ''],
        for (final x in reportRows) [x.$1, x.$2.trim(), r[x.$3] ?? 0, x.$4],
        ['', '', '', ''],
        ['대회별', '대회명', '개최일', '모집/지원/선발/출석/완료'],
        for (final c in (r['by_competition'] as List? ?? const []))
          ['대회별', c['name'], fmtDate(c['starts_on']), '${c['headcount']}/${c['applied']}/${c['selected']}/${c['checked_in']}/${c['completed']}'],
      ]);

  Future<void> _pdf(Map<String, dynamic> r) => run(context, () async {
        final regular = await PdfGoogleFonts.notoSansKRRegular();
        final bold = await PdfGoogleFonts.notoSansKRBold();
        final logo = (await rootBundle.load('assets/brand/snowflake_blue.png')).buffer.asUint8List();
        final bytes = await buildReportPdf(report: r, period: _period, regular: regular, bold: bold, logoPng: logo);
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'WINREF_성과리포트_${_d(_range.start)}_${_d(_range.end)}.pdf');
      });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        final r = snap.data;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('리포트 기간', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('지원사업 결과보고 등에 쓸 수 있도록 기간 안의 실적을 모아 보여줍니다. (한국 시간 기준)',
                    style: TextStyle(color: Brand.muted, fontSize: 13)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(_period),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  ActionChip(label: const Text('올해'), onPressed: () => _set(DateTimeRange(start: DateTime(now.year, 1, 1), end: DateTime(now.year, 12, 31)))),
                  ActionChip(label: const Text('이번 달'), onPressed: () => _set(DateTimeRange(start: DateTime(now.year, now.month, 1), end: today))),
                  ActionChip(
                      label: const Text('최근 30일'),
                      onPressed: () => _set(DateTimeRange(start: today.subtract(const Duration(days: 29)), end: today))),
                  ActionChip(
                      label: const Text('지난해'),
                      onPressed: () => _set(DateTimeRange(start: DateTime(now.year - 1, 1, 1), end: DateTime(now.year - 1, 12, 31)))),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: r == null ? null : () => _pdf(r),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('PDF 로 저장'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: r == null ? null : () => _csv(r),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('엑셀 내보내기'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          if (snap.hasError)
            ErrorView(error: snap.error, onRetry: () => setState(() => _f = _load()))
          else if (r == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else ...[
            for (final group in ['회원', '자격', '교육', '대회', '기타'])
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(group, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    for (final x in reportRows.where((x) => x.$1 == group))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(
                            child: Text(x.$2,
                                style: TextStyle(color: x.$2.startsWith(' ') ? Brand.muted : Brand.ink)),
                          ),
                          Text('${r[x.$3] ?? 0}',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Brand.navy)),
                          SizedBox(width: 24, child: Text(' ${x.$4}', style: TextStyle(color: Brand.muted, fontSize: 12))),
                        ]),
                      ),
                  ]),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('대회별 실적', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if ((r['by_competition'] as List? ?? const []).isEmpty)
                    Text('기간 안에 개최된 대회가 없습니다.', style: TextStyle(color: Brand.muted))
                  else
                    for (final c in r['by_competition'] as List)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${c['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${fmtDate(c['starts_on'])} · 모집 ${c['headcount']}명 · 지원 ${c['applied']} · 선발 ${c['selected']} · 출석 ${c['checked_in']} · 완료 ${c['completed']}',
                              style: TextStyle(color: Brand.muted, fontSize: 13)),
                        ]),
                      ),
                ]),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text('탈퇴한 회원의 기록은 집계에서 빠집니다. 자격 승인·반려 건수는 처리 기록이 쌓이기 시작한 날부터 집계됩니다.',
                  style: TextStyle(color: Brand.muted, fontSize: 12)),
            ),
          ],
        ]);
      },
    );
  }
}

/// 성과 리포트 PDF (A4 1~2쪽)
Future<Uint8List> buildReportPdf({
  required Map<String, dynamic> report,
  required String period,
  required pw.Font regular,
  required pw.Font bold,
  Uint8List? logoPng,
  DateTime? issuedAt,
}) async {
  const blue = PdfColor.fromInt(0xFF2560AC);
  const line = PdfColor.fromInt(0xFFC3D0E0);
  const muted = PdfColor.fromInt(0xFF5D6B7E);
  final issued = issuedAt ?? DateTime.now();
  final comps = (report['by_competition'] as List? ?? const []);
  String d(dynamic v) {
    final t = DateTime.tryParse(v?.toString() ?? '');
    return t == null ? '-' : DateFormat('yyyy.MM.dd').format(t);
  }

  pw.Widget head(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 8),
        child: pw.Text(t, style: pw.TextStyle(font: bold, fontSize: 12, color: blue)),
      );
  pw.Widget table(List<String> headers, List<List<String>> data, {Map<int, pw.TableColumnWidth>? widths}) =>
      pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        columnWidths: widths,
        headerStyle: pw.TextStyle(font: bold, fontSize: 9, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: blue),
        cellStyle: const pw.TextStyle(fontSize: 9),
        border: pw.TableBorder.all(color: line, width: 0.5),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      );

  final doc = pw.Document(title: 'WINREF 성과 리포트 $period', author: 'WINREF ACADEMY');
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 48),
    theme: pw.ThemeData.withFont(base: regular, bold: bold).copyWith(
      defaultTextStyle: pw.TextStyle(font: regular, fontSize: 10, lineSpacing: 2),
    ),
    footer: (ctx) => pw.Column(children: [
      pw.Divider(color: line, thickness: 0.5),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('출력 ${DateFormat('yyyy.MM.dd HH:mm').format(issued)} · 주식회사 윈렙아카데미',
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
          pw.Text('알파인 스키 심판 인재은행', style: const pw.TextStyle(fontSize: 9, color: muted)),
        ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Text('운영 성과 리포트', style: pw.TextStyle(font: bold, fontSize: 20)),
      pw.SizedBox(height: 4),
      pw.Container(width: 40, height: 2, color: blue),
      pw.SizedBox(height: 10),
      pw.Text('집계 기간: $period (한국 시간 기준)'),
      head('주요 실적'),
      table(
        ['구분', '항목', '실적'],
        [for (final x in reportRows) [x.$1, x.$2.trim(), '${report[x.$3] ?? 0}${x.$4}']],
        widths: {0: const pw.FixedColumnWidth(60), 1: const pw.FlexColumnWidth(3), 2: const pw.FixedColumnWidth(80)},
      ),
      head('대회별 실적'),
      if (comps.isEmpty)
        pw.Text('기간 안에 개최된 대회가 없습니다.', style: const pw.TextStyle(color: muted))
      else
        table(
          ['대회명', '개최일', '모집', '지원', '선발', '출석', '완료'],
          [
            for (final c in comps)
              ['${c['name']}', d(c['starts_on']), '${c['headcount']}', '${c['applied']}', '${c['selected']}', '${c['checked_in']}', '${c['completed']}']
          ],
          widths: {0: const pw.FlexColumnWidth(3), 1: const pw.FixedColumnWidth(64)},
        ),
      pw.SizedBox(height: 20),
      pw.Text('본 리포트는 WINREF 알파인 스키 심판 인재은행 앱에 기록된 자료를 집계한 것입니다. 탈퇴한 회원의 기록은 포함되지 않습니다.',
          style: const pw.TextStyle(fontSize: 8.5, color: muted)),
      pw.SizedBox(height: 4),
      pw.Text('사회적기업 창업지원사업', style: const pw.TextStyle(fontSize: 8, color: muted)),
    ],
  ));
  return doc.save();
}

// ---------- 처리 기록 · 오류 기록 ----------

const auditLabels = <String, String>{
  'qual_approved': '자격 승인',
  'qual_rejected': '자격 반려',
  'qual_deleted': '자격 삭제',
  'role_changed': '회원 유형 변경',
  'org_approved': '기관 승인',
  'org_rejected': '기관 반려',
  'member_deleted': '탈퇴 처리',
  'member_left': '본인 탈퇴',
  'selection': '선발 처리',
  'activity_completed': '활동완료',
  'checkin': '현장 출석',
  'competition_deleted': '대회 삭제',
};

const _roleKo = {'admin': '관리자', 'organizer': '대회관계자', 'referee': '심판'};

/// 기록 상세 문구를 한국어로 (예: 'applied → selected' → '지원완료 → 선발')
String auditDetail(String? detail) {
  if (detail == null) return '';
  return detail.split(' → ').map((w) => _roleKo[w] ?? statusLabel[w] ?? w).join(' → ');
}

class AuditPage extends StatefulWidget {
  const AuditPage({super.key});
  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  String _action = 'all';
  String _q = '';
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    var q = db.from('audit_log').select();
    if (_action != 'all') q = q.eq('action', _action);
    return q.order('at', ascending: false).limit(500);
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        ColoredBox(
          color: Brand.card,
          child: TabBar(tabs: [Tab(text: '처리 기록'), Tab(text: '앱 오류 기록')]),
        ),
        Expanded(
          child: TabBarView(children: [
            _audit(context),
            const _ErrorLogs(),
          ]),
        ),
      ]),
    );
  }

  Widget _audit(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (context, snap) {
          final all = snap.data ?? const <Map<String, dynamic>>[];
          final rows = all
              .where((r) => _q.isEmpty || '${r['actor_name']} ${r['target']} ${r['detail']}'.toLowerCase().contains(_q.toLowerCase()))
              .toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '처리자·대상 검색', isDense: true),
                    onChanged: (v) => setState(() => _q = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: rows.isEmpty
                      ? null
                      : () => exportCsv(context, 'WINREF_처리기록', [
                            '일시',
                            '처리',
                            '대상',
                            '상세',
                            '처리자',
                            '처리자 유형'
                          ], [
                            for (final r in rows)
                              [fmtDateTime(r['at']), auditLabels[r['action']] ?? r['action'], r['target'], auditDetail(r['detail']), r['actor_name'], _roleKo[r['actor_role']] ?? '']
                          ]),
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('엑셀 내보내기'),
                ),
              ]),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                for (final e in [const MapEntry('all', '전체'), ...auditLabels.entries])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _action == e.key,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => setState(() {
                        _action = e.key;
                        _f = _load();
                      }),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: snap.hasError
                  ? ErrorView(error: snap.error, onRetry: _reload)
                  : !snap.hasData
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: () async => _reload(),
                          child: rows.isEmpty
                              ? ListView(children: const [EmptyView('처리 기록이 없습니다.\n자격 승인, 선발, 출석, 탈퇴 처리 등을 하면 여기에 남습니다.')])
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                                  itemCount: rows.length + 1,
                                  itemBuilder: (c, i) {
                                    if (i == rows.length) {
                                      return Padding(
                                        padding: EdgeInsets.all(12),
                                        child: Text('최근 500건까지 표시 · 기록은 1년 보관 후 자동 삭제되며 수정·삭제할 수 없습니다.',
                                            textAlign: TextAlign.center, style: TextStyle(color: Brand.muted, fontSize: 12)),
                                      );
                                    }
                                    final r = rows[i];
                                    final detail = auditDetail(r['detail']);
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        title: Text('${auditLabels[r['action']] ?? r['action']} · ${r['target'] ?? ''}'),
                                        subtitle: Text(
                                            '${fmtDateTime(r['at'])} · ${r['actor_name'] ?? '-'}${_roleKo[r['actor_role']] == null ? '' : ' (${_roleKo[r['actor_role']]})'}'
                                            '${detail.isEmpty ? '' : '\n$detail'}'),
                                        isThreeLine: detail.isNotEmpty,
                                      ),
                                    );
                                  },
                                ),
                        ),
            ),
          ]);
        },
      );
}

class _ErrorLogs extends StatefulWidget {
  const _ErrorLogs();
  @override
  State<_ErrorLogs> createState() => _ErrorLogsState();
}

class _ErrorLogsState extends State<_ErrorLogs> {
  final _key = GlobalKey<AsyncListState>();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Text('사용자 기기에서 앱이 예상하지 못한 오류를 만나면 자동으로 여기에 모입니다. (90일 보관, 이름·연락처는 저장하지 않음)',
            style: TextStyle(color: Brand.muted, fontSize: 13)),
      ),
      Expanded(
        child: AsyncList(
          key: _key,
          load: () => db.from('error_logs').select().order('at', ascending: false).limit(200),
          empty: '수집된 오류가 없습니다.',
          item: (c, e, reload) => ExpansionTile(
            title: Text('${e['message']}', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${fmtDateTime(e['at'])} · ${e['platform'] ?? '-'} · 빌드 ${e['build'] ?? '-'}${e['user_id'] == null ? ' · 비로그인' : ''}'),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              SelectableText('${e['message']}\n\n${e['stack'] ?? ''}', style: const TextStyle(fontSize: 12, height: 1.4)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await run(c, () => db.from('error_logs').delete().eq('id', e['id']), done: '기록을 지웠습니다.');
                    reload();
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('확인함 (지우기)'),
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}
