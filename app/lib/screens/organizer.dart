import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';
import 'profile.dart';

/// 대회관계자 홈: 내 대회 목록 → 대회별 모집공고·지원자·브리핑 관리
class OrganizerHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const OrganizerHome({super.key, required this.profile});
  @override
  State<OrganizerHome> createState() => _OrganizerHomeState();
}

class _OrganizerHomeState extends State<OrganizerHome> {
  final _key = GlobalKey<_OrganizerBoardState>();
  late Map<String, dynamic> _profile = widget.profile;
  bool get _approved => _profile['org_status'] == 'approved';

  Future<void> _refreshProfile() async {
    final p = await db.from('profiles').select().eq('id', uid).single();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _create() async {
    final v = await editCompetitionForm(context);
    if (v == null || !mounted) return;
    await run(context, () => db.from('competitions').insert({...v, 'organizer_id': uid}), done: '대회를 등록했습니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 대회'), actions: commonActions(context, _profile)),
      floatingActionButton: _approved
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('대회 등록'))
          : null,
      body: Column(children: [
        if (!_approved)
          Container(
            width: double.infinity,
            color: const Color(0xFFF1E7D3),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Text(
                  _profile['org_status'] == 'rejected'
                      ? '기관 승인이 거절되었습니다. WINREF 관리자에게 문의하세요.'
                      : '기관 승인 대기 중입니다. 승인 후 대회 등록이 가능합니다.',
                  style: const TextStyle(color: Brand.navy),
                ),
              ),
              TextButton(onPressed: _refreshProfile, child: const Text('승인 확인')),
            ]),
          ),
        Expanded(child: _OrganizerBoard(key: _key)),
      ]),
    );
  }
}

/// 대회관계자 홈: 요약 + 대회별 D-day·선발 진행률·검토 대기
class _OrganizerBoard extends StatefulWidget {
  const _OrganizerBoard({super.key});
  @override
  State<_OrganizerBoard> createState() => _OrganizerBoardState();
}

class _OrganizerBoardState extends State<_OrganizerBoard> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() => db
      .from('competitions')
      .select('*, recruitments(id, position, headcount, is_open, deadline, applications(status, completed_at))')
      .eq('organizer_id', uid)
      .order('starts_on');

  void reload() => setState(() => _f = _load());

  /// 대회 하나의 집계: 모집 인원, 지원, 검토 대기, 선발, 모집중 여부
  static ({int quota, int applied, int pending, int selected, bool open}) stats(Map<String, dynamic> c) {
    var quota = 0, applied = 0, pending = 0, selected = 0;
    var open = false;
    for (final r in (c['recruitments'] as List)) {
      quota += (r['headcount'] as num).toInt();
      final dl = DateTime.tryParse(r['deadline'] ?? '');
      if (r['is_open'] == true && (dl == null || dl.isAfter(DateTime.now()))) open = true;
      for (final a in (r['applications'] as List)) {
        if (a['status'] == 'cancelled') continue;
        applied++;
        if (a['status'] == 'applied') pending++;
        if (a['status'] == 'selected') selected++;
      }
    }
    return (quota: quota, applied: applied, pending: pending, selected: selected, open: open);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: TextButton(onPressed: reload, child: const Text('불러오기 실패 (다시 시도)')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final today = DateTime.now().toIso8601String().substring(0, 10);
        final upcoming = snap.data!.where((c) => (c['ends_on'] ?? c['starts_on']).toString().compareTo(today) >= 0).toList();
        final past = snap.data!.where((c) => !upcoming.contains(c)).toList().reversed.toList();
        final all = upcoming.map(stats).toList();
        final pending = all.fold<int>(0, (s, x) => s + x.pending);
        final quota = all.fold<int>(0, (s, x) => s + x.quota);
        final selected = all.fold<int>(0, (s, x) => s + x.selected);
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: ListView(padding: const EdgeInsets.only(bottom: 96), children: [
            Container(
              color: Brand.navy,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Container(
                decoration: BoxDecoration(color: Brand.navyLight, borderRadius: BorderRadius.circular(6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  _sum('예정 대회', '${upcoming.length}'),
                  _sum('검토 대기', '$pending', highlight: pending > 0),
                  _sum('선발 충원율', quota == 0 ? '-' : '${(selected * 100 / quota).round()}%'),
                ]),
              ),
            ),
            if (snap.data!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('등록한 대회가 없습니다.\n오른쪽 아래 버튼으로 대회를 등록하세요.', textAlign: TextAlign.center)),
              ),
            if (upcoming.isNotEmpty) _label('진행 예정'),
            for (final c in upcoming) _card(context, c),
            if (past.isNotEmpty) _label('지난 대회'),
            for (final c in past) _card(context, c, past: true),
          ]),
        );
      },
    );
  }

  Widget _sum(String label, String value, {bool highlight = false}) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(color: highlight ? Brand.gold : Brand.ivory, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFFB9C0D0), fontSize: 12)),
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(t, style: const TextStyle(color: Brand.navy, fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _card(BuildContext context, Map<String, dynamic> c, {bool past = false}) {
    final st = stats(c);
    final start = DateTime.tryParse(c['starts_on'] ?? '');
    final days = start == null
        ? null
        : DateTime(start.year, start.month, start.day)
            .difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day))
            .inDays;
    final dday = days == null ? '' : (days == 0 ? 'D-DAY' : (days > 0 ? 'D-$days' : '종료'));
    final ratio = st.quota == 0 ? 0.0 : (st.selected / st.quota).clamp(0.0, 1.0);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CompetitionManage(competition: c)))
            .then((_) => reload()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(c['name'],
                    style: TextStyle(fontWeight: FontWeight.w700, color: past ? Brand.muted : Brand.ink)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: past ? Brand.ivoryDeep : Brand.navy, borderRadius: BorderRadius.circular(3)),
                child: Text(dday,
                    style: TextStyle(color: past ? Brand.muted : Brand.gold, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('${fmtDate(c['starts_on'])} · ${c['venue'] ?? '-'}', style: const TextStyle(color: Brand.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ExcludeSemantics( // 진행률은 옆 '선발 n/m' 텍스트로 읽힘. 카드가 버튼으로 인식되게 함
                  child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    color: ratio >= 1 ? Brand.gold : Brand.navy,
                    backgroundColor: Brand.ivoryDeep,
                  ),
                ),
                ),
              ),
              const SizedBox(width: 10),
              Text('선발 ${st.selected}/${st.quota}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusChip('지원 ${st.applied}명', 'pending'),
              if (st.pending > 0) StatusChip('검토 대기 ${st.pending}명', 'selected'),
              if (!past) StatusChip(st.open ? '모집중' : '모집 마감', st.open ? 'approved' : 'cancelled'),
              if ((c['recruitments'] as List).isEmpty && !past) const StatusChip('모집공고 없음', 'rejected'),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// 대회 등록·수정 입력 화면 (관계자·관리자 공용). 기존 값이 있으면 채워서 연다.
Future<Map<String, dynamic>?> editCompetitionForm(BuildContext context, [Map<String, dynamic>? c]) {
  return showForm(context, c == null ? '대회 등록' : '대회 수정', [
    Field('name', '대회명', required: true, initial: c?['name']),
    Field('starts_on', '시작일', type: FieldType.date, required: true, initial: c?['starts_on']),
    Field('ends_on', '종료일', type: FieldType.date, initial: c?['ends_on']),
    Field('venue', '장소', initial: c?['venue']),
    Field('host_org', '주최·주관기관', initial: c?['host_org']),
    Field('poster_path', '포스터 (이미지/PDF)', type: FieldType.file, initial: c?['poster_path']),
  ], fileFolder: 'posters');
}

/// 대회 하나의 관리 화면 (관리자도 같은 화면을 사용)
class CompetitionManage extends StatefulWidget {
  final Map<String, dynamic> competition;
  const CompetitionManage({super.key, required this.competition});
  @override
  State<CompetitionManage> createState() => _CompetitionManageState();
}

class _CompetitionManageState extends State<CompetitionManage> {
  late Map<String, dynamic> competition = widget.competition;

  Future<void> _edit() async {
    final v = await editCompetitionForm(context, competition);
    if (v == null || !mounted) return;
    final ok = await run(context, () => db.from('competitions').update(v).eq('id', competition['id']), done: '대회 정보를 수정했습니다.');
    if (ok) setState(() => competition = {...competition, ...v});
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('대회 삭제'),
        content: Text('${competition['name']}\n모집공고·지원 내역·브리핑이 함께 삭제되며 되돌릴 수 없습니다.\n'
            '(활동완료 기록이 있는 대회는 삭제되지 않습니다)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('삭제')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final ok = await run(context, () => db.from('competitions').delete().eq('id', competition['id']), done: '대회를 삭제했습니다.');
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(tooltip: '대회 수정', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: '대회 삭제', onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          ],
          title: Text(competition['name']),
          bottom: const TabBar(tabs: [Tab(text: '모집공고'), Tab(text: '지원자'), Tab(text: '브리핑')]),
        ),
        body: TabBarView(children: [
          _RecruitmentsManage(cid: competition['id']),
          _ApplicantsManage(cid: competition['id']),
          _BriefingsManage(cid: competition['id']),
        ]),
      ),
    );
  }
}

// ---------- 모집공고 ----------

class _RecruitmentsManage extends StatefulWidget {
  final int cid;
  const _RecruitmentsManage({required this.cid});
  @override
  State<_RecruitmentsManage> createState() => _RecruitmentsManageState();
}

class _RecruitmentsManageState extends State<_RecruitmentsManage> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _edit([Map<String, dynamic>? r]) async {
    final v = await showForm(context, r == null ? '심판 모집공고 작성' : '모집공고 수정', [
      Field('position', '모집 포지션', required: true, initial: r?['position']),
      Field('headcount', '모집 인원', type: FieldType.number, required: true, initial: r?['headcount']?.toString()),
      Field('requirements', '자격조건', type: FieldType.multiline, initial: r?['requirements']),
      Field('deadline', '지원 마감', type: FieldType.datetime, initial: r?['deadline']),
      Field('preparation', '준비사항', type: FieldType.multiline, initial: r?['preparation']),
    ]);
    if (v == null || !mounted) return;
    await run(context, () async {
      if (r == null) {
        await db.from('recruitments').insert({...v, 'competition_id': widget.cid});
      } else {
        await db.from('recruitments').update(v).eq('id', r['id']);
      }
    }, done: '저장했습니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _edit, child: const Icon(Icons.add)),
      body: AsyncList(
        key: _key,
        load: () => db.from('recruitments').select().eq('competition_id', widget.cid).order('created_at'),
        empty: '모집공고가 없습니다.',
        item: (c, r, reload) => ListTile(
          title: Text('${r['position']} · ${r['headcount']}명'),
          subtitle: Text('마감 ${fmtDateTime(r['deadline'])}'),
          onTap: () => _edit(r),
          trailing: Switch(
            value: r['is_open'] == true,
            onChanged: (v) async {
              await run(c, () => db.from('recruitments').update({'is_open': v}).eq('id', r['id']),
                  done: v ? '모집을 열었습니다.' : '모집을 마감했습니다.');
              reload();
            },
          ),
        ),
      ),
    );
  }
}

// ---------- 지원자 확인·선발·참석·활동완료 ----------

class _ApplicantsManage extends StatefulWidget {
  final int cid;
  const _ApplicantsManage({required this.cid});
  @override
  State<_ApplicantsManage> createState() => _ApplicantsManageState();
}

class _ApplicantsManageState extends State<_ApplicantsManage> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  bool _picking = false;
  final _picked = <int>{};
  String _filter = 'all';

  Future<List<Map<String, dynamic>>> _load() => db
      .from('applications')
      .select('*, profiles(*), recruitments!inner(id, position, headcount, competition_id)')
      .eq('recruitments.competition_id', widget.cid)
      .neq('status', 'cancelled')
      .order('created_at');

  void _reload() => setState(() {
        _f = _load();
        _picking = false;
        _picked.clear();
      });

  Future<void> _bulk(String status) async {
    final ids = _picked.toList();
    final ok = await run(context, () => db.from('applications').update({'status': status}).inFilter('id', ids),
        done: '${ids.length}명을 ${label(status)} 처리했습니다. 결과 알림이 발송됩니다.');
    if (ok) _reload();
  }

  Future<void> _export(List<Map<String, dynamic>> rows) => exportCsv(
        context,
        '지원자_${widget.cid}',
        ['이름', '연락처', '지역', '포지션', '선발결과', '참석', '활동완료', '지원일'],
        [
          for (final a in rows)
            [
              a['profiles']['name'],
              phoneCell(a['profiles']['phone']),
              a['profiles']['region'],
              a['recruitments']['position'],
              label(a['status']),
              label(a['attendance']),
              a['completed_at'] == null ? '' : fmtDateTime(a['completed_at']),
              fmtDateTime(a['created_at']),
            ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Center(child: TextButton(onPressed: _reload, child: const Text('불러오기 실패 (다시 시도)')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        // 포지션별 선발 현황 (선발 n / 모집 m)
        final quota = <String, (int, int)>{};
        for (final a in all) {
          final r = a['recruitments'];
          final cur = quota[r['position']] ?? (0, (r['headcount'] as num).toInt());
          quota[r['position']] = (cur.$1 + (a['status'] == 'selected' ? 1 : 0), cur.$2);
        }
        final rows = all.where((a) => _filter == 'all' || a['status'] == _filter).toList();
        return Scaffold(
          body: Column(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in quota.entries)
                        StatusChip('${e.key} 선발 ${e.value.$1}/${e.value.$2}',
                            e.value.$1 >= e.value.$2 ? 'selected' : 'pending'),
                    ]),
                  ),
                  IconButton(
                    tooltip: '엑셀 내보내기',
                    onPressed: all.isEmpty ? null : () => _export(rows),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                  TextButton(
                    onPressed: all.isEmpty ? null : () => setState(() { _picking = !_picking; _picked.clear(); }),
                    child: Text(_picking ? '선택 취소' : '일괄 선택'),
                  ),
                ]),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final f in const [('all', '전체'), ('applied', '지원완료'), ('selected', '선발'), ('reserve', '예비'), ('rejected', '미선발')])
                      Padding(
                        padding: const EdgeInsets.only(right: 6, top: 6),
                        child: ChoiceChip(
                          label: Text('${f.$2} ${f.$1 == 'all' ? all.length : all.where((a) => a['status'] == f.$1).length}'),
                          selected: _filter == f.$1,
                          showCheckmark: false,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() => _filter = f.$1),
                        ),
                      ),
                  ]),
                ),
              ]),
            ),
            const Divider(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: rows.isEmpty
                    ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('지원자가 없습니다.')))])
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (c, i) => _tile(c, rows[i]),
                      ),
              ),
            ),
          ]),
          bottomNavigationBar: !_picking
              ? null
              : SafeArea(
                  child: Container(
                    color: Brand.navy,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(children: [
                      Expanded(
                        child: Text('${_picked.length}명 선택',
                            style: const TextStyle(color: Brand.ivory, fontWeight: FontWeight.w600)),
                      ),
                      for (final st in const [('selected', '일괄 선발'), ('reserve', '일괄 예비'), ('rejected', '일괄 미선발')])
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 38),
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              backgroundColor: st.$1 == 'selected' ? Brand.gold : Brand.navyLight,
                            ),
                            onPressed: _picked.isEmpty ? null : () => _bulk(st.$1),
                            child: Text(st.$2),
                          ),
                        ),
                    ]),
                  ),
                ),
        );
      },
    );
  }

  Widget _tile(BuildContext c, Map<String, dynamic> a) {
    final p = a['profiles'] as Map<String, dynamic>;
    final done = a['completed_at'] != null;
    final title = '${p['name']} · ${a['recruitments']['position']}';
    final sub = a['status'] == 'selected'
        ? '참석 ${label(a['attendance'])}${done ? ' · 활동완료' : ''}'
        : '지원 ${fmtDate(a['created_at'])}${p['region'] != null ? ' · ${p['region']}' : ''}';
    if (_picking) {
      final id = a['id'] as int;
      return CheckboxListTile(
        value: _picked.contains(id),
        onChanged: done ? null : (v) => setState(() => v == true ? _picked.add(id) : _picked.remove(id)),
        secondary: Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 40),
        title: Text(title),
        subtitle: Text(sub),
      );
    }
    return ListTile(
      leading: Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 40),
      title: Text(title),
      subtitle: Text(sub),
      trailing: StatusChip(done ? '활동완료' : label(a['status']), done ? 'approved' : a['status']),
      onTap: () async {
        await showModalBottomSheet(
          context: c,
          isScrollControlled: true,
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.85,
            maxChildSize: 0.95,
            builder: (_, sc) => _ApplicantSheet(app: a, controller: sc),
          ),
        );
        _reload();
      },
    );
  }
}

class _ApplicantSheet extends StatelessWidget {
  final Map<String, dynamic> app;
  final ScrollController controller;
  const _ApplicantSheet({required this.app, required this.controller});

  Future<void> _set(BuildContext context, Map<String, dynamic> v, String msg) async {
    final ok = await run(context, () => db.from('applications').update(v).eq('id', app['id']), done: msg);
    if (ok && context.mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = app['profiles'] as Map<String, dynamic>;
    final selected = app['status'] == 'selected';
    final done = app['completed_at'] != null;
    return SafeArea(
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
                Text('${app['recruitments']['position']} 지원 · ${fmtDate(app['created_at'])}',
                    style: const TextStyle(color: Brand.muted)),
              ]),
            ),
            StatusChip(label(app['status']), app['status']),
          ]),
          const SizedBox(height: 16),
          if (!done) ...[
            const Text('선발 처리', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final s in ['selected', 'reserve', 'rejected'])
                ChoiceChip(
                  label: Text(label(s)),
                  selected: app['status'] == s,
                  onSelected: (_) => _set(context, {'status': s}, '${label(s)} 처리했습니다.'),
                ),
            ]),
          ],
          if (selected && !done) ...[
            const SizedBox(height: 16),
            const Text('참석 여부', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final s in ['attending', 'absent'])
                ChoiceChip(
                  label: Text(label(s)),
                  selected: app['attendance'] == s,
                  onSelected: (_) => _set(context, {'attendance': s}, '참석 여부를 저장했습니다.'),
                ),
            ]),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => _set(context, {'completed_at': DateTime.now().toUtc().toIso8601String()},
                  '활동완료 처리했습니다. 활동이력에 반영됩니다.'),
              child: const Text('활동완료 처리'),
            ),
          ],
          if (done) Text('활동완료: ${fmtDateTime(app['completed_at'])}'),
          const Divider(height: 36),
          CareerView(profile: p, showContact: true),
        ]),
      ),
    );
  }
}

// ---------- 브리핑 자료 ----------

class _BriefingsManage extends StatefulWidget {
  final int cid;
  const _BriefingsManage({required this.cid});
  @override
  State<_BriefingsManage> createState() => _BriefingsManageState();
}

class _BriefingsManageState extends State<_BriefingsManage> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _add() async {
    final v = await showForm(context, '브리핑 자료 등록', const [
      Field('title', '제목', required: true),
      Field('body', '공지·경기일정·준비사항', type: FieldType.multiline),
      Field('file_path', '첨부 (PDF/이미지)', type: FieldType.file),
    ], fileFolder: 'briefings/${widget.cid}');
    if (v == null || !mounted) return;
    await run(context, () => db.from('briefings').insert({...v, 'competition_id': widget.cid}),
        done: '등록했습니다. 선발된 심판에게 공개됩니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: AsyncList(
        key: _key,
        load: () => db.from('briefings').select().eq('competition_id', widget.cid).order('created_at'),
        empty: '브리핑 자료가 없습니다.\n선발된 심판에게만 공개됩니다.',
        item: (c, b, reload) => ListTile(
          title: Text(b['title']),
          subtitle: Text(b['body'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: b['file_path'] == null ? null : () => openFile(c, b['file_path']),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await run(c, () => db.from('briefings').delete().eq('id', b['id']), done: '삭제했습니다.');
              reload();
            },
          ),
        ),
      ),
    );
  }
}
