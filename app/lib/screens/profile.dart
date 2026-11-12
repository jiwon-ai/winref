import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../career_pdf.dart';
import '../common.dart';
import '../theme.dart';
import 'id_card.dart';

/// 심판 경력 카드: 활동 통계 · 직무별 활동 · 보유 자격 · 최근 활동 · 소개
/// 본인 프로필 화면과 대회관계자의 지원자 상세에서 함께 쓴다.
class CareerView extends StatefulWidget {
  final Map<String, dynamic> profile;
  final bool showContact;
  const CareerView({super.key, required this.profile, this.showContact = false});
  @override
  State<CareerView> createState() => _CareerViewState();
}

class _CareerViewState extends State<CareerView> {
  late final Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _f = _load();
  Map<String, dynamic> get profile => widget.profile;
  bool get showContact => widget.showContact;

  Future<(Map<String, dynamic>, List<Map<String, dynamic>>)> _load() async {
    final s = await db.rpc('referee_summary', params: {'p_user': profile['id']});
    final q = await db.from('qualifications').select().eq('user_id', profile['id']).order('expires_on');
    return ((s as Map).cast<String, dynamic>(), q);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(Map<String, dynamic>, List<Map<String, dynamic>>)>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) return Text('경력을 불러오지 못했습니다. ${friendlyError(snap.error!)}', style: const TextStyle(color: Brand.muted));
        if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: LinearProgressIndicator());
        final (sum, quals) = snap.data!;
        final byPos = (sum['by_position'] as Map).cast<String, dynamic>();
        final maxPos = byPos.values.fold<int>(1, (m, v) { final n = (v as num).toInt(); return n > m ? n : m; });
        final recent = (sum['recent'] as List).cast<Map<String, dynamic>>();
        final applied = (sum['applied'] as num).toInt();
        final selected = (sum['selected'] as num).toInt();
        final absent = (sum['absent'] as num).toInt();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _Stat('활동 완료', '${sum['completed']}', '회'),
            _Stat('선발', '$selected', '회'),
            _Stat('선발률', applied == 0 ? '-' : '${(selected * 100 / applied).round()}', applied == 0 ? '' : '%'),
            _Stat('불참', '$absent', '회', warn: absent > 0),
          ]),
          if (showContact) ...[
            const SizedBox(height: 16),
            _Info(Icons.phone_outlined, profile['phone'] == null ? '-' : fmtPhone(profile['phone'])),
            if (profile['email'] != null) _Info(Icons.alternate_email, profile['email']),
          ],
          if ((profile['region'] ?? '').toString().isNotEmpty || (profile['sport'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            _Info(Icons.place_outlined, [profile['region'], profile['sport']].where((e) => (e ?? '').toString().isNotEmpty).join(' · ')),
          ],
          if ((profile['bio'] ?? '').toString().isNotEmpty) ...[
            const _Head('소개'),
            Text(profile['bio'], style: const TextStyle(height: 1.5)),
          ],
          const _Head('보유 자격'),
          if (quals.isEmpty)
            const Text('등록된 자격이 없습니다.', style: TextStyle(color: Brand.muted))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [for (final q in quals) _QualBadge(q)]),
          const _Head('직무별 활동'),
          if (byPos.isEmpty)
            const Text('완료된 활동이 없습니다.', style: TextStyle(color: Brand.muted))
          else
            for (final e in byPos.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  SizedBox(width: 64, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: (e.value as num) / maxPos,
                        minHeight: 8,
                        color: Brand.navy,
                        backgroundColor: Brand.ivoryDeep,
                      ),
                    ),
                  ),
                  SizedBox(width: 44, child: Text('${e.value}회', textAlign: TextAlign.right)),
                ]),
              ),
          const _Head('최근 활동'),
          if (recent.isEmpty)
            const Text('활동 이력이 없습니다.', style: TextStyle(color: Brand.muted))
          else
            for (final r in recent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.verified_outlined, size: 18, color: Brand.gold),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${r['name']}', overflow: TextOverflow.ellipsis)),
                  Text('${fmtDate(r['starts_on'])} · ${r['position']}', style: const TextStyle(color: Brand.muted, fontSize: 13)),
                ]),
              ),
        ]);
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value, unit;
  final bool warn;
  const _Stat(this.label, this.value, this.unit, {this.warn = false});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Text.rich(TextSpan(children: [
          TextSpan(
              text: value,
              style: TextStyle(color: warn ? const Color(0xFF9B2C2C) : Brand.navy, fontSize: 22, fontWeight: FontWeight.w700)),
          TextSpan(text: unit, style: const TextStyle(color: Brand.muted, fontSize: 12)),
        ])),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Brand.muted, fontSize: 12)),
      ]),
    );
  }
}

class _Head extends StatelessWidget {
  final String text;
  const _Head(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Container(width: 3, height: 14, color: Brand.gold),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Brand.navy, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Info extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Info(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: Brand.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ]);
}

class _QualBadge extends StatelessWidget {
  final Map<String, dynamic> q;
  const _QualBadge(this.q);
  @override
  Widget build(BuildContext context) {
    final approved = q['status'] == 'approved';
    final exp = DateTime.tryParse(q['expires_on'] ?? '');
    final expired = exp != null && exp.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: approved && !expired ? const Color(0xFFE3EFFC) : Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: approved && !expired ? Brand.gold : const Color(0xFFC3D0E0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(approved ? Icons.workspace_premium : Icons.hourglass_empty,
              size: 16, color: approved ? const Color(0xFF1F5FAF) : Brand.muted),
          const SizedBox(width: 4),
          Text('${q['name']}${q['grade'] != null ? ' ${q['grade']}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
        if (q['cert_no'] != null)
          Text('No. ${q['cert_no']}', style: const TextStyle(fontSize: 11, color: Brand.muted)),
        Text(
          expired ? '만료됨' : (approved ? '~${fmtDate(q['expires_on'])}' : label(q['status'])),
          style: TextStyle(fontSize: 11, color: expired ? const Color(0xFF9B2C2C) : Brand.muted),
        ),
      ]),
    );
  }
}

/// 본인 프로필 화면 (심판·교육신청자)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>> _f = _load();
  Future<Map<String, dynamic>> _load() => db.from('profiles').select().eq('id', uid).single();
  void _reload() => setState(() => _f = _load());

  /// 활동완료 내역과 승인된 자격으로 PDF 를 만들어 저장·인쇄 화면을 연다
  Future<void> _exportPdf(Map<String, dynamic> p) async {
    await run(context, () async {
      final history = await db.from('activity_history').select().eq('user_id', uid).order('starts_on', ascending: false);
      final quals = await db.from('qualifications').select().eq('user_id', uid).eq('status', 'approved').order('acquired_on');
      final regular = await PdfGoogleFonts.notoSansKRRegular();
      final bold = await PdfGoogleFonts.notoSansKRBold();
      final logo = (await rootBundle.load('assets/brand/snowflake_blue.png')).buffer.asUint8List();
      final bytes = await buildCareerPdf(profile: p, history: history, quals: quals, regular: regular, bold: bold, logoPng: logo);
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'WINREF_활동이력_${p['name']}.pdf');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 프로필')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final p = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(children: [
              Container(
                color: Brand.navy,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Row(children: [
                  Stack(children: [
                    Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 76),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: IconButton.filled(
                        tooltip: '사진 변경',
                        iconSize: 16,
                        style: IconButton.styleFrom(backgroundColor: Brand.gold, minimumSize: const Size(30, 30)),
                        onPressed: () async {
                          if (await changeAvatar(context)) _reload();
                        },
                        icon: const Icon(Icons.photo_camera, color: Colors.white),
                      ),
                    ),
                  ]),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] ?? '',
                          style: const TextStyle(color: Brand.ivory, fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        [p['region'], p['sport']].where((e) => (e ?? '').toString().isNotEmpty).join(' · ').ifEmpty('지역·종목을 등록하세요'),
                        style: const TextStyle(color: Color(0xFFC9DCF5)),
                      ),
                      if (db.auth.currentUser?.email != null)
                        Text(db.auth.currentUser!.email!,
                            style: const TextStyle(color: Color(0xFFC9DCF5), fontSize: 12.5)),
                    ]),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Brand.ivory,
                      side: const BorderSide(color: Brand.ice),
                      minimumSize: const Size(56, 36),
                    ),
                    onPressed: () async {
                      if (await editProfile(context, p)) _reload();
                    },
                    child: const Text('편집'),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => RefereeCardScreen(profile: p))),
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('디지털 심판증'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                      onPressed: () => _exportPdf(p),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('활동 이력 PDF'),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: CareerView(key: ValueKey(p.toString()), profile: p),
              ),
            ]),
          );
        },
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
