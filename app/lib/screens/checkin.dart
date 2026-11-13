import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../common.dart';
import '../theme.dart';

/// QR 에 담는 문자열. 앞머리는 다른 QR 과 구분하기 위한 표시이고, 서버는 마지막 8자리 코드만 본다.
String checkinPayload(String code) => 'WINREF-CHECKIN:$code';

/// 화면 표시용: 1A2B3C4D → 1A2B-3C4D
String prettyCode(String code) => code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// 심판: 내 출석 QR (대회 당일 대회관계자에게 보여준다)
Future<void> showCheckinQr(BuildContext context,
    {required String code, required String competition, required String position, String? checkedInAt}) {
  return showModalBottomSheet(
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    builder: (s) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('출석 QR', style: Theme.of(s).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('$competition · $position', textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Brand.line),
            ),
            child: QrImageView(
              data: checkinPayload(code),
              size: 220,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
              semanticsLabel: '출석 QR 코드',
            ),
          ),
          const SizedBox(height: 16),
          const Text('출석 코드', style: TextStyle(color: Brand.muted, fontSize: 12)),
          const SizedBox(height: 2),
          SelectableText(prettyCode(code),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 3, color: Brand.ink)),
          const SizedBox(height: 14),
          if (checkedInAt != null)
            StatusChip('출석 완료 · ${fmtDateTime(checkedInAt)}', 'approved')
          else
            const Text('대회 현장에서 대회관계자에게 이 화면을 보여주세요.\nQR 을 읽을 수 없으면 출석 코드를 불러주면 됩니다.',
                textAlign: TextAlign.center, style: TextStyle(color: Brand.muted, fontSize: 13, height: 1.5)),
        ]),
      ),
    ),
  );
}

/// 대회관계자·관리자: 심판의 QR 을 스캔하거나 코드를 입력해 출석 처리
class CheckinScanScreen extends StatefulWidget {
  final String competition;
  const CheckinScanScreen({super.key, required this.competition});
  @override
  State<CheckinScanScreen> createState() => _CheckinScanScreenState();
}

class _CheckinScanScreenState extends State<CheckinScanScreen> {
  final _scanner = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  final _done = <Map<String, dynamic>>[]; // 이번에 출석 처리한 사람 (최근 순)
  String? _lastCode; // 같은 QR 을 계속 비추고 있을 때 반복 처리 방지
  DateTime _lastAt = DateTime(2000);
  bool _busy = false;
  ({bool ok, String text})? _result;

  @override
  void dispose() {
    _scanner.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _submit(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || _busy) return;
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt) < const Duration(seconds: 4)) return;
    _lastCode = code;
    _lastAt = now;
    setState(() => _busy = true);
    try {
      final r = Map<String, dynamic>.from(await db.rpc('check_in', params: {'p_code': code}) as Map);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _result = (
          ok: true,
          text: r['already'] == true
              ? '${r['name']} 님은 이미 출석 처리되었습니다. (${fmtDateTime(r['checked_in_at'])})'
              : '${r['name']} 님 출석 완료 · ${r['position']}'
        );
        if (r['already'] != true) _done.insert(0, r);
        _manual.clear();
      });
    } catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _result = (ok: false, text: friendlyError(e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('출석 체크')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 48), children: [
        Text(widget.competition, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 2),
        const Text('선발된 심판의 출석 QR 을 사각형 안에 비춰 주세요.', style: TextStyle(color: Brand.muted, fontSize: 13)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 280,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Color(0xFF0F2547)),
              MobileScanner(
                controller: _scanner,
                onDetect: (capture) {
                  final v = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
                  if (v != null) _submit(v);
                },
                // 카메라 권한이 없거나 카메라가 없는 기기: 영어 오류 대신 안내
                errorBuilder: (context, error) => const ColoredBox(
                  color: Color(0xFF0F2547),
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('카메라를 사용할 수 없습니다.\n카메라 권한을 허용하거나, 아래에 출석 코드를 입력해 주세요.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.white, height: 1.5)),
                    ),
                  ),
                ),
              ),
              // 조준 사각형
              Center(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
              if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (r != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: r.ok ? const Color(0xFFE8F6EE) : const Color(0xFFFDECEC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.ok ? const Color(0xFF9AD3B0) : const Color(0xFFF0A8A8)),
            ),
            child: Row(children: [
              Icon(r.ok ? Icons.check_circle : Icons.error_outline,
                  color: r.ok ? const Color(0xFF1E8E4E) : const Color(0xFFD32F2F)),
              const SizedBox(width: 10),
              Expanded(child: Text(r.text, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
        const SizedBox(height: 16),
        const Text('카메라를 쓸 수 없으면 심판 화면의 출석 코드를 입력하세요.', style: TextStyle(color: Brand.muted, fontSize: 13)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: TextField(
              controller: _manual,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z-]')),
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: const InputDecoration(labelText: '출석 코드', hintText: '예: 1A2B-3C4D'),
              onSubmitted: _submit,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 18)),
            onPressed: _busy ? null : () => _submit(_manual.text),
            child: const Text('출석 처리', maxLines: 1, softWrap: false),
          ),
        ]),
        if (_done.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionHeader('방금 출석 처리 ${_done.length}명', padding: EdgeInsets.zero),
          const SizedBox(height: 8),
          for (final d in _done)
            Card(
              child: ListTile(
                leading: Avatar(path: d['avatar_path'], name: d['name'] ?? '', size: 40),
                title: Text('${d['name']} · ${d['position']}'),
                subtitle: Text('출석 ${fmtDateTime(d['checked_in_at'])}'),
                trailing: const Icon(Icons.check_circle, color: Color(0xFF1E8E4E)),
              ),
            ),
        ],
      ]),
    );
  }
}
