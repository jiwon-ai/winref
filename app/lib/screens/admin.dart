import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';
import 'organizer.dart';
import 'profile.dart';

/// WINREF 관리자 콘솔 (웹 우선, 모바일에서도 동작)
class AdminHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const AdminHome({super.key, required this.profile});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _i = 0;
  static const _menu = <(IconData, String)>[
    (Icons.insights_outlined, '대시보드'),
    (Icons.people_outline, '회원'),
    (Icons.badge_outlined, '자격 승인'),
    (Icons.school_outlined, '교육'),
    (Icons.sports_outlined, '대회'),
    (Icons.campaign_outlined, '공지·알림'),
  ];

  Widget _page() => switch (_i) {
        0 => const _Dashboard(),
        1 => const _Members(),
        2 => const _Qualifications(),
        3 => const _Courses(),
        4 => const _Competitions(),
        _ => const _NoticesAdmin(),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final appBar = AppBar(
      title: Text(wide ? 'WINREF 관리자 · ${_menu[_i].$2}' : _menu[_i].$2),
      actions: commonActions(context, widget.profile),
    );
    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() => _i = i),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final m in _menu) NavigationRailDestination(icon: Icon(m.$1), label: Text(m.$2)),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: _page()),
            ),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        backgroundColor: Brand.ivory,
        child: ListView(children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Brand.navy),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text('WINREF 관리자', style: TextStyle(color: Brand.ivory, fontSize: 20, letterSpacing: 2)),
            ),
          ),
          for (var k = 0; k < _menu.length; k++)
            ListTile(
              tileColor: Colors.transparent,
              leading: Icon(_menu[k].$1),
              title: Text(_menu[k].$2),
              selected: k == _i,
              onTap: () {
                setState(() => _i = k);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
      body: _page(),
    );
  }
}

// ---------- 대시보드 (기본 통계) ----------

class _Dashboard extends StatefulWidget {
  const _Dashboard();
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<dynamic> _f = db.rpc('admin_stats');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error, onRetry: () => setState(() => _f = db.rpc('admin_stats')));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final s = snap.data as Map<String, dynamic>;
        final roles = (s['members_by_role'] as Map).cast<String, dynamic>();
        final total = roles.values.fold<int>(0, (a, b) => a + (b as num).toInt());
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = db.rpc('admin_stats')),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Kpi('전체 회원', '$total'),
              _Kpi('심판·교육신청자', '${roles['referee'] ?? 0}'),
              _Kpi('대회관계자', '${roles['organizer'] ?? 0}'),
              _Kpi('신규 회원 (30일)', '${s['new_members_30d']}'),
              _Kpi('등록 대회', '${s['competitions']}'),
              _Kpi('모집 중 공고', '${s['open_recruitments']}'),
              _Kpi('활동완료 누적', '${s['completed_activities']}'),
              _Kpi('자격 만료 예정 (90일)', '${s['expiring_90d']}', alert: (s['expiring_90d'] as num) > 0),
            ]),
            const SizedBox(height: 24),
            _section(context, '교육과정별 신청인원', [
              for (final c in s['course_applicants'] as List) _bar(c['title'], c['applicants'] as int, null),
            ]),
            _section(context, '대회별 지원·선발 인원', [
              for (final c in s['competition_applications'] as List)
                _bar(c['name'], c['applied'] as int, c['selected'] as int),
            ]),
          ]),
        );
      },
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Text('데이터 없음', style: TextStyle(color: Brand.muted)) else ...rows,
          ]),
        ),
      );

  Widget _bar(String name, int value, int? selected) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
          Text(selected == null ? '$value명' : '지원 $value · 선발 $selected',
              style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.navy)),
        ]),
      );
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final bool alert;
  const _Kpi(this.label, this.value, {this.alert = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: alert ? Brand.warn : Brand.navy, width: 3),
          top: const BorderSide(color: Color(0xFFDCE5F0)),
          right: const BorderSide(color: Color(0xFFDCE5F0)),
          bottom: const BorderSide(color: Color(0xFFDCE5F0)),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Brand.muted, fontSize: 13)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Brand.navy, fontSize: 26, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ---------- 회원 관리 / 대회관계자 기관 승인 ----------

class _Members extends StatefulWidget {
  const _Members();
  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  String? _role; // null = 전체
  String _q = '';
  final _key = GlobalKey<AsyncListState>();
  List<Map<String, dynamic>> _shown = [];

  Future<List<Map<String, dynamic>>> _load() async {
    var q = db.from('profiles').select();
    if (_role != null) q = q.eq('role', _role!);
    final rows = await q.order('created_at', ascending: false);
    final k = _q.trim().toLowerCase();
    _shown = k.isEmpty
        ? rows
        : rows
            .where((p) => '${p['name']} ${p['phone'] ?? ''} ${p['organization'] ?? ''} ${p['region'] ?? ''}'
                .toLowerCase()
                .contains(k))
            .toList();
    return _shown;
  }

  Future<void> _export() => exportCsv(
        context,
        '회원목록',
        ['이름', '유형', '소속기관', '기관승인', '연락처', '지역', '종목', '가입일'],
        [
          for (final p in _shown)
            [
              p['name'],
              switch (p['role']) { 'admin' => '관리자', 'organizer' => '대회관계자', _ => '심판·교육신청자' },
              p['organization'],
              p['role'] == 'organizer' ? label(p['org_status']) : '',
              phoneCell(p['phone']),
              p['region'],
              p['sport'],
              fmtDate(p['created_at']),
            ],
        ],
      );

  Future<void> _setOrg(BuildContext c, Map<String, dynamic> p, String status) async {
    await run(c, () => db.from('profiles').update({'org_status': status}).eq('id', p['id']),
        done: '${p['name']}: ${label(status)}');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                hintText: '이름·연락처·소속·지역 검색',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
              onChanged: (v) {
                _q = v;
                _key.currentState?.reload();
              },
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _export,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('엑셀 내보내기'),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: SegmentedButton<String?>(
          segments: const [
            ButtonSegment(value: null, label: Text('전체')),
            ButtonSegment(value: 'referee', label: Text('심판')),
            ButtonSegment(value: 'organizer', label: Text('대회관계자')),
            ButtonSegment(value: 'admin', label: Text('관리자')),
          ],
          selected: {_role},
          onSelectionChanged: (s) {
            setState(() => _role = s.first);
            _key.currentState?.reload();
          },
        ),
      ),
      Expanded(
        child: AsyncList(
          key: _key,
          load: _load,
          empty: '회원이 없습니다.',
          item: (c, p, _) {
            final org = p['role'] == 'organizer';
            return ListTile(
              title: Text('${p['name']}  ${org ? '· ${p['organization'] ?? ''}' : ''}'),
              subtitle: Text('${p['phone'] ?? '-'} · 가입 ${fmtDate(p['created_at'])}'),
              trailing: !org
                  ? Text(p['role'] == 'admin' ? '관리자' : '심판·교육')
                  : p['org_status'] == 'pending'
                      ? Wrap(spacing: 4, children: [
                          OutlinedButton(onPressed: () => _setOrg(c, p, 'rejected'), child: const Text('거절')),
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                            onPressed: () => _setOrg(c, p, 'approved'),
                            child: const Text('승인'),
                          ),
                        ])
                      : StatusChip(label(p['org_status']), p['org_status'] ?? 'pending'),
              leading: Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 40),
              onTap: p['role'] != 'referee'
                  ? null
                  : () => showModalBottomSheet(
                        context: c,
                        isScrollControlled: true,
                        builder: (_) => DraggableScrollableSheet(
                          expand: false,
                          initialChildSize: 0.85,
                          builder: (_, sc) => SingleChildScrollView(
                            controller: sc,
                            padding: const EdgeInsets.all(20),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Row(children: [
                                Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 56),
                                const SizedBox(width: 14),
                                Text(p['name'], style: Theme.of(c).textTheme.titleLarge),
                              ]),
                              const SizedBox(height: 20),
                              CareerView(profile: p, showContact: true),
                            ]),
                          ),
                        ),
                      ),
              onLongPress: org && p['org_status'] != 'pending'
                  ? () => _setOrg(c, p, p['org_status'] == 'approved' ? 'rejected' : 'approved')
                  : null,
            );
          },
        ),
      ),
    ]);
  }
}

// ---------- 심판 자격정보 확인·승인 ----------

class _Qualifications extends StatelessWidget {
  const _Qualifications();
  @override
  Widget build(BuildContext context) {
    return AsyncList(
      load: () => db
          .from('qualifications')
          .select('*, profiles(name)')
          .order('status', ascending: true) // pending 이 먼저 (enum 정의 순서)
          .order('created_at', ascending: false),
      empty: '등록된 자격정보가 없습니다.',
      item: (c, q, reload) => ListTile(
        title: Text('${q['profiles']['name']} · ${q['name']} ${q['grade'] ?? ''}'),
        subtitle: Text('${qualPeriod(q).isEmpty ? '' : '${qualPeriod(q)} · '}'
            '보수교육 ${q['refresher_done'] == true ? '이수' : '미이수'}'
            '${q['file_path'] != null ? ' · 사본 첨부' : ''}'),
        trailing: StatusChip(label(q['status']), q['status']),
        onTap: () async {
          final v = await showModalBottomSheet<Map<String, dynamic>>(
            context: c,
            builder: (s) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (q['file_path'] != null)
                  ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: const Text('자격증 사본 보기'),
                    onTap: () => openFile(s, q['file_path']),
                  )
                else
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('첨부된 사본 없음'),
                    enabled: false,
                  ),
                ListTile(title: const Text('승인'), onTap: () => Navigator.pop(s, {'status': 'approved'})),
                ListTile(title: const Text('반려'), onTap: () => Navigator.pop(s, {'status': 'rejected'})),
                ListTile(
                  title: Text(q['refresher_done'] == true ? '보수교육 미이수로 변경' : '보수교육 이수 처리'),
                  onTap: () => Navigator.pop(s, {'refresher_done': q['refresher_done'] != true}),
                ),
              ]),
            ),
          );
          if (v == null || !c.mounted) return;
          await run(c, () => db.from('qualifications').update(v).eq('id', q['id']), done: '저장했습니다.');
          reload();
        },
      ),
    );
  }
}

// ---------- 교육과정 등록·수정 / 신청자 관리 ----------

class _Courses extends StatefulWidget {
  const _Courses();
  @override
  State<_Courses> createState() => _CoursesState();
}

class _CoursesState extends State<_Courses> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final v = await showForm(context, c == null ? '교육과정 등록' : '교육과정 수정', [
      Field('title', '과정명', required: true, initial: c?['title']),
      Field('description', '내용', type: FieldType.multiline, initial: c?['description']),
      Field('location', '장소', initial: c?['location']),
      Field('starts_at', '시작', type: FieldType.datetime, initial: c?['starts_at']),
      Field('ends_at', '종료', type: FieldType.datetime, initial: c?['ends_at']),
      Field('apply_deadline', '신청 마감', type: FieldType.datetime, initial: c?['apply_deadline']),
      Field('capacity', '정원', type: FieldType.number, initial: c?['capacity']?.toString()),
    ]);
    if (v == null || !mounted) return;
    final refresher = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('보수교육 과정입니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('아니오')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('예')),
        ],
      ),
    );
    if (!mounted) return;
    final data = {...v, 'is_refresher': refresher ?? false};
    await run(context, () async {
      if (c == null) {
        await db.from('courses').insert(data);
      } else {
        await db.from('courses').update(data).eq('id', c['id']);
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
        load: () async {
          final courses = await db.from('courses').select().order('starts_at', ascending: false);
          final seats = await db.rpc('course_seats') as List;
          final taken = {for (final r in seats) r['course_id']: (r['taken'] as num).toInt()};
          return [for (final c in courses) {...c, '_taken': taken[c['id']] ?? 0}];
        },
        empty: '교육과정이 없습니다.',
        item: (c, course, _) => ListTile(
          title: Text(course['title']),
          subtitle: Text('${fmtDateTime(course['starts_at'])} · 마감 ${fmtDateTime(course['apply_deadline'])}\n'
              '신청 ${course['_taken']}${course['capacity'] != null ? ' / 정원 ${course['capacity']}' : ''}명'),
          isThreeLine: true,
          trailing: Wrap(children: [
            IconButton(tooltip: '수정', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(course)),
            IconButton(
              tooltip: '신청자',
              icon: const Icon(Icons.groups_outlined),
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => _CourseApplicants(course: course))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CourseApplicants extends StatelessWidget {
  final Map<String, dynamic> course;
  const _CourseApplicants({required this.course});

  Future<List<Map<String, dynamic>>> _load() => db
      .from('course_applications')
      .select('*, profiles(name, phone)')
      .eq('course_id', course['id'])
      .order('created_at');
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${course['title']} 신청자'), actions: [
        IconButton(
          tooltip: '엑셀 내보내기',
          icon: const Icon(Icons.file_download_outlined),
          onPressed: () async {
            final rows = await _load();
            if (!context.mounted) return;
            await exportCsv(context, '교육신청자_${course['id']}', ['이름', '연락처', '상태', '신청일'], [
              for (final a in rows)
                [a['profiles']['name'], phoneCell(a['profiles']['phone']), label(a['status']), fmtDateTime(a['created_at'])],
            ]);
          },
        ),
      ]),
      body: AsyncList(
        load: _load,
        empty: '신청자가 없습니다.',
        item: (c, a, reload) => ListTile(
          title: Text(a['profiles']['name']),
          subtitle: Text('${a['profiles']['phone'] ?? '-'} · 신청 ${fmtDateTime(a['created_at'])}'),
          trailing: a['status'] == 'applied'
              ? FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: () async {
                    await run(c, () => db.from('course_applications').update({'status': 'confirmed'}).eq('id', a['id']),
                        done: '확정했습니다.');
                    reload();
                  },
                  child: const Text('확정'),
                )
              : StatusChip(label(a['status']), a['status']),
        ),
      ),
    );
  }
}

// ---------- 대회·모집공고·지원/선발/활동완료 현황 ----------

class _Competitions extends StatefulWidget {
  const _Competitions();
  @override
  State<_Competitions> createState() => _CompetitionsState();
}

class _CompetitionsState extends State<_Competitions> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _create() async {
    final v = await editCompetitionForm(context);
    if (v == null || !mounted) return;
    await run(context, () => db.from('competitions').insert({...v, 'organizer_id': uid}), done: '대회를 등록했습니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-comp',
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('대회 등록'),
      ),
      body: _list(),
    );
  }

  Widget _list() {
    return AsyncList(
      key: _key,
      load: () => db.from('competitions').select('*, profiles(name, organization)').order('starts_on', ascending: false),
      empty: '등록된 대회가 없습니다.',
      item: (c, comp, reload) => ListTile(
        title: Text(comp['name']),
        subtitle: Text('${fmtDate(comp['starts_on'])} · ${comp['venue'] ?? '-'} · '
            '${comp['profiles']?['organization'] ?? comp['profiles']?['name'] ?? ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CompetitionManage(competition: comp)))
            .then((_) => reload()),
      ),
    );
  }
}

// ---------- 공지사항 / 알림 발송 ----------

class _NoticesAdmin extends StatefulWidget {
  const _NoticesAdmin();
  @override
  State<_NoticesAdmin> createState() => _NoticesAdminState();
}

class _NoticesAdminState extends State<_NoticesAdmin> {
  final _key = GlobalKey<AsyncListState>();

  Future<void> _notice() async {
    final v = await showForm(context, '공지 등록', const [
      Field('title', '제목', required: true),
      Field('body', '내용', type: FieldType.multiline),
      Field('file_path', '첨부 (PDF/이미지)', type: FieldType.file),
    ], fileFolder: 'notices');
    if (v == null || !mounted) return;
    final ok = await run(context, () => db.from('notices').insert(v), done: '공지를 등록했습니다.');
    _key.currentState?.reload();
    if (!ok || !mounted) return;
    final push = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('전체 회원에게 알림을 보낼까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('아니오')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('보내기')),
        ],
      ),
    );
    if (push == true && mounted) await _broadcast(v['title'], v['body'], null);
  }

  Future<void> _broadcast(String title, String? body, String? role) async {
    await run(context, () async {
      final n = await db.rpc('admin_broadcast', params: {'p_title': title, 'p_body': body, 'p_role': role});
      if (mounted) toast(context, '$n명에게 알림을 보냈습니다.');
    });
  }

  Future<void> _sendNotification() async {
    final v = await showForm(context, '알림 발송', const [
      Field('title', '제목', required: true),
      Field('body', '내용', type: FieldType.multiline),
    ]);
    if (v == null || !mounted) return;
    final role = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(title: const Text('받는 사람'), children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(d, 'all'), child: const Text('전체 회원')),
        SimpleDialogOption(onPressed: () => Navigator.pop(d, 'referee'), child: const Text('심판·교육신청자')),
        SimpleDialogOption(onPressed: () => Navigator.pop(d, 'organizer'), child: const Text('대회관계자')),
      ]),
    );
    if (role == null || !mounted) return;
    await _broadcast(v['title'], v['body'], role == 'all' ? null : role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        FloatingActionButton.extended(
          heroTag: 'noti',
          onPressed: _sendNotification,
          icon: const Icon(Icons.send_outlined),
          label: const Text('알림 발송'),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'notice',
          onPressed: _notice,
          icon: const Icon(Icons.add),
          label: const Text('공지 등록'),
        ),
      ]),
      body: AsyncList(
        key: _key,
        load: () => db.from('notices').select().order('created_at', ascending: false),
        empty: '공지사항이 없습니다.',
        item: (c, n, reload) => ListTile(
          title: Text(n['title']),
          subtitle: Text(fmtDateTime(n['created_at'])),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              await run(c, () => db.from('notices').delete().eq('id', n['id']), done: '삭제했습니다.');
              reload();
            },
          ),
        ),
      ),
    );
  }
}
