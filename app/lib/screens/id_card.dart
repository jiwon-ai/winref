import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../common.dart';
import '../theme.dart';

/// 디지털 심판증: 대회 현장에서 휴대폰으로 보여주는 등록 정보 카드
class RefereeCardScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const RefereeCardScreen({super.key, required this.profile});
  @override
  State<RefereeCardScreen> createState() => _RefereeCardScreenState();
}

class _RefereeCardScreenState extends State<RefereeCardScreen> {
  String? _verifyUrl; // 스캔하면 진위 확인 페이지가 열리는 QR 주소

  late final Future<(List, int)> _f = () async {
    final id = widget.profile['id'];
    final quals = await db.from('qualifications').select().eq('user_id', id).eq('status', 'approved').order('acquired_on');
    final done = await db.from('activity_history').select('competition_id').eq('user_id', id);
    if ((quals as List).isNotEmpty) {
      try {
        final c = Map<String, dynamic>.from(await db.rpc('card_certificate') as Map);
        _verifyUrl = '${appUrl}verify.html?code=${c['code']}';
      } catch (_) {
        // QR 은 부가 기능: 발급에 실패해도 심판증은 보여준다
      }
    }
    return (quals, (done as List).length);
  }();

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    return Scaffold(
      backgroundColor: const Color(0xFF0F2547),
      appBar: AppBar(
        title: const Text('디지털 심판증'),
        backgroundColor: const Color(0xFF0F2547),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(fontFamily: 'Pretendard', color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
        shape: const Border(),
      ),
      body: FutureBuilder<(List, int)>(
        future: _f,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error, onRetry: () => setState(() {}));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Colors.white));
          final (quals, done) = snap.data!;
          if (quals.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('관리자가 승인한 자격이 있어야 디지털 심판증이 발급됩니다.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 15)),
              ),
            );
          }
          final today = DateTime.now();
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(children: [
                  _Card(profile: p, quals: quals, done: done, verifyUrl: _verifyUrl),
                  const SizedBox(height: 16),
                  Text('확인 시각 ${DateFormat('yyyy.MM.dd HH:mm').format(today)}',
                      style: const TextStyle(color: Color(0xFF9DB4D6), fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('WINREF 알파인 스키 심판 인재은행에 등록된 정보이며, 자격은 관리자 확인을 거친 항목만 표시됩니다.\nQR 을 스캔하면 진위 확인 페이지에서 같은 내용을 확인할 수 있습니다.',
                      textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9DB4D6), fontSize: 12)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Map<String, dynamic> profile;
  final List quals;
  final int done;
  final String? verifyUrl;
  const _Card({required this.profile, required this.quals, required this.done, this.verifyUrl});

  /// 가장 높은 승인 자격 등급 → 띠 색 (1급 금색, 2급 은색, 3급 동색, 그 외 흰색)
  (String, Color) get _grade {
    var best = 9;
    for (final q in quals) {
      final m = RegExp(r'^([1-3])급').firstMatch((q['grade'] ?? '').toString());
      if (m != null && int.parse(m.group(1)!) < best) best = int.parse(m.group(1)!);
    }
    return switch (best) {
      1 => ('1급 심판', const Color(0xFFE8B93B)),
      2 => ('2급 심판', const Color(0xFFC5CED8)),
      3 => ('3급 심판', const Color(0xFFCB8E5E)),
      _ => ('등록 심판', Colors.white),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final memberNo = 'WR-${p['id'].toString().replaceAll('-', '').substring(0, 8).toUpperCase()}';
    const sub = TextStyle(color: Color(0xFFD6E8FF), fontSize: 13);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E4F96), Brand.navy, Brand.gold],
        ),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: Stack(children: [
        // 배경 눈꽃 워터마크
        Positioned(
          right: -40,
          bottom: -40,
          child: Opacity(opacity: 0.10, child: Image.asset('assets/brand/snowflake_white.png', width: 240)),
        ),
        // 자격 등급 띠 (실물 신분증의 색 띠처럼 카드 왼쪽 가장자리)
        Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 8, color: _grade.$2)),
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 22, 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Image.asset('assets/brand/snowflake_white.png', width: 26, height: 26),
              const SizedBox(width: 8),
              // 좁은 화면·큰 글씨에서도 오른쪽 배지가 잘리지 않게 줄여서 표시
              const Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('WINREF ACADEMY',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('ALPINE OFFICIAL',
                    maxLines: 1, style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1.2)),
              ),
            ]),
            const SizedBox(height: 22),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Avatar(path: p['avatar_path'], name: p['name'] ?? '', size: 78),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text([p['region'], p['sport']].where((e) => (e ?? '').toString().isNotEmpty).join(' · '),
                      style: sub),
                  const SizedBox(height: 6),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _grade.$2, borderRadius: BorderRadius.circular(6)),
                      child: Text(_grade.$1,
                          style: const TextStyle(color: Color(0xFF14233D), fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('활동 완료 $done회',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Container(height: 1, color: Colors.white24),
            const SizedBox(height: 14),
            const Text('보유 자격', style: TextStyle(color: Color(0xFFD6E8FF), fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 8),
            if (quals.isEmpty)
              const Text('관리자 확인을 마친 자격이 없습니다.', style: TextStyle(color: Colors.white70))
            else
              for (final q in quals.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.verified, color: Colors.white, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${q['name']}${q['grade'] != null ? ' ${q['grade']}' : ''}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                        Text([
                          if (q['cert_no'] != null) 'No. ${q['cert_no']}',
                          if (q['expires_on'] != null) '~${fmtDate(q['expires_on'])}',
                        ].join('  ·  '), style: sub),
                      ]),
                    ),
                  ]),
                ),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('회원번호', style: sub.copyWith(fontSize: 11)),
                  Text(memberNo,
                      style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()], letterSpacing: 1)),
                ]),
              ),
              if (verifyUrl != null)
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: QrImageView(data: verifyUrl!, size: 76, padding: EdgeInsets.zero, semanticsLabel: '진위 확인 QR'),
                )
              else
                Text('알파인 스키 심판 인재은행', style: sub),
            ]),
          ]),
        ),
      ]),
    );
  }
}
