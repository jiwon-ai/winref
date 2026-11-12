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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => fullWidth.value = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) => fullWidth.value = false);
    super.dispose();
  }

  int _i = 0;
  String? _memberRole; // 대시보드에서 회원 유형을 골라 들어온 경우
  static const _menu = <(IconData, String)>[
    (Icons.insights_outlined, '대시보드'),
    (Icons.people_outline, '회원'),
    (Icons.badge_outlined, '자격 승인'),
    (Icons.school_outlined, '교육'),
    (Icons.flag_outlined, '대회'),
    (Icons.campaign_outlined, '공지·알림'),
  ];

  Widget _page() => switch (_i) {
        0 => _Dashboard(
            onGo: (i) => setState(() => _i = i),
            onMembers: (role) => setState(() {
              _memberRole = role;
              _i = 1;
            }),
          ),
        1 => _Members(key: ValueKey(_memberRole), initialRole: _memberRole),
        2 => const _Qualifications(),
        3 => const _Courses(),
        4 => const _Competitions(),
        _ => const _NoticesAdmin(),
      };

  @override
  Widget build(BuildContext context) => BackGuard(
        atHome: _i == 0,
        onHome: () => setState(() {
          _i = 0;
          _memberRole = null;
        }),
        child: _scaffold(context),
      );

  Widget _scaffold(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final appBar = AppBar(
      title: BrandTitle(wide ? 'WINREF 관리자 · ${_menu[_i].$2}' : _menu[_i].$2),
      actions: commonActions(context, widget.profile),
    );
    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() {
              _i = i;
              _memberRole = null;
            }),
            labelType: NavigationRailLabelType.all,
            minWidth: 88,
            groupAlignment: -0.9,
            destinations: [
              for (final m in _menu) NavigationRailDestination(icon: Icon(m.$1), label: Text(m.$2)),
            ],
          ),
          const VerticalDivider(width: 1),
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
                setState(() {
                  _i = k;
                  _memberRole = null;
                });
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
  final ValueChanged<int> onGo; // 처리할 일 → 해당 메뉴로 이동
  final ValueChanged<String?> onMembers; // 회원 카드 → 회원 메뉴(유형 필터)
  const _Dashboard({required this.onGo, required this.onMembers});
  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late Future<dynamic> _f = db.rpc('admin_stats');
  void _reload() => setState(() => _f = db.rpc('admin_stats'));
  int _n(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error, onRetry: _reload);
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final s = snap.data as Map<String, dynamic>;
        final roles = (s['members_by_role'] as Map).cast<String, dynamic>();
        final total = roles.values.fold<int>(0, (a, b) => a + (b as num).toInt());
        final todos = [
          ( Icons.badge_outlined, '자격 승인 대기', _n(s['pending_quals']), 2),
          ( Icons.apartment_outlined, '기관 승인 대기', _n(s['pending_orgs']), 1),
          ( Icons.event_outlined, '14일 내 대회', _n(s['upcoming_14d']), 4),
          ( Icons.school_outlined, '7일 내 교육 마감', _n(s['courses_closing_7d']), 3),
        ];
        final waiting = _n(s['pending_quals']) + _n(s['pending_orgs']);
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(waiting == 0 ? '승인 대기 중인 요청이 없습니다.' : '처리할 요청이 $waiting건 있습니다.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: waiting == 0 ? Brand.muted : Brand.ink)),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final t in todos) _Todo(icon: t.$1, label: t.$2, count: t.$3, urgent: t.$4 <= 2, onTap: () => widget.onGo(t.$4)),
            ]),
            const SizedBox(height: 24),
            Text('운영 현황', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 12, runSpacing: 12, children: [
              _Kpi('전체 회원', '$total', icon: Icons.groups_outlined, onTap: () => widget.onMembers(null)),
              _Kpi('심판·교육신청자', '${roles['referee'] ?? 0}',
                  icon: Icons.person_outline, onTap: () => widget.onMembers('referee')),
              _Kpi('대회관계자', '${roles['organizer'] ?? 0}',
                  icon: Icons.apartment_outlined, onTap: () => widget.onMembers('organizer')),
              _Kpi('신규 회원 (30일)', '${s['new_members_30d']}',
                  icon: Icons.person_add_alt_outlined, onTap: () => _detail(context, _newMembers)),
              _Kpi('등록 대회', '${s['competitions']}', icon: Icons.emoji_events_outlined, onTap: () => widget.onGo(4)),
              _Kpi('모집 중 공고', '${s['open_recruitments']}',
                  icon: Icons.campaign_outlined, onTap: () => _detail(context, _openRecruitments)),
              _Kpi('활동완료 누적', '${s['completed_activities']}',
                  icon: Icons.task_alt, onTap: () => _detail(context, _completed)),
              _Kpi('자격 만료 예정 (90일)', '${s['expiring_90d']}',
                  icon: Icons.hourglass_bottom,
                  alert: _n(s['expiring_90d']) > 0,
                  onTap: () => _detail(context, _expiring)),
            ]),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, c) {
              final cards = [
                _section(context, '월별 신규 가입 (최근 6개월)', [_MonthlyChart(s['monthly_signups'] as List? ?? const [])]),
                _section(context, '교육과정 신청 현황', [
                  for (final c in s['course_applicants'] as List)
                    _progress(c['title'], _n(c['applicants']), c['capacity'] == null ? null : _n(c['capacity']), '명'),
                ]),
                _section(context, '대회별 선발 현황', [
                  for (final c in s['competition_applications'] as List)
                    _progress('${c['name']}', _n(c['selected']), _n(c['headcount']) == 0 ? null : _n(c['headcount']), '명 선발',
                        extra: '지원 ${_n(c['applied'])}'),
                ]),
              ];
              if (c.maxWidth < 760) return Column(children: cards);
              return Column(children: [
                cards[0],
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: cards[1]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[2]),
                ]),
              ]);
            }),
          ]),
        );
      },
    );
  }

  // ---- 운영 현황 카드 → 상세 목록 ----
  Future<void> _detail(BuildContext context, Future<(String, List<(String, String, String)>)> Function() load) =>
      showDetail(
        context,
        initial: 0.75,
        builder: (_, sc) => FutureBuilder<(String, List<(String, String, String)>)>(
            future: load(),
            builder: (c, snap) {
              if (snap.hasError) return ErrorView(error: snap.error, onRetry: () => Navigator.pop(c));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final (title, rows) = snap.data!;
              return ListView(controller: sc, shrinkWrap: true, padding: const EdgeInsets.fromLTRB(8, 16, 8, 48), children: [
                ListTile(
                  title: Text(title, style: Theme.of(c).textTheme.titleLarge),
                  trailing: Text('${rows.length}건', style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700)),
                ),
                const Divider(),
                if (rows.isEmpty) const EmptyView('해당 내역이 없습니다.'),
                for (final r in rows)
                  ListTile(
                    title: Text(r.$1),
                    subtitle: r.$2.isEmpty ? null : Text(r.$2),
                    trailing: Text(r.$3, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ),
              ]);
            },
          ),
      );

  Future<(String, List<(String, String, String)>)> _newMembers() async {
    final since = DateTime.now().subtract(const Duration(days: 30)).toUtc().toIso8601String();
    final rows = await db.from('profiles').select().gte('created_at', since).order('created_at', ascending: false);
    const roles = {'admin': '관리자', 'organizer': '대회관계자', 'referee': '심판·교육신청자'};
    return (
      '신규 회원 (최근 30일)',
      [for (final p in rows) ('${p['name']}', [roles[p['role']], p['email']].whereType<String>().join(' · '), fmtDate(p['created_at']))]
    );
  }

  Future<(String, List<(String, String, String)>)> _openRecruitments() async {
    final rows = await db
        .from('recruitments')
        .select('*, competitions(name, starts_on, venue)')
        .eq('is_open', true)
        .order('deadline', ascending: true, nullsFirst: false);
    final now = DateTime.now();
    final open = rows.where((r) => DateTime.tryParse(r['deadline'] ?? '')?.isAfter(now) ?? true);
    return (
      '모집 중 공고',
      [
        for (final r in open)
          (
            '${r['competitions']?['name'] ?? ''} · ${r['position']}',
            '${r['headcount']}명 · ${r['competitions']?['venue'] ?? ''} · 대회 ${fmtDate(r['competitions']?['starts_on'])}',
            r['deadline'] == null ? '상시' : '마감 ${fmtDateTime(r['deadline'])}',
          )
      ]
    );
  }

  Future<(String, List<(String, String, String)>)> _completed() async {
    final rows = await db.from('activity_history').select().order('starts_on', ascending: false);
    final names = {
      for (final p in await db.from('profiles').select('id, name')) p['id']: p['name'],
    };
    return (
      '활동완료 누적',
      [
        for (final a in rows)
          ('${names[a['user_id']] ?? '탈퇴 회원'} · ${a['position'] ?? ''}', '${a['competition_name'] ?? ''}', fmtDate(a['starts_on']))
      ]
    );
  }

  Future<(String, List<(String, String, String)>)> _expiring() async {
    final today = DateTime.now();
    final until = today.add(const Duration(days: 90));
    final rows = await db
        .from('qualifications')
        .select('*, profiles(name, phone)')
        .eq('status', 'approved')
        .gte('expires_on', today.toIso8601String().substring(0, 10))
        .lte('expires_on', until.toIso8601String().substring(0, 10))
        .order('expires_on');
    return (
      '자격 만료 예정 (90일 이내)',
      [
        for (final q in rows)
          (
            '${q['profiles']?['name'] ?? ''} · ${q['name']} ${q['grade'] ?? ''}',
            '${q['cert_no'] != null ? 'No.${q['cert_no']} · ' : ''}${q['profiles']?['phone'] ?? ''}',
            '만료 ${fmtDate(q['expires_on'])}',
          )
      ]
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (rows.isEmpty) const Text('데이터 없음', style: TextStyle(color: Brand.muted)) else ...rows,
          ]),
        ),
      );

  /// 이름 + 진행 막대 (정원·모집인원 대비)
  Widget _progress(String name, int value, int? max, String unit, {String? extra}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
            Text('${extra != null ? '$extra · ' : ''}$value${max != null ? '/$max' : ''}$unit',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Brand.navy, fontSize: 13)),
          ]),
          if (max != null) ...[
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: max == 0 ? 0 : (value / max).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: Brand.ivoryDeep,
                  color: value >= max ? const Color(0xFF2E7D5B) : Brand.gold,
                ),
              ),
            ),
          ],
        ]),
      );
}

/// 처리할 일 카드 (누르면 해당 메뉴로)
class _Todo extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool urgent;
  final VoidCallback onTap;
  const _Todo({required this.icon, required this.label, required this.count, required this.urgent, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final hot = urgent && count > 0;
    final color = hot ? Brand.warn : Brand.navy;
    return Material(
      color: hot ? const Color(0xFFFFF4E8) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: hot ? const Color(0xFFF2C79B) : const Color(0xFFDCE5F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 200,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: Brand.ink))),
              Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 월별 막대그래프 (외부 라이브러리 없이)
class _MonthlyChart extends StatelessWidget {
  final List data;
  const _MonthlyChart(this.data);
  @override
  Widget build(BuildContext context) {
    final values = [for (final d in data) (d['n'] as num).toInt()];
    final top = values.fold<int>(1, (a, b) => b > a ? b : a);
    return Semantics(
      label: '월별 신규 가입 ${[for (final d in data) '${int.parse('${d['month']}'.substring(5))}월 ${d['n']}명'].join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 150,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < data.length; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${values[i]}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.navy)),
                  const SizedBox(height: 4),
                  Container(
                    height: 100 * values[i] / top + 2,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: i == data.length - 1 ? Brand.navy : Brand.gold.withValues(alpha: 0.55),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${int.parse('${data[i]['month']}'.substring(5))}월',
                      style: const TextStyle(fontSize: 12, color: Brand.muted)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool alert;
  final VoidCallback? onTap;
  const _Kpi(this.label, this.value, {required this.icon, this.alert = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final color = alert ? Brand.warn : Brand.navy;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFDCE5F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12.5), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w800)),
          ]),
        ),
        if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: Brand.muted),
      ]),
        ),
      ),
    );
  }
}

// ---------- 회원 관리 / 대회관계자 기관 승인 ----------

class _Members extends StatefulWidget {
  final String? initialRole;
  const _Members({super.key, this.initialRole});
  @override
  State<_Members> createState() => _MembersState();
}

class _MembersState extends State<_Members> {
  late String? _role = widget.initialRole; // null = 전체
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
            .where((p) => '${p['name']} ${p['email'] ?? ''} ${p['phone'] ?? ''} ${p['organization'] ?? ''} ${p['region'] ?? ''}'
                .toLowerCase()
                .contains(k))
            .toList();
    return _shown;
  }

  Future<void> _export() => exportCsv(
        context,
        '회원목록',
        ['이름', '이메일(아이디)', '유형', '소속기관', '기관승인', '연락처', '생년월일', '지역', '종목', '가입일'],
        [
          for (final p in _shown)
            [
              p['name'],
              p['email'],
              switch (p['role']) { 'admin' => '관리자', 'organizer' => '대회관계자', _ => '심판·교육신청자' },
              p['organization'],
              p['role'] == 'organizer' ? label(p['org_status']) : '',
              phoneCell(p['phone']),
              p['birth_date'],
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
                hintText: '이름·이메일·연락처·소속·지역 검색',
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
      // PC: 표 머리글
      if (MediaQuery.sizeOf(context).width >= 900)
        const Padding(
          padding: EdgeInsets.fromLTRB(32, 4, 32, 0),
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: 'Pretendard', color: Brand.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
            child: Row(children: [
              SizedBox(width: 230, child: Text('이름')),
              Expanded(child: Text('이메일(아이디)')),
              SizedBox(width: 140, child: Text('연락처')),
              SizedBox(width: 110, child: Text('유형')),
              SizedBox(width: 100, child: Text('가입일')),
              SizedBox(width: 150, child: Text('상태', textAlign: TextAlign.right)),
            ]),
          ),
        ),
      Expanded(
        child: AsyncList(
          key: _key,
          load: _load,
          empty: '회원이 없습니다.',
          item: (c, p, reload) {
            final org = p['role'] == 'organizer';
            Future<void> open() async {
              final changed = await showDetail<bool>(
                c,
                initial: p['role'] == 'referee' ? 0.9 : 0.7,
                builder: (_, sc) => _MemberSheet(member: p, controller: sc),
              );
              if (changed == true) reload();
            }

            final status = !org
                ? Text(p['role'] == 'admin' ? '관리자' : '심판·교육', style: const TextStyle(color: Brand.muted, fontSize: 13))
                : p['org_status'] == 'pending'
                    ? Wrap(spacing: 4, children: [
                        OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(56, 38)),
                            onPressed: () => _setOrg(c, p, 'rejected'),
                            child: const Text('거절')),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(56, 38)),
                          onPressed: () => _setOrg(c, p, 'approved'),
                          child: const Text('승인'),
                        ),
                      ])
                    : StatusChip(label(p['org_status']), p['org_status'] ?? 'pending');
            const roleName = {'admin': '관리자', 'organizer': '대회관계자', 'referee': '심판·교육신청자'};
            if (MediaQuery.sizeOf(c).width >= 900) {
              // PC: 표 형태 한 줄
              return InkWell(
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                      width: 230,
                      child: Row(children: [
                        Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 34),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                            if (org && p['organization'] != null)
                              Text(p['organization'], style: const TextStyle(color: Brand.muted, fontSize: 12), overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ]),
                    ),
                    Expanded(child: Text(p['email'] ?? '-', overflow: TextOverflow.ellipsis)),
                    SizedBox(width: 140, child: Text(p['phone'] ?? '-')),
                    SizedBox(width: 110, child: Text(roleName[p['role']] ?? '', style: const TextStyle(fontSize: 13))),
                    SizedBox(width: 100, child: Text(fmtDate(p['created_at']), style: const TextStyle(color: Brand.muted, fontSize: 13))),
                    SizedBox(width: 150, child: Align(alignment: Alignment.centerRight, child: status)),
                  ]),
                ),
              );
            }
            return ListTile(
              title: Text('${p['name']}  ${org ? '· ${p['organization'] ?? ''}' : ''}'),
              subtitle: Text('${p['email'] ?? '-'}\n${p['phone'] ?? '-'} · 가입 ${fmtDate(p['created_at'])}'),
              isThreeLine: true,
              trailing: status,
              leading: Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 40),
              onTap: open,
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

/// 회원 상세: 연락처·회원 유형 변경(관리자 지정 포함)·심판 경력
class _MemberSheet extends StatelessWidget {
  final Map<String, dynamic> member;
  final ScrollController controller;
  const _MemberSheet({required this.member, required this.controller});

  static const _roles = {'referee': '심판·교육신청자', 'organizer': '대회관계자', 'admin': '관리자'};

  Future<void> _setRole(BuildContext context, String role) async {
    final p = member;
    final ok = await confirm(context, '회원 유형 변경',
        '${p['name']}님을 \'${_roles[role]}\'(으)로 변경할까요?'
        '${role == 'admin' ? '\n관리자는 모든 회원 정보와 관리 기능에 접근할 수 있습니다.' : ''}',
        ok: '변경');
    if (!ok || !context.mounted) return;
    final done = await run(
      context,
      () => db.from('profiles').update({'role': role, 'org_status': role == 'organizer' ? 'approved' : null}).eq('id', p['id']),
      done: '${_roles[role]}(으)로 변경했습니다.',
    );
    if (done && context.mounted) Navigator.pop(context, true);
  }

  /// 관리자 탈퇴 처리: 파일 삭제 → 계정·개인 데이터 삭제
  Future<void> _delete(BuildContext context) async {
    final p = member;
    final ok = await confirm(context, '회원 탈퇴 처리',
        '${p['name']}(${p['email'] ?? '이메일 없음'}) 회원을 탈퇴 처리할까요?\n'
        '계정과 프로필·자격·교육 신청·대회 지원 기록이 모두 삭제되며 되돌릴 수 없습니다.',
        ok: '탈퇴 처리');
    if (!ok || !context.mounted) return;
    final done = await run(context, () async {
      for (final folder in ['avatars/${p['id']}', 'quals/${p['id']}']) {
        try {
          final files = await db.storage.from('files').list(path: folder);
          if (files.isNotEmpty) await db.storage.from('files').remove([for (final f in files) '$folder/${f.name}']);
        } catch (_) {}
      }
      await db.rpc('admin_delete_user', params: {'p_user': p['id']});
    }, done: '${p['name']} 회원을 탈퇴 처리했습니다.');
    if (done && context.mounted) Navigator.pop(context, true);
  }

  Widget _info(IconData icon, String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: Brand.muted),
          const SizedBox(width: 10),
          SizedBox(width: 112, child: Text(label, style: const TextStyle(color: Brand.muted))),
          Expanded(child: Text((value ?? '').isEmpty ? '-' : value!)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final p = member;
    final me = p['id'] == uid;
    return SingleChildScrollView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 48), // 맨 아래 여유
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] ?? '', style: Theme.of(context).textTheme.titleLarge),
              Text(_roles[p['role']] ?? '', style: const TextStyle(color: Brand.muted)),
            ]),
          ),
          if (me)
            TextButton.icon(
              onPressed: () async {
                if (await changeAvatar(context) && context.mounted) Navigator.pop(context, true);
              },
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('사진 변경'),
            ),
        ]),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(children: [
              _info(Icons.alternate_email, '이메일(아이디)', p['email']),
              _info(Icons.phone_outlined, '연락처', p['phone']),
              _info(Icons.cake_outlined, '생년월일', p['birth_date'] == null ? null : fmtDate(p['birth_date'])),
              _info(Icons.place_outlined, '활동 지역', p['region']),
              _info(Icons.flag_outlined, '전문 종목', p['sport']),
              if (p['role'] == 'organizer') ...[
                _info(Icons.apartment_outlined, '소속 기관', p['organization']),
                _info(Icons.verified_outlined, '기관 승인', label(p['org_status'])),
              ],
              _info(Icons.event_outlined, '가입일', fmtDate(p['created_at'])),
              _info(Icons.notes_outlined, '소개', p['bio']),
            ]),
          ),
        ),
        const SizedBox(height: 20),
        const Text('회원 유형', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [for (final e in _roles.entries) ButtonSegment(value: e.key, label: Text(e.value))],
          selected: {p['role'] as String},
          showSelectedIcon: false,
          onSelectionChanged: me ? null : (v) => _setRole(context, v.first),
        ),
        if (me)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('본인 계정의 유형은 바꿀 수 없습니다.', style: TextStyle(color: Brand.muted, fontSize: 12)),
          ),
        if (!me && p['role'] != 'admin') ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
              side: const BorderSide(color: Color(0xFFE6A3A3)),
              minimumSize: const Size.fromHeight(46),
            ),
            onPressed: () => _delete(context),
            icon: const Icon(Icons.person_remove_outlined),
            label: const Text('회원 탈퇴 처리'),
          ),
        ],
        if (p['role'] == 'referee') ...[
          const SizedBox(height: 24),
          CareerView(profile: p, showContact: false),
        ],
      ]),
    );
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
        subtitle: Text('${q['cert_no'] != null ? 'No.${q['cert_no']} · ' : ''}${qualPeriod(q).isEmpty ? '' : '${qualPeriod(q)} · '}'
            '보수교육 ${q['refresher_done'] == true ? '이수' : '미이수'}'
            '${q['file_path'] != null ? ' · 사본 첨부' : ''}'),
        trailing: StatusChip(label(q['status']), q['status']),
        onTap: () async {
          final v = await showModalBottomSheet<Map<String, dynamic>>(
            useSafeArea: true, // 상태바·하단바에 가리지 않게
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
                ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('승인'),
                    onTap: () => Navigator.pop(s, {'status': 'approved'})),
                ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('반려'),
                    onTap: () => Navigator.pop(s, {'status': 'rejected'})),
                ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(q['refresher_done'] == true ? '보수교육 미이수로 변경' : '보수교육 이수 처리'),
                  onTap: () => Navigator.pop(s, {'refresher_done': q['refresher_done'] != true}),
                ),
                ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('정보 수정'),
                    onTap: () => Navigator.pop(s, {'_edit': true})),
                ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('삭제'),
                    onTap: () => Navigator.pop(s, {'_delete': true})),
              ]),
            ),
          );
          if (v == null || !c.mounted) return;
          if (v['_delete'] == true) {
            if (!await confirm(c, '자격 삭제', '${q['profiles']['name']}님의 ${q['name']} 자격을 삭제할까요?')) return;
            if (!c.mounted) return;
            await run(c, () => db.from('qualifications').delete().eq('id', q['id']), done: '삭제했습니다.');
          } else if (v['_edit'] == true) {
            final e = await showForm(c, '자격 정보 수정', qualFields(q), fileFolder: 'quals/${q['user_id']}');
            if (e == null || !c.mounted) return;
            await run(c, () => db.from('qualifications').update(e).eq('id', q['id']), done: '수정했습니다.');
          } else {
            await run(c, () => db.from('qualifications').update(v).eq('id', q['id']), done: '저장했습니다.');
          }
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
