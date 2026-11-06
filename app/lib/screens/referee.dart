import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';

/// 심판·교육신청자 홈: 대회 / 교육 / 내 활동 / 자격
class RefereeHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RefereeHome({super.key, required this.profile});
  @override
  State<RefereeHome> createState() => _RefereeHomeState();
}

class _RefereeHomeState extends State<RefereeHome> {
  int _tab = 0;
  static const _titles = ['대회 모집', '교육', '내 활동', '자격정보'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab]), actions: commonActions(context, widget.profile)),
      body: IndexedStack(index: _tab, children: const [
        _RecruitmentsTab(),
        _CoursesTab(),
        _MyActivityTab(),
        _QualificationsTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.sports_outlined), label: '대회'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: '교육'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: '내 활동'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), label: '자격'),
        ],
      ),
    );
  }
}

// ---------- 대회 조회·지원 ----------

class _RecruitmentsTab extends StatelessWidget {
  const _RecruitmentsTab();
  @override
  Widget build(BuildContext context) {
    return AsyncList(
      load: () => db
          .from('recruitments')
          .select('*, competitions(*)')
          .eq('is_open', true)
          .order('deadline', ascending: true, nullsFirst: false),
      empty: '모집 중인 대회가 없습니다.',
      item: (c, r, reload) {
        final comp = r['competitions'] as Map<String, dynamic>;
        return ListTile(
          title: Text(comp['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${fmtDate(comp['starts_on'])} · ${comp['venue'] ?? '-'}\n'
              '${r['position']} ${r['headcount']}명 · 마감 ${fmtDateTime(r['deadline'])}'),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => RecruitmentDetail(recruitment: r)))
              .then((_) => reload()),
        );
      },
    );
  }
}

class RecruitmentDetail extends StatefulWidget {
  final Map<String, dynamic> recruitment;
  const RecruitmentDetail({super.key, required this.recruitment});
  @override
  State<RecruitmentDetail> createState() => _RecruitmentDetailState();
}

class _RecruitmentDetailState extends State<RecruitmentDetail> {
  Map<String, dynamic>? _mine;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await db
        .from('applications')
        .select()
        .eq('recruitment_id', widget.recruitment['id'])
        .eq('user_id', uid);
    if (mounted) setState(() { _mine = rows.isEmpty ? null : rows.first; _loaded = true; });
  }

  Future<void> _apply() async {
    final ok = await run(context, () async {
      if (_mine == null) {
        await db.from('applications').insert({'recruitment_id': widget.recruitment['id'], 'user_id': uid});
      } else {
        await db.from('applications').update({'status': 'applied'}).eq('id', _mine!['id']); // 취소 후 재지원
      }
    }, done: '지원했습니다.');
    if (ok) _load();
  }

  Future<void> _cancel() async {
    final ok = await run(context, () => db.from('applications').update({'status': 'cancelled'}).eq('id', _mine!['id']),
        done: '지원을 취소했습니다.');
    if (ok) _load();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recruitment;
    final comp = r['competitions'] as Map<String, dynamic>;
    final status = _mine?['status'] as String?;
    return Scaffold(
      appBar: AppBar(title: const Text('대회 상세')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(comp['name'], style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        _row('일정', '${fmtDate(comp['starts_on'])}${comp['ends_on'] != null ? ' ~ ${fmtDate(comp['ends_on'])}' : ''}'),
        _row('장소', comp['venue'] ?? '-'),
        _row('주최·주관', comp['host_org'] ?? '-'),
        const Divider(height: 32),
        _row('모집 포지션', r['position']),
        _row('모집 인원', '${r['headcount']}명'),
        _row('지원 조건', r['requirements'] ?? '-'),
        _row('마감', fmtDateTime(r['deadline'])),
        _row('준비사항', r['preparation'] ?? '-'),
        if (comp['poster_path'] != null) fileButton(context, comp['poster_path'], label: '대회 포스터 보기'),
        const SizedBox(height: 24),
        if (!_loaded)
          const Center(child: CircularProgressIndicator())
        else if (status == null || status == 'cancelled')
          FilledButton(onPressed: _apply, child: Text(status == 'cancelled' ? '다시 지원하기' : '심판 지원하기'))
        else ...[
          Row(children: [const Text('지원 상태  '), StatusChip(label(status), status)]),
          if (status == 'applied') ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _cancel, child: const Text('지원 취소')),
          ],
        ],
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(k, style: const TextStyle(color: Brand.muted))),
          Expanded(child: Text(v)),
        ]),
      );
}

// ---------- 교육 ----------

class _CoursesTab extends StatefulWidget {
  const _CoursesTab();
  @override
  State<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends State<_CoursesTab> {
  final _key = GlobalKey<AsyncListState>();

  Future<List<Map<String, dynamic>>> _load() async {
    final courses = await db.from('courses').select().order('starts_at', ascending: false);
    final mine = await db.from('course_applications').select().eq('user_id', uid);
    final byCourse = {for (final a in mine) a['course_id']: a};
    return [for (final c in courses) {...c, '_mine': byCourse[c['id']]}];
  }

  Future<void> _apply(Map<String, dynamic> c) async {
    await run(context, () async {
      final mine = c['_mine'];
      if (mine == null) {
        await db.from('course_applications').insert({'course_id': c['id'], 'user_id': uid});
      } else {
        await db.from('course_applications').update({'status': 'applied'}).eq('id', mine['id']);
      }
    }, done: '교육을 신청했습니다.');
    _key.currentState?.reload();
  }

  Future<void> _cancel(Map<String, dynamic> c) async {
    await run(context, () => db.from('course_applications').update({'status': 'cancelled'}).eq('id', c['_mine']['id']),
        done: '신청을 취소했습니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return AsyncList(
      key: _key,
      load: _load,
      empty: '등록된 교육과정이 없습니다.',
      item: (ctx, c, _) {
        final mine = c['_mine'] as Map<String, dynamic>?;
        final status = mine?['status'] as String?;
        final deadline = DateTime.tryParse(c['apply_deadline'] ?? '');
        final closed = deadline != null && deadline.isBefore(DateTime.now());
        return ExpansionTile(
          title: Row(children: [
            Expanded(child: Text(c['title'], style: const TextStyle(fontWeight: FontWeight.w600))),
            if (c['is_refresher'] == true) const StatusChip('보수교육', 'pending'),
          ]),
          subtitle: Text('${fmtDateTime(c['starts_at'])} · ${c['location'] ?? '-'}'),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(c['description'] ?? ''),
            const SizedBox(height: 8),
            Text('신청 마감 ${fmtDateTime(c['apply_deadline'])} · 정원 ${c['capacity'] ?? '-'}명',
                style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 12),
            if (status == 'applied' || status == 'confirmed')
              Row(children: [
                StatusChip(status == 'applied' ? '신청완료' : label(status), status!),
                const Spacer(),
                if (!closed) TextButton(onPressed: () => _cancel(c), child: const Text('신청 취소')),
              ])
            else if (closed)
              const Text('신청이 마감되었습니다.', style: TextStyle(color: Brand.muted))
            else
              FilledButton(onPressed: () => _apply(c), child: const Text('교육 신청')),
          ],
        );
      },
    );
  }
}

// ---------- 내 활동: 지원현황·선발결과·브리핑·활동이력 ----------

class _MyActivityTab extends StatelessWidget {
  const _MyActivityTab();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: Brand.navy,
          child: const TabBar(tabs: [Tab(text: '지원 현황'), Tab(text: '활동 이력')]),
        ),
        Expanded(
          child: TabBarView(children: [
            AsyncList(
              load: () => db
                  .from('applications')
                  .select('*, recruitments(position, competitions(id, name, starts_on, venue))')
                  .eq('user_id', uid)
                  .order('created_at', ascending: false),
              empty: '지원 내역이 없습니다.',
              item: (c, a, _) {
                final rec = a['recruitments'] as Map<String, dynamic>;
                final comp = rec['competitions'] as Map<String, dynamic>;
                final selected = a['status'] == 'selected';
                return ListTile(
                  title: Text(comp['name']),
                  subtitle: Text('${fmtDate(comp['starts_on'])} · ${rec['position']}'
                      '${selected ? ' · 참석 ${label(a['attendance'])}' : ''}'),
                  trailing: StatusChip(label(a['status']), a['status']),
                  onTap: selected
                      ? () => Navigator.push(c, MaterialPageRoute(builder: (_) => BriefingScreen(competition: comp)))
                      : null,
                );
              },
            ),
            AsyncList(
              load: () => db.from('activity_history').select().eq('user_id', uid).order('starts_on', ascending: false),
              empty: '활동 이력이 없습니다.',
              item: (c, h, _) => ListTile(
                leading: const Icon(Icons.verified_outlined, color: Brand.gold),
                title: Text(h['competition_name']),
                subtitle: Text('${fmtDate(h['starts_on'])} · ${h['venue'] ?? '-'} · ${h['position']}'),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// 선발된 대회의 공지·브리핑 자료
class BriefingScreen extends StatelessWidget {
  final Map<String, dynamic> competition;
  const BriefingScreen({super.key, required this.competition});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('브리핑 자료')),
      body: AsyncList(
        load: () => db.from('briefings').select().eq('competition_id', competition['id']).order('created_at'),
        empty: '등록된 브리핑 자료가 없습니다.',
        item: (c, b, _) => ExpansionTile(
          initiallyExpanded: true,
          title: Text(b['title']),
          subtitle: Text(fmtDateTime(b['created_at'])),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [Text(b['body'] ?? ''), fileButton(c, b['file_path'])],
        ),
      ),
    );
  }
}

// ---------- 자격정보 ----------

class _QualificationsTab extends StatefulWidget {
  const _QualificationsTab();
  @override
  State<_QualificationsTab> createState() => _QualificationsTabState();
}

class _QualificationsTabState extends State<_QualificationsTab> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _add() async {
    final v = await showForm(context, '자격 등록', const [
      Field('name', '자격명', required: true),
      Field('grade', '등급'),
      Field('acquired_on', '취득일', type: FieldType.date),
      Field('expires_on', '유효기간(만료일)', type: FieldType.date),
    ]);
    if (v == null || !mounted) return;
    await run(context, () => db.from('qualifications').insert({...v, 'user_id': uid}),
        done: '등록했습니다. 관리자 확인 후 승인됩니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
      body: AsyncList(
        key: _key,
        load: () => db.from('qualifications').select().eq('user_id', uid).order('created_at', ascending: false),
        empty: '등록된 자격이 없습니다.\n+ 버튼으로 등록하세요.',
        item: (c, q, reload) {
          final exp = DateTime.tryParse(q['expires_on'] ?? '');
          final soon = exp != null && exp.difference(DateTime.now()).inDays <= 90;
          return ListTile(
            title: Text('${q['name']}${q['grade'] != null ? ' · ${q['grade']}' : ''}'),
            subtitle: Text('취득 ${fmtDate(q['acquired_on'])} · 만료 ${fmtDate(q['expires_on'])}'
                '${soon ? ' (보수교육 필요)' : ''}\n보수교육 ${q['refresher_done'] == true ? '이수' : '미이수'}'),
            isThreeLine: true,
            trailing: StatusChip(label(q['status']), q['status']),
            onLongPress: q['status'] != 'pending'
                ? null
                : () async {
                    await run(c, () => db.from('qualifications').delete().eq('id', q['id']), done: '삭제했습니다.');
                    reload();
                  },
          );
        },
      ),
    );
  }
}
