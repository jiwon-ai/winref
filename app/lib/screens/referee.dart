import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';
import 'browse.dart';
import 'profile.dart';

/// 심판·교육신청자 홈: 홈 / 대회 / 교육 / 내 활동 / 자격
class RefereeHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RefereeHome({super.key, required this.profile});
  @override
  State<RefereeHome> createState() => _RefereeHomeState();
}

class _RefereeHomeState extends State<RefereeHome> {
  int _tab = 0;
  static const _titles = ['WINREF', '대회 모집', '교육', '내 활동', '자격정보'];

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab]), actions: commonActions(context, widget.profile)),
      body: IndexedStack(index: _tab, children: [
        _DashboardTab(profile: widget.profile, goTab: _go, active: _tab == 0),
        const _RecruitmentsTab(),
        const _CoursesTab(),
        const _MyActivityTab(),
        const _QualificationsTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.sports_outlined), label: '대회'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: '교육'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: '내 활동'),
          NavigationDestination(icon: Icon(Icons.badge_outlined), label: '자격'),
        ],
      ),
    );
  }
}

// ---------- 홈 대시보드 ----------

/// 오늘 기준 D-day 문자열 (D-DAY, D-3, D+1)
String dday(String? date) {
  final d = DateTime.tryParse(date ?? '');
  if (d == null) return '';
  final now = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  if (diff == 0) return 'D-DAY';
  return diff > 0 ? 'D-$diff' : 'D+${-diff}';
}

class _DashboardTab extends StatefulWidget {
  final Map<String, dynamic> profile;
  final void Function(int) goTab;
  final bool active;
  const _DashboardTab({required this.profile, required this.goTab, required this.active});
  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  late Future<Map<String, dynamic>> _f = _load();

  @override
  void didUpdateWidget(_DashboardTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) setState(() => _f = _load()); // 홈으로 돌아올 때 새로고침
  }

  Future<Map<String, dynamic>> _load() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final soon = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    final r = await Future.wait<List<Map<String, dynamic>>>([
      db
          .from('applications')
          .select('id, status, attendance, completed_at, recruitments(position, competitions(id, name, starts_on, venue))')
          .eq('user_id', uid)
          .neq('status', 'cancelled'),
      db.from('qualifications').select().eq('user_id', uid).eq('status', 'approved'),
      db
          .from('recruitments')
          .select('*, competitions(*)')
          .eq('is_open', true)
          .gte('deadline', DateTime.now().toUtc().toIso8601String())
          .lte('deadline', soon)
          .order('deadline'),
      db.from('notices').select('id, title, body, file_path, created_at').order('created_at', ascending: false).limit(3),
    ]);
    final apps = r[0];
    final upcoming = apps
        .where((a) =>
            a['status'] == 'selected' &&
            a['completed_at'] == null &&
            ((a['recruitments']['competitions']['starts_on'] as String?) ?? '').compareTo(today) >= 0)
        .toList()
      ..sort((a, b) => (a['recruitments']['competitions']['starts_on'] as String)
          .compareTo(b['recruitments']['competitions']['starts_on'] as String));
    final appliedIds = {for (final a in apps) a['recruitments']['competitions']['id']};
    final expiring = r[1].where((q) {
      final e = DateTime.tryParse(q['expires_on'] ?? '');
      return e != null && e.difference(DateTime.now()).inDays <= 90;
    }).toList();
    final me = await db.from('profiles').select().eq('id', uid).single();
    return {
      'me': me,
      'pending': apps.where((a) => a['status'] == 'applied').length,
      'selected': upcoming.length,
      'done': apps.where((a) => a['completed_at'] != null).length,
      'upcoming': upcoming,
      'expiring': expiring,
      'closing': r[2].where((x) => !appliedIds.contains(x['competitions']['id'])).toList(),
      'notices': r[3],
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: TextButton(onPressed: () => setState(() => _f = _load()), child: const Text('불러오기 실패 (다시 시도)')),
          );
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final d = snap.data!;
        final upcoming = d['upcoming'] as List;
        final expiring = d['expiring'] as List;
        final closing = d['closing'] as List;
        final notices = d['notices'] as List;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView(padding: EdgeInsets.zero, children: [
            _header(d),
            if (expiring.isNotEmpty)
              _Section('자격 알림', [
                for (final q in expiring)
                  _CardTile(
                    accent: Brand.gold,
                    icon: Icons.warning_amber_rounded,
                    title: '${q['name']} 만료 ${dday(q['expires_on'])}',
                    subtitle: '유효기간 ${fmtDate(q['expires_on'])} · 보수교육 ${q['refresher_done'] == true ? '이수' : '필요'}',
                    onTap: () => widget.goTab(4),
                  ),
              ]),
            _Section('다가오는 일정', [
              if (upcoming.isEmpty)
                _CardTile(
                  icon: Icons.event_available_outlined,
                  title: '예정된 대회 일정이 없습니다',
                  subtitle: '모집 중인 대회를 확인해 보세요',
                  onTap: () => widget.goTab(1),
                )
              else
                for (final a in upcoming)
                  _CardTile(
                    badge: dday(a['recruitments']['competitions']['starts_on']),
                    title: a['recruitments']['competitions']['name'],
                    subtitle: '${fmtDate(a['recruitments']['competitions']['starts_on'])} · '
                        '${a['recruitments']['competitions']['venue'] ?? '-'} · ${a['recruitments']['position']}',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BriefingScreen(competition: a['recruitments']['competitions'])),
                    ),
                  ),
            ]),
            if (closing.isNotEmpty)
              _Section('마감 임박 모집', [
                for (final x in closing)
                  _CardTile(
                    icon: Icons.schedule,
                    title: x['competitions']['name'],
                    subtitle: '${x['position']} ${x['headcount']}명 · 마감 ${fmtDateTime(x['deadline'])}',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecruitmentDetail(recruitment: x)))
                        .then((_) => setState(() => _f = _load())),
                  ),
              ]),
            _Section('공지사항', [
              if (notices.isEmpty)
                const _CardTile(icon: Icons.campaign_outlined, title: '새 공지가 없습니다')
              else
                for (final n in notices)
                  _CardTile(
                    icon: Icons.campaign_outlined,
                    title: n['title'],
                    subtitle: fmtDate(n['created_at']),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen())),
                  ),
            ]),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  Widget _header(Map<String, dynamic> d) {
    Widget stat(String label, int n, int tab) => Expanded(
          child: InkWell(
            onTap: () => widget.goTab(tab),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(children: [
                Text('$n', style: const TextStyle(color: Brand.ivory, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(color: Color(0xFFB9C0D0), fontSize: 12)),
              ]),
            ),
          ),
        );
    return Container(
      color: Brand.navy,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()))
              .then((_) => setState(() => _f = _load())),
          child: Row(children: [
            Avatar(path: d['me']['avatar_path'], name: d['me']['name'] ?? '', size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['me']['name']} 님',
                    style: const TextStyle(color: Brand.ivory, fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                const Text('내 프로필·경력 보기', style: TextStyle(color: Color(0xFFB9C0D0), fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Brand.gold),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Brand.navyLight,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            stat('지원 중', d['pending'] as int, 3),
            stat('선발 일정', d['selected'] as int, 3),
            stat('활동 완료', d['done'] as int, 3),
          ]),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(title,
              style: const TextStyle(color: Brand.navy, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
        ...children,
      ]),
    );
  }
}

class _CardTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? badge;
  final IconData? icon;
  final Color accent;
  final VoidCallback? onTap;
  const _CardTile({required this.title, this.subtitle, this.badge, this.icon, this.accent = Brand.navy, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            if (badge != null)
              Container(
                width: 58,
                padding: const EdgeInsets.symmetric(vertical: 6),
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: Text(badge!, style: const TextStyle(color: Brand.gold, fontWeight: FontWeight.w700)),
              )
            else if (icon != null)
              Padding(padding: const EdgeInsets.only(right: 12), child: Icon(icon, color: accent)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: const TextStyle(color: Brand.muted, fontSize: 13)),
                ],
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: Brand.muted),
          ]),
        ),
      ),
    );
  }
}

// ---------- 대회 조회·지원 ----------

class _RecruitmentsTab extends StatefulWidget {
  const _RecruitmentsTab();
  @override
  State<_RecruitmentsTab> createState() => _RecruitmentsTabState();
}

class _RecruitmentsTabState extends State<_RecruitmentsTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  String _q = '';
  String? _position; // null = 전체
  String _period = 'all'; // all / week / month
  bool _calendar = false;
  DateTime? _day;

  Future<List<Map<String, dynamic>>> _load() => db
      .from('recruitments')
      .select('*, competitions(*)')
      .eq('is_open', true)
      .order('deadline', ascending: true, nullsFirst: false);

  void _reload() => setState(() => _f = _load());

  DateTime? _start(Map<String, dynamic> r) => DateTime.tryParse(r['competitions']['starts_on'] ?? '');

  /// 검색·포지션·기간 필터 (캘린더에서 날짜 선택 시 그 날짜만)
  List<Map<String, dynamic>> _apply(List<Map<String, dynamic>> rows, {bool byDay = true}) {
    final q = _q.trim().toLowerCase();
    final today = dateOnly(DateTime.now());
    final until = switch (_period) {
      'week' => today.add(const Duration(days: 7)),
      'month' => DateTime(today.year, today.month + 1, today.day),
      _ => null,
    };
    return rows.where((r) {
      final c = r['competitions'] as Map<String, dynamic>;
      if (q.isNotEmpty &&
          !'${c['name']} ${c['venue'] ?? ''} ${c['host_org'] ?? ''} ${r['position']}'.toLowerCase().contains(q)) {
        return false;
      }
      if (_position != null && r['position'] != _position) return false;
      final d = _start(r);
      if (until != null && (d == null || d.isBefore(today) || d.isAfter(until))) return false;
      if (byDay && _calendar && _day != null && (d == null || dateOnly(d) != _day)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: TextButton(onPressed: _reload, child: const Text('불러오기 실패 (다시 시도)')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final all = snap.data!;
        final positions = {for (final r in all) r['position'] as String}.toList()..sort();
        final rows = _apply(all);
        final counts = <DateTime, int>{};
        for (final r in _apply(all, byDay: false)) {
          final d = _start(r);
          if (d != null) counts[dateOnly(d)] = (counts[dateOnly(d)] ?? 0) + 1;
        }
        return Column(children: [
          SearchFilterBar(
            hint: '대회명·장소·주최 검색',
            onQuery: (v) => setState(() => _q = v),
            trailing: IconButton.filledTonal(
              tooltip: _calendar ? '목록 보기' : '캘린더 보기',
              onPressed: () => setState(() { _calendar = !_calendar; _day = null; }),
              icon: Icon(_calendar ? Icons.view_list : Icons.calendar_month),
            ),
            chips: [
              for (final p in const [('all', '전체 기간'), ('week', '7일 이내'), ('month', '한 달 이내')])
                FilterPill(p.$2, selected: _period == p.$1, onTap: () => setState(() => _period = p.$1)),
              const SizedBox(width: 8),
              FilterPill('모든 포지션', selected: _position == null, onTap: () => setState(() => _position = null)),
              for (final p in positions)
                FilterPill(p, selected: _position == p, onTap: () => setState(() => _position = _position == p ? null : p)),
            ],
          ),
          const Divider(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(children: [
                if (_calendar) ...[
                  MonthCalendar(counts: counts, selected: _day, onSelect: (d) => setState(() => _day = _day == d ? null : d)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(_day == null ? '날짜를 선택하면 그날 대회만 보입니다' : '${_day!.month}월 ${_day!.day}일 대회 ${rows.length}건',
                        style: const TextStyle(color: Brand.muted, fontSize: 13)),
                  ),
                ],
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('조건에 맞는 모집 대회가 없습니다.', style: TextStyle(color: Brand.muted))),
                  ),
                for (final r in rows) _recruitmentCard(context, r),
                const SizedBox(height: 16),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _recruitmentCard(BuildContext context, Map<String, dynamic> r) {
    final comp = r['competitions'] as Map<String, dynamic>;
    final badge = deadlineBadge(r['deadline']);
    final urgent = badge != null && (badge == '오늘 마감' || badge == '마감 D-1' || badge == '마감 D-2');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecruitmentDetail(recruitment: r)))
            .then((_) => _reload()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 52,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(color: Brand.ivory, borderRadius: BorderRadius.circular(4)),
              child: Column(children: [
                Text('${_start(r)?.month ?? '-'}월', style: const TextStyle(color: Brand.muted, fontSize: 11)),
                Text('${_start(r)?.day ?? '-'}',
                    style: const TextStyle(color: Brand.navy, fontSize: 20, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(comp['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text('${comp['venue'] ?? '-'} · ${r['position']} ${r['headcount']}명',
                    style: const TextStyle(color: Brand.muted, fontSize: 13)),
              ]),
            ),
            if (badge != null) StatusChip(badge, urgent ? 'selected' : 'pending'),
          ]),
        ),
      ),
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
    final q = _q.trim().toLowerCase();
    final now = DateTime.now();
    return [
      for (final c in courses)
        if (q.isEmpty || '${c['title']} ${c['location'] ?? ''} ${c['description'] ?? ''}'.toLowerCase().contains(q))
          if (switch (_filter) {
            'open' => DateTime.tryParse(c['apply_deadline'] ?? '')?.isAfter(now) ?? true,
            'refresher' => c['is_refresher'] == true,
            'mine' => ['applied', 'confirmed'].contains(byCourse[c['id']]?['status']),
            _ => true,
          })
            {...c, '_mine': byCourse[c['id']]},
    ];
  }

  String _q = '';
  String _filter = 'all';
  void _set(void Function() f) {
    setState(f);
    _key.currentState?.reload();
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
    return Column(children: [
      SearchFilterBar(
        hint: '교육과정·장소 검색',
        onQuery: (v) => _set(() => _q = v),
        chips: [
          for (final f in const [('all', '전체'), ('open', '신청 가능'), ('refresher', '보수교육'), ('mine', '내 신청')])
            FilterPill(f.$2, selected: _filter == f.$1, onTap: () => _set(() => _filter = f.$1)),
        ],
      ),
      const Divider(),
      Expanded(child: _list()),
    ]);
  }

  Widget _list() {
    return AsyncList(
      key: _key,
      load: _load,
      empty: '조건에 맞는 교육과정이 없습니다.',
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
