import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';
import 'browse.dart';
import 'profile.dart';
import '../calendar_link.dart';
import '../venue_map.dart';

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
        _RecruitmentsTab(active: _tab == 1),
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
                    accent: Brand.warn,
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
                        '${a['recruitments']['competitions']['venue'] ?? '-'} · ${a['recruitments']['position']}'
                        '${switch (a['attendance']) { 'attending' => ' · 참석 확정', 'absent' => ' · 불참', _ => ' · 참석 응답 필요' }}',
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
                Text(label, style: const TextStyle(color: Color(0xFFC9DCF5), fontSize: 12)),
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
                const Text('내 프로필·경력 보기', style: TextStyle(color: Color(0xFFC9DCF5), fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Brand.ice),
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
                child: Text(badge!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
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
  final bool active;
  const _RecruitmentsTab({this.active = false});
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
  String? _myRegion; // 프로필 활동 지역
  bool _regionOnly = false;

  @override
  void initState() {
    super.initState();
    _loadRegion();
  }

  @override
  void didUpdateWidget(_RecruitmentsTab old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _reload(); // 탭을 다시 열 때 최신 모집·내 지역 반영
      _loadRegion();
    }
  }

  Future<void> _loadRegion() async {
    try {
      final p = await db.from('profiles').select('region').eq('id', uid).single();
      final r = (p['region'] ?? '').toString().trim();
      if (mounted) setState(() => _myRegion = r.isEmpty ? null : r);
    } catch (_) {}
  }

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
      if (_regionOnly && _myRegion != null &&
          !'${c['venue'] ?? ''} ${c['address'] ?? ''} ${c['name']} ${c['host_org'] ?? ''}'.contains(_myRegion!)) {
        return false;
      }
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
              if (_myRegion != null)
                FilterPill('내 지역 ($_myRegion)', selected: _regionOnly, onTap: () => setState(() => _regionOnly = !_regionOnly)),
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
  List<String> _clash = []; // 기간이 겹치는, 이미 선발된 다른 대회 이름

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
    final comp = widget.recruitment['competitions'] as Map<String, dynamic>;
    final s = DateTime.tryParse(comp['starts_on'] ?? '');
    final e = DateTime.tryParse(comp['ends_on'] ?? '') ?? s;
    final selected = await db
        .from('applications')
        .select('recruitments(competitions(id, name, starts_on, ends_on))')
        .eq('user_id', uid)
        .eq('status', 'selected');
    final clash = <String>{};
    for (final a in selected) {
      final o = a['recruitments']['competitions'];
      final os = DateTime.tryParse(o['starts_on'] ?? '');
      final oe = DateTime.tryParse(o['ends_on'] ?? '') ?? os;
      if (o['id'] != comp['id'] && s != null && os != null && !os.isAfter(e!) && !oe!.isBefore(s)) clash.add(o['name']);
    }
    if (mounted) setState(() { _mine = rows.isEmpty ? null : rows.first; _loaded = true; _clash = clash.toList(); });
  }

  Future<void> _apply() async {
    if (_clash.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('일정이 겹칩니다'),
          content: Text('같은 기간에 이미 선발된 대회가 있습니다.\n${_clash.join(', ')}\n그래도 지원할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('지원하기')),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
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
        if (_clash.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFF2C08C)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.event_busy_outlined, color: Brand.warn, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('같은 날 선발된 대회가 있습니다: ${_clash.join(', ')}', style: const TextStyle(fontSize: 13))),
            ]),
          ),
        const SizedBox(height: 16),
        _row('일정', '${fmtDate(comp['starts_on'])}${comp['ends_on'] != null ? ' ~ ${fmtDate(comp['ends_on'])}' : ''}'),
        _row('장소', comp['venue'] ?? '-'),
        if ((comp['address'] ?? '').toString().isNotEmpty) _row('주소', comp['address']),
        const SizedBox(height: 8),
        VenueMap(venue: comp['venue'], address: comp['address']),
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
    final seats = await db.rpc('course_seats') as List;
    final taken = {for (final r in seats) r['course_id']: (r['taken'] as num).toInt()};
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
            {...c, '_mine': byCourse[c['id']], '_taken': taken[c['id']] ?? 0},
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
        final cap = (c['capacity'] as num?)?.toInt();
        final left = cap == null ? null : (cap - (c['_taken'] as int)).clamp(0, cap);
        final full = left == 0;
        final seatText = cap == null ? '' : (full ? ' · 정원 마감' : ' · 잔여 $left석');
        return ExpansionTile(
          title: Row(children: [
            Expanded(child: Text(c['title'], style: const TextStyle(fontWeight: FontWeight.w600))),
            if (c['is_refresher'] == true) const StatusChip('보수교육', 'pending'),
          ]),
          subtitle: Text('${fmtDateTime(c['starts_at'])} · ${c['location'] ?? '-'}$seatText'),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(c['description'] ?? ''),
            const SizedBox(height: 8),
            Text('신청 마감 ${fmtDateTime(c['apply_deadline'])} · 정원 ${cap ?? '-'}명 · 신청 ${c['_taken']}명',
                style: const TextStyle(color: Brand.muted)),
            const SizedBox(height: 12),
            if (status == 'applied' || status == 'confirmed')
              Row(children: [
                StatusChip(status == 'applied' ? '신청완료' : label(status), status!),
                const Spacer(),
                if (DateTime.tryParse(c['starts_at'] ?? '') != null)
                  TextButton.icon(
                    onPressed: () => addToCalendar(
                      title: '[교육] ${c['title']}',
                      start: DateTime.parse(c['starts_at']).toLocal(),
                      end: DateTime.tryParse(c['ends_at'] ?? '')?.toLocal(),
                      location: c['location'],
                    ),
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: const Text('캘린더'),
                  ),
                if (!closed) TextButton(onPressed: () => _cancel(c), child: const Text('신청 취소')),
              ])
            else if (closed)
              const Text('신청이 마감되었습니다.', style: TextStyle(color: Brand.muted))
            else if (full)
              const FilledButton(onPressed: null, child: Text('정원 마감'))
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
class BriefingScreen extends StatefulWidget {
  final Map<String, dynamic> competition;
  const BriefingScreen({super.key, required this.competition});
  @override
  State<BriefingScreen> createState() => _BriefingScreenState();
}

/// 선발된 대회: 참석 응답 · 캘린더 추가 · 브리핑 자료
class _BriefingScreenState extends State<BriefingScreen> {
  Map<String, dynamic>? _comp;
  List<Map<String, dynamic>> _mine = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cid = widget.competition['id'];
    final comp = await db.from('competitions').select().eq('id', cid).single();
    final mine = await db
        .from('applications')
        .select('id, status, attendance, completed_at, recruitments!inner(position, competition_id)')
        .eq('user_id', uid)
        .eq('recruitments.competition_id', cid)
        .eq('status', 'selected');
    if (mounted) setState(() { _comp = comp; _mine = mine; });
  }

  Future<void> _answer(Map<String, dynamic> a, String v) async {
    if (v == 'absent') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('불참으로 응답할까요?'),
          content: const Text('대회관계자에게 불참 알림이 전달됩니다.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('불참 응답')),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    final ok = await run(context, () => db.from('applications').update({'attendance': v}).eq('id', a['id']),
        done: v == 'attending' ? '참석을 확정했습니다.' : '불참으로 응답했습니다.');
    if (ok) _load();
  }

  Future<void> _calendar() async {
    final c = _comp ?? widget.competition;
    final start = DateTime.tryParse(c['starts_on'] ?? '');
    if (start == null) return;
    await addToCalendar(
      title: '[심판] ${c['name']}',
      start: start,
      end: DateTime.tryParse(c['ends_on'] ?? ''),
      allDay: true,
      location: [c['venue'], c['address']].where((e) => (e ?? '').toString().isNotEmpty).join(' '),
      details: _mine.isEmpty ? null : '포지션: ${_mine.first['recruitments']['position']}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _comp ?? widget.competition;
    return Scaffold(
      appBar: AppBar(title: const Text('브리핑 자료'), actions: [
        IconButton(tooltip: '캘린더에 추가', onPressed: _calendar, icon: const Icon(Icons.event_available_outlined)),
      ]),
      body: Column(children: [
        for (final a in _mine.where((a) => a['completed_at'] == null))
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${c['name']} · ${a['recruitments']['position']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                switch (a['attendance']) {
                  'attending' => '참석 확정했습니다. 일정이 바뀌면 불참으로 바꿔주세요.',
                  'absent' => '불참으로 응답했습니다.',
                  _ => '선발되었습니다. 참석 여부를 알려주세요.',
                },
                style: TextStyle(color: a['attendance'] == 'unknown' ? Brand.warn : Brand.muted, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: a['attendance'] == 'attending'
                      ? const FilledButton(onPressed: null, child: Text('참석 확정됨'))
                      : FilledButton(onPressed: () => _answer(a, 'attending'), child: const Text('참석 확정')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    onPressed: a['attendance'] == 'absent' ? null : () => _answer(a, 'absent'),
                    child: Text(a['attendance'] == 'absent' ? '불참 응답함' : '불참'),
                  ),
                ),
              ]),
            ]),
          ),
        if (_mine.isNotEmpty) const Divider(),
        Expanded(
          child: AsyncList(
            load: () => db.from('briefings').select().eq('competition_id', widget.competition['id']).order('created_at'),
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
        ),
      ]),
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
      Field('file_path', '자격증 사본 (사진/PDF) — 관리자 확인용', type: FieldType.file),
    ], fileFolder: 'quals/$uid');
    if (v == null || !mounted) return;
    await run(context, () => db.from('qualifications').insert({...v, 'user_id': uid}),
        done: '등록했습니다. 관리자 확인 후 승인됩니다.');
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(tooltip: '자격 등록', onPressed: _add, child: const Icon(Icons.add)),
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
                '${soon ? ' (보수교육 필요)' : ''}\n보수교육 ${q['refresher_done'] == true ? '이수' : '미이수'}'
                '${q['file_path'] != null ? ' · 사본 첨부됨' : ''}'),
            isThreeLine: true,
            trailing: StatusChip(label(q['status']), q['status']),
            onTap: q['file_path'] == null ? null : () => openFile(c, q['file_path']),
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
