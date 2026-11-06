import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';

/// 대회관계자 홈: 내 대회 목록 → 대회별 모집공고·지원자·브리핑 관리
class OrganizerHome extends StatefulWidget {
  final Map<String, dynamic> profile;
  const OrganizerHome({super.key, required this.profile});
  @override
  State<OrganizerHome> createState() => _OrganizerHomeState();
}

class _OrganizerHomeState extends State<OrganizerHome> {
  final _key = GlobalKey<AsyncListState>();
  late Map<String, dynamic> _profile = widget.profile;
  bool get _approved => _profile['org_status'] == 'approved';

  Future<void> _refreshProfile() async {
    final p = await db.from('profiles').select().eq('id', uid).single();
    if (mounted) setState(() => _profile = p);
  }

  Future<void> _create() async {
    final v = await showForm(context, '대회 등록', const [
      Field('name', '대회명', required: true),
      Field('starts_on', '시작일', type: FieldType.date, required: true),
      Field('ends_on', '종료일', type: FieldType.date),
      Field('venue', '장소'),
      Field('host_org', '주최·주관기관'),
      Field('poster_path', '포스터 (이미지/PDF)', type: FieldType.file),
    ], fileFolder: 'posters');
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
        Expanded(
          child: AsyncList(
            key: _key,
            load: () => db.from('competitions').select().eq('organizer_id', uid).order('starts_on', ascending: false),
            empty: '등록한 대회가 없습니다.',
            item: (c, comp, reload) => ListTile(
              title: Text(comp['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${fmtDate(comp['starts_on'])} · ${comp['venue'] ?? '-'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => CompetitionManage(competition: comp)))
                  .then((_) => reload()),
            ),
          ),
        ),
      ]),
    );
  }
}

/// 대회 하나의 관리 화면 (관리자도 같은 화면을 사용)
class CompetitionManage extends StatelessWidget {
  final Map<String, dynamic> competition;
  const CompetitionManage({super.key, required this.competition});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
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

class _ApplicantsManage extends StatelessWidget {
  final int cid;
  const _ApplicantsManage({required this.cid});

  @override
  Widget build(BuildContext context) {
    return AsyncList(
      load: () => db
          .from('applications')
          .select('*, profiles(id, name, phone), recruitments!inner(position, competition_id)')
          .eq('recruitments.competition_id', cid)
          .neq('status', 'cancelled')
          .order('created_at'),
      empty: '지원자가 없습니다.',
      item: (c, a, reload) {
        final p = a['profiles'] as Map<String, dynamic>;
        final done = a['completed_at'] != null;
        return ListTile(
          title: Text('${p['name']} · ${a['recruitments']['position']}'),
          subtitle: Text(a['status'] == 'selected'
              ? '참석 ${label(a['attendance'])}${done ? ' · 활동완료' : ''}'
              : '지원 ${fmtDate(a['created_at'])}'),
          trailing: StatusChip(done ? '활동완료' : label(a['status']), done ? 'approved' : a['status']),
          onTap: () async {
            await showModalBottomSheet(context: c, builder: (_) => _ApplicantSheet(app: a));
            reload();
          },
        );
      },
    );
  }
}

class _ApplicantSheet extends StatelessWidget {
  final Map<String, dynamic> app;
  const _ApplicantSheet({required this.app});

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
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(p['name'], style: Theme.of(context).textTheme.titleLarge),
          Text(p['phone'] ?? '', style: const TextStyle(color: Brand.muted)),
          const SizedBox(height: 12),
          const Text('자격정보', style: TextStyle(fontWeight: FontWeight.w600)),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: db.from('qualifications').select().eq('user_id', p['id']),
            builder: (c, s) {
              if (!s.hasData) return const LinearProgressIndicator();
              if (s.data!.isEmpty) return const Text('등록된 자격 없음', style: TextStyle(color: Brand.muted));
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final q in s.data!)
                  Text('· ${q['name']} ${q['grade'] ?? ''} (만료 ${fmtDate(q['expires_on'])}, ${label(q['status'])})'),
              ]);
            },
          ),
          const Divider(height: 28),
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
