import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, FlutterError;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
import 'screens/app_info.dart';
import 'screens/profile.dart';
import 'screens/referee.dart' show RefresherCoursesScreen;
import 'theme.dart';

final db = Supabase.instance.client;

/// 인증 메일(가입 확인·비밀번호 재설정) 링크가 돌아올 앱 주소.
/// Supabase > Authentication > URL Configuration 의 Redirect URLs 에 등록돼 있어야 한다.
const appUrl = String.fromEnvironment('APP_URL', defaultValue: 'https://jiwon.fr/winref/');

/// 개인정보처리방침 전문 (웹에 게시된 privacy.html)
Future<void> openPrivacy() =>
    launchUrl(Uri.parse('${appUrl}privacy.html'), mode: LaunchMode.externalApplication);

/// 안드로이드 앱으로 돌아오는 소셜 로그인 콜백 (AndroidManifest intent-filter 와 같아야 함)
const mobileAuthCallback = 'kr.co.winref.app://login-callback';

/// Supabase 인증 오류를 사용자용 한국어로
const duplicatePhone = '이미 가입된 휴대폰 번호입니다. 처음 가입한 방법(이메일·카카오·구글)으로 로그인해 주세요.';

/// 다른 계정이 이미 쓰는 휴대폰 번호인가 (중복 가입 방지)
Future<bool> phoneInUse(String phone) async => (await db.rpc('phone_in_use', params: {'p_phone': phone})) == true;

/// 이 기기에만 저장하는 간단한 설정 (첫 실행 안내를 봤는지, 화면 모드). 준비에 실패하면 null → 기본값으로 동작.
SharedPreferences? prefs;

const alreadyRegistered = '이미 가입된 이메일입니다. 그 이메일로 로그인하거나, 카카오·구글로 가입하셨다면 해당 버튼으로 로그인해 주세요.';

String authMessage(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login credentials')) return '이메일 또는 비밀번호가 올바르지 않습니다.';
  if (m.contains('email not confirmed')) return '이메일 인증이 필요합니다. 받은 메일의 링크를 눌러주세요.';
  if (m.contains('already registered') || m.contains('already been registered')) return alreadyRegistered;
  // 이전과 같은 비밀번호 (서버 문구에 'password should be different' 가 들어 있어 '짧다'보다 먼저 확인)
  if (e.code == 'same_password' || (m.contains('different') && m.contains('password')) || (m.contains('same') && m.contains('password'))) {
    return '이전과 같은 비밀번호입니다. 다른 비밀번호를 입력해 주세요.';
  }
  if (e.code == 'weak_password' || m.contains('password should be') || m.contains('weak')) {
    return '비밀번호가 너무 짧거나 쉽습니다. 8자 이상, 영문과 숫자를 섞어 정해주세요.';
  }
  // 메일 서버(SMTP) 설정 오류 등으로 서버가 메일을 보내지 못함
  if (m.contains('sending') && m.contains('email')) return '메일을 보내지 못했습니다. 잠시 후 다시 시도하고, 계속되면 관리자에게 알려주세요.';
  if (m.contains('email rate limit')) return '메일 발송 한도를 넘었습니다. 1시간쯤 뒤에 다시 시도해 주세요.';
  if (m.contains('security purposes') || m.contains('seconds')) return '방금 메일을 보냈습니다. 1분 뒤에 다시 시도해 주세요.';
  if (m.contains('rate limit') || m.contains('too many')) return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
  if (m.contains('invalid email') || m.contains('unable to validate email')) return '이메일 형식이 올바르지 않습니다.';
  if (m.contains('expired') || (m.contains('invalid') && m.contains('token'))) return '링크가 만료되었습니다. 다시 요청해 주세요.';
  if (e is AuthRetryableFetchException || m.contains('fetch') || m.contains('socket')) {
    return '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
  }
  debugPrint('인증 오류: ${e.message}');
  return '로그인 처리 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// 로그아웃: 이전 사용자 화면의 안내 메시지를 지우고 세션 종료
/// 임시 비밀번호로 로그인함 → 새 비밀번호 설정 화면을 반드시 거치게
bool tempPasswordLogin = false;

/// true 면 PC 에서도 전체 폭(관리자 화면). 기본은 휴대폰 폭으로 가운데 표시.
final fullWidth = ValueNotifier<bool>(false);

Future<void> signOut() async {
  messengerKey.currentState?.clearSnackBars();
  // 같은 휴대폰으로 다른 사람이 로그인해도 이전 회원의 푸시가 오지 않게 기기 토큰 해제
  try {
    if (db.auth.currentUser != null) await db.from('profiles').update({'fcm_token': null}).eq('id', uid);
  } catch (_) {}
  await db.auth.signOut();
}
String get uid => db.auth.currentUser!.id;

String fmtDate(dynamic v) {
  if (v == null) return '-';
  final d = DateTime.tryParse(v.toString());
  return d == null ? '-' : DateFormat('yyyy.MM.dd').format(d.toLocal());
}

String fmtDateTime(dynamic v) {
  if (v == null) return '-';
  final d = DateTime.tryParse(v.toString());
  return d == null ? '-' : DateFormat('yyyy.MM.dd HH:mm').format(d.toLocal());
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar() // 이전 알림이 쌓이지 않게 교체
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2800)));
}

/// 사용자에게 보여줄 오류 문구. 서버·네트워크의 영문 원문을 그대로 노출하지 않는다.
String friendlyError(Object e) {
  if (e is String) return e; // 앱이 직접 던진 안내 문구
  final raw = e.toString();
  if (e is AuthException && e is! AuthRetryableFetchException) return authMessage(e);
  if (RegExp(r'SocketException|ClientException|Failed host lookup|Connection (refused|reset|closed)|Network is unreachable|TimeoutException|XMLHttpRequest', caseSensitive: false)
      .hasMatch(raw)) {
    return '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
  }
  if (e is PostgrestException) {
    switch (e.code) {
      case '23505':
        return '이미 등록된 내용입니다.';
      case '23503':
        return '연결된 정보가 있어 처리할 수 없습니다.';
      case '23514': // 서버의 값 검사 규칙 위반
        if (e.message.contains('competitions_date_order')) return '종료일은 시작일보다 빠를 수 없습니다.';
        if (e.message.contains('courses_date_order')) return '날짜를 확인해 주세요. 종료는 시작 이후, 신청 마감은 시작 전이어야 합니다.';
        if (e.message.contains('qualifications_date_order')) return '만료일은 취득일보다 빠를 수 없습니다.';
        return '입력값을 확인해 주세요.';
      case '42501':
        return '이 작업을 할 권한이 없습니다.';
      case 'P0001': // 서버 규칙(트리거)이 보낸 안내
        if (e.message == 'forbidden') return '이 작업을 할 권한이 없습니다.';
        if (e.message == 'not signed in') return '다시 로그인해 주세요.';
        return e.message;
    }
    if (e.message.contains('row-level security')) return '이 작업을 할 권한이 없습니다.';
  }
  if (e is StorageException) return '파일을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  debugPrint('처리되지 않은 오류: $raw');
  reportError(e, e is Error ? e.stackTrace : null); // 원인을 알 수 없는 오류는 관리자 화면(앱 오류 기록)으로 보낸다
  return '일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}

// ---------- 오류 수집 ----------

final _reported = <int>{};
final _networkError = RegExp(
    r'SocketException|ClientException|Failed host lookup|Connection (refused|reset|closed)|Network is unreachable|TimeoutException|XMLHttpRequest|Failed to fetch',
    caseSensitive: false);

/// 예상하지 못한 앱 오류를 서버에 남긴다 (관리자 › 처리 기록 › 앱 오류 기록).
/// 인터넷 끊김처럼 사용자 환경 문제는 보내지 않고, 같은 오류는 한 번만, 한 번 실행에 최대 10건.
void reportError(Object error, StackTrace? stack) {
  try {
    final msg = error.toString();
    if (_networkError.hasMatch(msg)) return;
    if (_reported.length >= 10 || !_reported.add(msg.hashCode)) return;
    db.rpc('log_error', params: {
      'p_message': msg,
      'p_stack': stack?.toString(),
      'p_build': const String.fromEnvironment('BUILD', defaultValue: 'dev'),
      'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
    }).then((_) {}, onError: (_) {});
  } catch (_) {
    // 오류 보고가 앱 동작을 방해하면 안 된다
  }
}

/// 앱 전체의 처리되지 않은 오류를 [reportError] 로 연결
void installErrorReporting() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    previous?.call(details);
    reportError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return false; // 기본 처리(콘솔 출력)는 그대로
  };
}

/// 불러오기 실패 화면: 안내 + 다시 시도
class ErrorView extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;
  const ErrorView({super.key, this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: Brand.muted),
            const SizedBox(height: 12),
            Text(error == null ? '불러오지 못했습니다.' : friendlyError(error!),
                textAlign: TextAlign.center, style: TextStyle(color: Brand.muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18), label: const Text('다시 시도')),
          ]),
        ),
      );
}

/// 빈 목록 안내
class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
        child: Column(children: [
          const AlpineEmptyArt(),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: Brand.muted, height: 1.5)),
        ]),
      );
}

/// 서버 호출을 실행하고 실패 시 메시지를 띄운다. 성공하면 true.
Future<bool> run(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (context.mounted && done != null) toast(context, done);
    return true;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
  return false;
}

// ---------- 파일 (포스터·브리핑·공지 첨부) ----------

/// 파일을 골라 storage 'files' 버킷에 올리고 경로를 돌려준다. 취소 시 null.
Future<String?> pickAndUpload(BuildContext context, String folder, {bool imagesOnly = false}) async {
  final f = await FilePicker.pickFile(
      type: FileType.custom, allowedExtensions: imagesOnly ? ['jpg', 'jpeg', 'png'] : ['pdf', 'jpg', 'jpeg', 'png']);
  if (f == null || !context.mounted) return null;
  final ext = (f.extension ?? 'bin').toLowerCase();
  final mime = switch (ext) { 'pdf' => 'application/pdf', 'png' => 'image/png', _ => 'image/jpeg' };
  final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
  String? out;
  await run(context, () async {
    final bytes = await f.xFile.readAsBytes();
    if (bytes.length > 20 * 1024 * 1024) throw '20MB 이하 파일만 올릴 수 있습니다.';
    await db.storage.from('files').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    out = path;
  });
  return out;
}

Future<void> openFile(BuildContext context, String path) async {
  await run(context, () async {
    final url = await db.storage.from('files').createSignedUrl(path, 3600);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  });
}

Widget fileButton(BuildContext context, String? path, {String label = '첨부자료 열기'}) {
  if (path == null || path.isEmpty) return const SizedBox.shrink();
  return TextButton.icon(
    onPressed: () => openFile(context, path),
    icon: const Icon(Icons.attach_file),
    label: Text(label),
  );
}

// ---------- 이름 입력 규칙 ----------

/// 이름: 한글만, 띄어쓰기 없이 2~10자 (영문·숫자·특수문자·이모지·공백 입력 자체를 막음).
/// 입력 중인 자음·모음(천지인 자판의 ㆍ·ᆢ 포함)은 허용해야 한글 조합이 끊기지 않는다.
final koreanNameInput = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[ㄱ-ㆎ가-힣ᄀ-ᇿ]')),
  LengthLimitingTextInputFormatter(10),
];

String? koreanNameError(String? v) {
  final s = v ?? '';
  if (s.isEmpty) return '필수 입력';
  if (!RegExp(r'^[가-힣]{2,10}$').hasMatch(s)) return '한글로만, 띄어쓰기 없이 2~10자로 입력해 주세요.';
  return null;
}

bool isKoreanName(String? v) => koreanNameError(v) == null;

/// 휴대폰 번호: 숫자만, 010 은 11자리 (011·016~019 는 10~11자리). 하이픈 없이 저장.
final phoneInput = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(11),
];
final _phoneRe = RegExp(r'^(010\d{8}|01[16789]\d{7,8})$');

String? phoneError(String? v) {
  final s = v ?? '';
  if (s.isEmpty) return '필수 입력';
  if (!_phoneRe.hasMatch(s)) return '휴대폰 번호를 정확히 입력해 주세요. (예: 01012345678)';
  return null;
}

/// 화면 표시용: 01012345678 → 010-1234-5678
String fmtPhone(Object? v) {
  final s = (v ?? '').toString();
  if (!_phoneRe.hasMatch(s)) return s;
  return s.length == 11 ? '${s.substring(0, 3)}-${s.substring(3, 7)}-${s.substring(7)}' : '${s.substring(0, 3)}-${s.substring(3, 6)}-${s.substring(6)}';
}

// ---------- 입력 폼 다이얼로그 ----------

enum FieldType { text, multiline, number, date, datetime, file }

class Field {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? initial;
  final String? helper; // 입력칸 아래 안내
  final List<String>? options; // 목록에서 고르기(직접 입력도 가능)
  final bool optionsOnly; // true 면 목록에서만 선택
  /// 날짜 자동 채움: [autoFrom] 날짜를 고르면 그 날짜 + [autoYears]년으로 채운다(직접 고치면 그 값 유지)
  final String? autoFrom;
  final int autoYears;
  final bool koreanName; // 이름 규칙(한글만·띄어쓰기 없음) 적용
  final bool phone; // 휴대폰 번호 규칙(숫자만·자리수) 적용
  /// 날짜 순서: 이 날짜는 [notBefore] 필드보다 빠를 수 없고, [notAfter] 필드보다 늦을 수 없다
  final String? notBefore;
  final String? notAfter;
  final bool notFuture; // 오늘 이후 날짜 불가 (생년월일·취득일)
  const Field(this.key, this.label,
      {this.type = FieldType.text,
      this.notBefore,
      this.notAfter,
      this.notFuture = false,
      this.koreanName = false,
      this.phone = false,
      this.required = false,
      this.initial,
      this.helper,
      this.autoFrom,
      this.autoYears = 0,
      this.options,
      this.optionsOnly = false});
}

/// 필드 목록으로 입력 화면을 띄우고, 저장 시 key→값(빈 값은 null) 맵을 돌려준다.
/// date 는 'yyyy-MM-dd', datetime 은 ISO8601(UTC), number 는 int, file 은 storage 경로.
Future<Map<String, dynamic>?> showForm(BuildContext context, String title, List<Field> fields,
    {String fileFolder = 'misc'}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(builder: (_) => _FormScreen(title, fields, fileFolder)),
  );
}

class _FormScreen extends StatefulWidget {
  final String title;
  final List<Field> fields;
  final String fileFolder;
  const _FormScreen(this.title, this.fields, this.fileFolder);
  @override
  State<_FormScreen> createState() => _FormScreenState();
}

class _FormScreenState extends State<_FormScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.initial ?? ''),
  };
  final Map<String, dynamic> _values = {};
  final Set<String> _manual = {}; // 사용자가 직접 고른 날짜(자동 채움 대상에서 제외)

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.initial != null && f.initial!.isNotEmpty) {
        _values[f.key] = f.initial;
        _manual.add(f.key);
        if (f.type == FieldType.date) _c[f.key]!.text = fmtDate(f.initial);
        if (f.type == FieldType.datetime) _c[f.key]!.text = fmtDateTime(f.initial);
        if (f.type == FieldType.file) _c[f.key]!.text = f.initial!.split('/').last;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(Field f) async {
    if (f.type == FieldType.file) {
      final p = await pickAndUpload(context, widget.fileFolder);
      if (p != null) setState(() { _values[f.key] = p; _c[f.key]!.text = p.split('/').last; });
      return;
    }
    final now = DateTime.now();
    // 달력에서 순서가 맞지 않는 날짜는 아예 고를 수 없게 범위를 제한
    final lo = _dateOf(f.notBefore);
    final hi = _dateOf(f.notAfter);
    final first = lo == null ? DateTime(1950) : DateTime(lo.year, lo.month, lo.day);
    var last = hi == null ? DateTime(now.year + 30) : DateTime(hi.year, hi.month, hi.day, 23, 59);
    if (f.notFuture) last = DateTime(now.year, now.month, now.day);
    if (last.isBefore(first)) last = first;
    var init = DateTime.tryParse(_values[f.key]?.toString() ?? '')?.toLocal() ?? (lo ?? now);
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: first, lastDate: last);
    if (d == null || !mounted) return;
    if (f.type == FieldType.date) {
      setState(() {
        _setDate(f.key, d);
        _manual.add(f.key);
        for (final g in widget.fields.where((g) => g.autoFrom == f.key && !_manual.contains(g.key))) {
          _setDate(g.key, DateTime(d.year + g.autoYears, d.month, d.day));
        }
      });
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { _values[f.key] = dt.toUtc().toIso8601String(); _c[f.key]!.text = fmtDateTime(dt.toIso8601String()); });
  }

  Future<void> _choose(Field f) async {
    final v = await showModalBottomSheet<String>(
      useSafeArea: true, // 상태바·하단바에 가리지 않게
      context: context,
      isScrollControlled: true,
      builder: (s) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(s).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: Text(f.label, style: const TextStyle(fontWeight: FontWeight.w700))),
            for (final o in f.options!)
              ListTile(
                title: Text(o),
                trailing: _c[f.key]!.text == o ? Icon(Icons.check, color: Brand.navy) : null,
                onTap: () => Navigator.pop(s, o),
              ),
          ]),
        ),
      ),
    );
    if (v != null) setState(() => _c[f.key]!.text = v);
  }

  DateTime? _dateOf(String? key) =>
      key == null ? null : DateTime.tryParse(_values[key]?.toString() ?? '')?.toLocal();

  String _label(String key) => widget.fields.firstWhere((g) => g.key == key).label;

  /// 날짜 순서·범위 검사 (달력 제한 외에 다른 날짜를 나중에 바꾼 경우까지 저장 시 다시 확인)
  String? _dateOrderError(Field f) {
    final v = _dateOf(f.key);
    if (v == null) return null;
    final lo = _dateOf(f.notBefore);
    if (lo != null && v.isBefore(lo)) return '${_label(f.notBefore!)}보다 빠를 수 없습니다.';
    final hi = _dateOf(f.notAfter);
    if (hi != null && v.isAfter(hi)) return '${_label(f.notAfter!)}보다 늦을 수 없습니다.';
    if (f.notFuture && v.isAfter(DateTime.now())) return '오늘 이후 날짜는 입력할 수 없습니다.';
    return null;
  }

  void _setDate(String key, DateTime d) {
    _values[key] = DateFormat('yyyy-MM-dd').format(d);
    _c[key]!.text = fmtDate(d.toIso8601String());
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final out = <String, dynamic>{};
    for (final f in widget.fields) {
      switch (f.type) {
        case FieldType.text:
        case FieldType.multiline:
          final v = _c[f.key]!.text.trim();
          out[f.key] = v.isEmpty ? null : v;
        case FieldType.number:
          out[f.key] = int.tryParse(_c[f.key]!.text.trim());
        default:
          out[f.key] = _values[f.key];
      }
    }
    Navigator.of(context).pop(out);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextFormField(
                  controller: _c[f.key],
                  readOnly: f.optionsOnly ||
                      f.type == FieldType.date ||
                      f.type == FieldType.datetime ||
                      f.type == FieldType.file,
                  onTap: f.optionsOnly
                      ? () => _choose(f)
                      : f.type == FieldType.date || f.type == FieldType.datetime || f.type == FieldType.file
                          ? () => _pick(f)
                          : null,
                  keyboardType: f.type == FieldType.number || f.phone ? TextInputType.number : null,
                  inputFormatters: f.koreanName ? koreanNameInput : f.phone ? phoneInput : null,
                  maxLines: f.type == FieldType.multiline ? 5 : 1,
                  decoration: InputDecoration(
                    labelText: f.required ? '${f.label} *' : f.label,
                    helperText: f.helper,
                    border: const OutlineInputBorder(),
                    suffixIcon: switch (f.type) {
                      FieldType.date || FieldType.datetime => const Icon(Icons.calendar_today),
                      FieldType.file => const Icon(Icons.upload_file),
                      _ when f.optionsOnly => const Icon(Icons.arrow_drop_down),
                      _ when f.options != null => IconButton(
                          tooltip: '${f.label} 목록에서 선택',
                          icon: const Icon(Icons.arrow_drop_down_circle_outlined),
                          onPressed: () => _choose(f),
                        ),
                      _ => null,
                    },
                  ),
                  validator: (v) {
                    if (f.type == FieldType.date || f.type == FieldType.datetime) {
                      if (f.required && (v == null || v.trim().isEmpty)) return '필수 입력';
                      return _dateOrderError(f);
                    }
                    if (f.koreanName) return koreanNameError(v);
                    if (f.phone) return phoneError(v);
                    if (f.required && (v == null || v.trim().isEmpty)) return '필수 입력';
                    if (f.type == FieldType.number && v != null && v.trim().isNotEmpty && int.tryParse(v.trim()) == null) {
                      return '숫자만 입력';
                    }
                    return null;
                  },
                ),
              ),
            FilledButton(onPressed: _save, child: const Text('저장')),
          ],
        ),
      ),
    );
  }
}

// ---------- 공통 화면 ----------

/// 서버 데이터를 불러와 목록으로 그리는 공통 위젯 (당겨서 새로고침).
class AsyncList extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(BuildContext, Map<String, dynamic>, VoidCallback reload) item;
  final String empty;
  const AsyncList({super.key, required this.load, required this.item, this.empty = '항목이 없습니다.'});
  @override
  State<AsyncList> createState() => AsyncListState();
}

class AsyncListState extends State<AsyncList> {
  late Future<List<Map<String, dynamic>>> _f = widget.load();
  void reload() => setState(() => _f = widget.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _f,
      builder: (context, snap) {
        if (snap.hasError) {
          return ErrorView(error: snap.error, onRetry: reload);
        }
        if (!snap.hasData) return const SkeletonList();
        final rows = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: rows.isEmpty
              ? ListView(children: [EmptyView(widget.empty)])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), // 맨 아래 항목이 + 버튼에 가리지 않게
                  itemCount: rows.length,
                  // 항목마다 흰 카드 (둥근 모서리·옅은 테두리)
                  itemBuilder: (c, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Brand.card,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Brand.line),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: widget.item(c, rows[i], reload),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공지사항')),
      body: AsyncList(
        load: () => db.from('notices').select().order('created_at', ascending: false),
        empty: '공지사항이 없습니다.',
        item: (c, n, _) => ExpansionTile(
          title: Text(n['title']),
          subtitle: Text(fmtDate(n['created_at'])),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          expandedAlignment: Alignment.centerLeft,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [Text(n['body'] ?? ''), fileButton(c, n['file_path'])],
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _key = GlobalKey<AsyncListState>();

  static const _icons = {
    'selection': Icons.how_to_reg_outlined,
    'briefing': Icons.description_outlined,
    'qualification': Icons.workspace_premium_outlined,
    'competition_d1': Icons.event_outlined,
    'course_deadline': Icons.school_outlined,
    'refresher': Icons.warning_amber_rounded,
    'new_applicant': Icons.person_add_alt_outlined,
    'org_request': Icons.domain_verification_outlined,
    'qual_request': Icons.fact_check_outlined,
    'attendance': Icons.how_to_reg_outlined,
  };

  Future<void> _readAll() async {
    await run(
      context,
      () => db
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('user_id', uid)
          .isFilter('read_at', null),
      done: '모두 읽음으로 표시했습니다.',
    );
    _key.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림'), actions: [
        TextButton(
          onPressed: _readAll,
          child: const Text('모두 읽음'),
        ),
      ]),
      body: AsyncList(
        key: _key,
        load: () => db.from('notifications').select().eq('user_id', uid).order('created_at', ascending: false).limit(100),
        empty: '알림이 없습니다.',
        item: (c, n, reload) {
          final unread = n['read_at'] == null;
          return ListTile(
            tileColor: unread ? Brand.soft(const Color(0xFFF1F7FF)) : Brand.card,
            leading: Icon(_icons[n['kind']] ?? Icons.campaign_outlined, color: unread ? Brand.gold : Brand.muted),
            title: Text(n['title'], style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text('${n['body'] ?? ''}\n${fmtDateTime(n['created_at'])}'
                '${n['kind'] == 'refresher' ? '\n눌러서 보수교육 신청하기 ›' : ''}'),
            isThreeLine: true,
            onTap: !unread && n['kind'] != 'refresher'
                ? null
                : () async {
                    if (unread) {
                      await db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', n['id']);
                    }
                    // 자격 만료 예정 알림 → 보수교육 목록으로 바로 이동
                    if (n['kind'] == 'refresher' && c.mounted) {
                      await Navigator.push(c, MaterialPageRoute(builder: (_) => const RefresherCoursesScreen()));
                    }
                    reload();
                  },
          );
        },
      ),
    );
  }
}

/// 비공개 저장소의 이미지 표시 (대회 포스터 썸네일 등). 이미지가 아니거나 불러오지 못하면 [fallback].
class StorageImage extends StatelessWidget {
  final String? path;
  final double width;
  final double height;
  final Widget fallback;
  final double radius;
  const StorageImage({super.key, required this.path, required this.width, required this.height, required this.fallback, this.radius = 10});

  static bool isImage(String? p) => p != null && RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(p);

  @override
  Widget build(BuildContext context) {
    if (!isImage(path)) return fallback;
    return FutureBuilder<String>(
      future: _signedUrls.putIfAbsent(path!, () => db.storage.from('files').createSignedUrl(path!, 60 * 60 * 24)),
      builder: (_, s) => !s.hasData
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Image.network(s.data!, width: width, height: height, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
            ),
    );
  }
}

/// 불러오는 동안 보여주는 회색 틀 (내용 모양의 자리 표시). 빙글빙글 도는 표시보다 화면이 덜 깜빡인다.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key});
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: Brand.soft(const Color(0xFFE3E8EF)), borderRadius: BorderRadius.circular(6)),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final n = box.hasBoundedHeight ? (box.maxHeight / 92).floor().clamp(2, 8) : 4;
      final col = Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < n; i++)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Brand.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Brand.line),
            ),
            child: Row(children: [
              _bar(44, 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  FractionallySizedBox(widthFactor: i.isEven ? 0.7 : 0.5, child: _bar(double.infinity, 14)),
                  const SizedBox(height: 10),
                  FractionallySizedBox(widthFactor: i.isEven ? 0.45 : 0.6, child: _bar(double.infinity, 11)),
                ]),
              ),
            ]),
          ),
      ]);
      return Semantics(
        label: '불러오는 중',
        child: ExcludeSemantics(
          child: FadeTransition(
            opacity: Tween(begin: 0.55, end: 1.0).animate(_c),
            child: box.hasBoundedHeight
                ? SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: col)
                : col,
          ),
        ),
      );
    });
  }
}

/// 앱바 알림 버튼: 읽지 않은 알림 수 배지
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _count();
  }

  Future<void> _count() async {
    try {
      final rows = await db.from('notifications').select('id').eq('user_id', uid).isFilter('read_at', null).limit(100);
      if (mounted) setState(() => _unread = rows.length);
    } catch (_) {
      // 배지는 부가 정보라 실패해도 화면을 막지 않는다
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _unread == 0 ? '알림' : '알림 읽지 않음 $_unread건',
      icon: Badge(
        isLabelVisible: _unread > 0,
        backgroundColor: Brand.gold,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        _count();
      },
    );
  }
}

/// 개인정보·프로필 관리
Future<bool> editProfile(BuildContext context, Map<String, dynamic> p) async {
  final referee = p['role'] == 'referee';
  final v = await showForm(context, '내 정보 수정', [
    Field('name', '이름', required: true, koreanName: true, helper: '한글만, 띄어쓰기 없이', initial: p['name']),
    Field('phone', '휴대폰', required: true, phone: true, helper: '숫자만 (예: 01012345678)', initial: p['phone']),
    Field('birth_date', '생년월일', type: FieldType.date, notFuture: true, initial: p['birth_date']),
    if (p['role'] == 'organizer') Field('organization', '소속 기관', initial: p['organization']),
    if (referee) ...[
      Field('region', '활동 지역 (예: 서울)', initial: p['region']),
      Field('sport', '전문 종목', initial: p['sport'], options: alpineDisciplines),
      Field('bio', '소개·주요 경력', type: FieldType.multiline, initial: p['bio']),
    ],
  ]);
  if (v == null || !context.mounted) return false;
  return run(context, () => db.from('profiles').update(v).eq('id', uid), done: '저장했습니다.');
}

// ---------- 프로필 사진 ----------

final _signedUrls = <String, Future<String>>{};

/// 비공개 저장소 이미지를 서명 URL 로 보여주는 원형 아바타 (사진 없으면 이름 첫 글자)
class Avatar extends StatelessWidget {
  final String? path;
  final String name;
  final double size;
  const Avatar({super.key, required this.path, required this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Brand.ivoryDeep, shape: BoxShape.circle, border: Border.all(color: Brand.gold, width: 1.5)),
      child: Text(name.isEmpty ? '?' : name.characters.first,
          style: TextStyle(color: Brand.navy, fontSize: size * 0.4, fontWeight: FontWeight.w700)),
    );
    if (path == null || path!.isEmpty) return initial;
    return FutureBuilder<String>(
      future: _signedUrls.putIfAbsent(path!, () => db.storage.from('files').createSignedUrl(path!, 60 * 60 * 24)),
      builder: (_, s) => !s.hasData
          ? initial
          : Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Brand.gold, width: 1.5)),
              child: ClipOval(
                child: Image.network(s.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => initial),
              ),
            ),
    );
  }
}

/// 프로필 사진 변경: avatars/<uid>/ 에 업로드 후 profiles.avatar_path 갱신
Future<bool> changeAvatar(BuildContext context) async {
  final path = await pickAndUpload(context, 'avatars/$uid', imagesOnly: true);
  if (path == null || !context.mounted) return false;
  return run(context, () => db.from('profiles').update({'avatar_path': path}).eq('id', uid), done: '프로필 사진을 변경했습니다.');
}

// ---------- CSV(엑셀) 내보내기 ----------

String _cell(Object? v) {
  var s = v?.toString() ?? '';
  if (RegExp(r'^[=+\-@]').hasMatch(s)) s = "'$s"; // 수식 주입 방지
  if (s.contains(RegExp(r'[",\n\r]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

/// 전화번호를 엑셀에서 문자로 유지 (앞자리 0 보존)
String phoneCell(Object? v) => v == null ? '' : '\t$v';

/// UTF-8 BOM 을 붙인 CSV 를 내려받는다 (엑셀에서 한글 깨짐 방지). 모바일은 클립보드 복사.
Future<void> exportCsv(BuildContext context, String fileBase, List<String> headers, List<List<Object?>> rows) async {
  final csv = StringBuffer('\uFEFF')..writeln(headers.map(_cell).join(','));
  for (final r in rows) {
    csv.writeln(r.map(_cell).join(','));
  }
  final name = '${fileBase}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';
  final saved = await saveFile(name, utf8.encode(csv.toString()), 'text/csv;charset=utf-8');
  if (!saved) await Clipboard.setData(ClipboardData(text: csv.toString()));
  if (context.mounted) {
    toast(context, saved ? '$name 파일을 내려받았습니다. (${rows.length}건)' : '${rows.length}건을 클립보드에 복사했습니다. 엑셀에 붙여넣으세요.');
  }
}

/// 회원 탈퇴: 계정과 개인 데이터 삭제 (되돌릴 수 없음)
Future<void> deleteAccount(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('회원 탈퇴'),
      content: const Text('계정과 자격정보·지원내역·활동이력이 모두 삭제되며 되돌릴 수 없습니다. 탈퇴하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFD32F2F)),
          onPressed: () => Navigator.pop(d, true),
          child: const Text('탈퇴'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final nav = Navigator.of(context);
  final done = await run(context, () async {
    // 본인이 올린 파일(프로필 사진·자격증 사본)을 먼저 지운다. 실패해도 탈퇴는 계속.
    for (final folder in ['avatars/$uid', 'quals/$uid']) {
      try {
        final files = await db.storage.from('files').list(path: folder);
        if (files.isNotEmpty) await db.storage.from('files').remove([for (final f in files) '$folder/${f.name}']);
      } catch (_) {}
    }
    await db.rpc('delete_my_account');
  });
  if (done) {
    nav.popUntil((r) => r.isFirst); // 내 정보 화면 등을 닫고 로그인 화면으로
    await signOut();
  }
}

/// 회원 탈퇴: 실수로 누르지 않도록 메뉴가 아니라 내 정보 화면 맨 아래에 작게 둔다
class DeleteAccountLink extends StatelessWidget {
  final VoidCallback? onPressed; // 시트 안에서는 시트를 닫고 진행
  const DeleteAccountLink({super.key, this.onPressed});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        child: Center(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Brand.muted,
              textStyle: const TextStyle(fontSize: 13, decoration: TextDecoration.underline),
            ),
            onPressed: onPressed ?? () => deleteAccount(context),
            child: const Text('회원 탈퇴'),
          ),
        ),
      );
}

/// 앱바 공통 메뉴: 알림·공지·내정보·로그아웃
List<Widget> commonActions(BuildContext context, Map<String, dynamic> profile) => [
      const NotificationBell(),
      PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'notice':
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen()));
            case 'me':
              if (profile['role'] == 'referee') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              } else {
                // 관리자·대회관계자: 사진 변경 / 정보 수정
                showModalBottomSheet(
                  useSafeArea: true, // 상태바·하단바에 가리지 않게
                  context: context,
                  builder: (s) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ListTile(
                        leading: Avatar(path: profile['avatar_path'], name: profile['name'] ?? '', size: 40),
                        title: Text(profile['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(db.auth.currentUser?.email ?? ''),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.photo_camera_outlined),
                        title: const Text('프로필 사진 변경'),
                        onTap: () {
                          Navigator.pop(s);
                          changeAvatar(context);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text('내 정보 수정'),
                        onTap: () {
                          Navigator.pop(s);
                          editProfile(context, profile);
                        },
                      ),
                      if (profile['role'] != 'admin')
                        DeleteAccountLink(onPressed: () {
                          Navigator.pop(s);
                          deleteAccount(context);
                        }),
                    ]),
                  ),
                );
              }
            case 'logout':
              signOut();
            case 'about':
              Navigator.push(context, MaterialPageRoute(builder: (_) => AppInfoScreen(role: profile['role'])));
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'notice', child: Text('공지사항')),
          const PopupMenuItem(value: 'me', child: Text('내 정보')),
          const PopupMenuItem(value: 'about', child: Text('앱 정보')),
          const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
        ],
      ),
    ];

/// 상태값 한글 표기
const statusLabel = {
  'applied': '지원완료',
  'selected': '선발',
  'reserve': '예비',
  'rejected': '미선발',
  'cancelled': '취소',
  'pending': '승인대기',
  'approved': '승인',
  'confirmed': '확정',
  'unknown': '미확인',
  'attending': '참석',
  'absent': '불참',
};
String label(dynamic s) => statusLabel[s] ?? '$s';

/// 자격 기간 표시: 값이 있는 것만 ("취득 2024.03.01 · 만료 2027.02.28")
String qualPeriod(Map q) => [
      if (q['acquired_on'] != null) '취득 ${fmtDate(q['acquired_on'])}',
      if (q['expires_on'] != null) '만료 ${fmtDate(q['expires_on'])}',
    ].join(' · ');

/// 선발 후 참석 응답 표시
String attendanceText(dynamic a) => switch (a) { 'attending' => '참석 확정', 'absent' => '불참', _ => '참석 미응답' };

/// 앱바 제목 앞 회사 CI(눈꽃 로고)
class BrandTitle extends StatelessWidget {
  final String text;
  const BrandTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/brand/snowflake_blue.png', width: 24, height: 24, semanticLabel: 'WINREF 로고'),
        const SizedBox(width: 8),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ]);
}

/// 자격 입력 항목 (등록·수정 공용). 만료일은 취득일 기준 2년으로 자동 입력.
List<Field> qualFields([Map? q]) => [
      Field('name', '자격명', required: true, initial: q?['name'], options: qualNames, optionsOnly: true),
      Field('grade', '등급', initial: q?['grade'], options: qualGrades, optionsOnly: true),
      Field('cert_no', '자격번호', initial: q?['cert_no']),
      Field('acquired_on', '취득일', type: FieldType.date, notFuture: true, initial: q?['acquired_on']),
      Field('expires_on', '유효기간(만료일)',
          type: FieldType.date,
          notBefore: 'acquired_on',
          initial: q?['expires_on'],
          helper: '취득일을 고르면 2년 뒤 날짜가 자동 입력됩니다',
          autoFrom: 'acquired_on',
          autoYears: 2),
      Field('file_path', '자격증 사본 (사진/PDF) — 관리자 확인용', type: FieldType.file, initial: q?['file_path']),
    ];

/// 삭제 전 확인
Future<bool> confirm(BuildContext context, String title, String body, {String ok = '삭제'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('취소')),
          FilledButton(style: dialogAction, onPressed: () => Navigator.pop(d, true), child: Text(ok)),
        ],
      ),
    ) ==
    true;

/// 알파인 스키 경기 종목
const alpineDisciplines = [
  '회전 (SL)',
  '대회전 (GS)',
  '슈퍼대회전 (SG)',
  '활강 (DH)',
  '알파인 복합 (AC)',
  '평행 회전 (PSL)',
  '평행 대회전 (PGS)',
];

/// 알파인 스키 대회 심판·경기 운영 직무 (목록에 없으면 직접 입력)
const alpineRoles = [
  '기술대표 (TD)',
  '심판장 (Referee)',
  '경기위원장 (Chief of Race)',
  '코스위원장',
  '기문심판장',
  '기문심판',
  '출발심판',
  '결승심판',
  '계시위원장',
  '계시원',
  '코스요원',
];

/// 경기 종목 표시 (예: ⛷ 대회전 (GS))
class DisciplineTag extends StatelessWidget {
  final String text;
  const DisciplineTag(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Brand.ice, borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.flag, size: 14, color: Brand.navy),
          const SizedBox(width: 4),
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Brand.navy, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// 설산 능선 실루엣 (알파인 스키 분위기). 아래쪽 배경색으로 채워 위 영역과 자연스럽게 이어진다.
class MountainRidge extends StatelessWidget {
  final double height;
  final Color? color; // 기본: 화면 배경색
  const MountainRidge({super.key, this.height = 36, this.color});
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(size: Size(double.infinity, height), painter: _RidgePainter(color ?? Brand.ivory)));
}

class _RidgePainter extends CustomPainter {
  final Color color;
  _RidgePainter(this.color);
  @override
  void paint(Canvas canvas, Size s) {
    // 뒤 능선(반투명) + 앞 능선(배경색)
    final back = Path()
      ..moveTo(0, s.height * 0.55)
      ..lineTo(s.width * 0.18, s.height * 0.10)
      ..lineTo(s.width * 0.30, s.height * 0.45)
      ..lineTo(s.width * 0.47, 0)
      ..lineTo(s.width * 0.64, s.height * 0.50)
      ..lineTo(s.width * 0.80, s.height * 0.15)
      ..lineTo(s.width, s.height * 0.55)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(back, Paint()..color = Colors.white.withValues(alpha: 0.22));
    final front = Path()
      ..moveTo(0, s.height * 0.85)
      ..lineTo(s.width * 0.12, s.height * 0.55)
      ..lineTo(s.width * 0.26, s.height * 0.80)
      ..lineTo(s.width * 0.40, s.height * 0.40)
      ..lineTo(s.width * 0.58, s.height * 0.82)
      ..lineTo(s.width * 0.72, s.height * 0.52)
      ..lineTo(s.width * 0.88, s.height * 0.78)
      ..lineTo(s.width, s.height * 0.60)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(front, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RidgePainter old) => old.color != color;
}

/// 자격명·등급 (윈렙아카데미 지정 목록)
const qualNames = ['알파인스키 국내심판', '클린심판아카데미'];
const qualGrades = ['1급 신규', '1급 보수', '2급 신규', '2급 보수', '3급 신규', '3급 보수', '양성과정', '심화과정'];

/// 첫 화면에서 휴대폰 '뒤로' 버튼: 다른 탭이면 홈 탭으로 이동, 홈이면 안내 후
/// 2초 안에 한 번 더 누를 때만 앱 종료 (실수로 앱이 꺼지지 않게). 웹은 브라우저 기본 동작.
class BackGuard extends StatefulWidget {
  final bool atHome;
  final VoidCallback? onHome;
  final Widget child;
  const BackGuard({super.key, this.atHome = true, this.onHome, required this.child});
  @override
  State<BackGuard> createState() => _BackGuardState();
}

class _BackGuardState extends State<BackGuard> {
  DateTime? _last;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: kIsWeb,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (!widget.atHome) return widget.onHome?.call();
          final now = DateTime.now();
          if (_last != null && now.difference(_last!) < const Duration(seconds: 2)) {
            SystemNavigator.pop();
            return;
          }
          _last = now;
          messengerKey.currentState
            ?..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
              content: Text("'뒤로'를 한 번 더 누르면 앱이 종료됩니다."),
              duration: Duration(seconds: 2),
            ));
        },
        child: widget.child,
      );
}

/// 긴 상세 화면 열기: 휴대폰은 아래에서 올라오는 시트, PC(폭 900 이상)는 가운데 창.
/// PC 창은 높이를 화면의 88% 로 제한하고 스크롤바를 항상 보여 아래 내용이 잘려 보이지 않게 한다.
Future<T?> showDetail<T>(
  BuildContext context, {
  double initial = 0.85,
  required Widget Function(BuildContext context, ScrollController controller) builder,
}) {
  if (MediaQuery.sizeOf(context).width >= 900) {
    return showDialog<T>(context: context, builder: (_) => _DetailDialog(builder: builder));
  }
  return showModalBottomSheet<T>(
    useSafeArea: true, // 상태바·하단바에 가리지 않게
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: initial,
      maxChildSize: 0.95,
      builder: builder,
    ),
  );
}

class _DetailDialog extends StatefulWidget {
  final Widget Function(BuildContext, ScrollController) builder;
  const _DetailDialog({required this.builder});
  @override
  State<_DetailDialog> createState() => _DetailDialogState();
}

class _DetailDialogState extends State<_DetailDialog> {
  final _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: h * 0.88),
        child: Stack(children: [
          Scrollbar(
            controller: _sc,
            thumbVisibility: true,
            child: Padding(padding: const EdgeInsets.only(top: 44), child: widget.builder(context, _sc)), // 위쪽은 닫기 버튼 자리
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              tooltip: '닫기',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- 알파인 디자인 디테일 ----------

/// 남색 헤더 위에 흩날리는 눈송이 (장식, 터치·접근성 영향 없음). 위치는 고정이라 화면마다 같은 모양.
class Snowfall extends StatelessWidget {
  final double opacity;
  const Snowfall({super.key, this.opacity = 1});
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: ExcludeSemantics(child: CustomPaint(painter: _SnowPainter(opacity), size: Size.infinite)),
      );
}

class _SnowPainter extends CustomPainter {
  final double opacity;
  _SnowPainter(this.opacity);
  // (x, y 비율, 크기, 투명도) — 무작위처럼 보이되 항상 같은 배치
  static const _flakes = [
    (0.06, 0.18, 1.6, 0.35), (0.14, 0.62, 1.2, 0.25), (0.23, 0.30, 2.2, 0.30), (0.31, 0.80, 1.4, 0.20),
    (0.39, 0.12, 1.2, 0.28), (0.47, 0.52, 1.8, 0.22), (0.55, 0.24, 1.3, 0.30), (0.63, 0.70, 2.0, 0.24),
    (0.71, 0.10, 1.5, 0.32), (0.78, 0.44, 1.2, 0.26), (0.86, 0.22, 2.4, 0.30), (0.93, 0.66, 1.4, 0.22),
    (0.10, 0.90, 1.1, 0.18), (0.50, 0.92, 1.2, 0.16), (0.82, 0.88, 1.1, 0.18), (0.98, 0.36, 1.3, 0.24),
  ];

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white;
    for (final (x, y, r, a) in _flakes) {
      p.color = Colors.white.withValues(alpha: a * opacity);
      canvas.drawCircle(Offset(x * s.width, y * s.height), r, p);
    }
    // 큰 눈꽃 결정 두 개 (가는 선)
    _crystal(canvas, Offset(s.width * 0.90, s.height * 0.30), 14, 0.16 * opacity);
    _crystal(canvas, Offset(s.width * 0.68, s.height * 0.78), 9, 0.12 * opacity);
  }

  void _crystal(Canvas c, Offset o, double r, double a) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: a)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final ang = i * math.pi / 3;
      final tip = o + Offset(math.cos(ang), math.sin(ang)) * r;
      c.drawLine(o, tip, p);
      final mid = o + Offset(math.cos(ang), math.sin(ang)) * r * 0.55;
      for (final d in [-0.6, 0.6]) {
        c.drawLine(mid, mid + Offset(math.cos(ang + d), math.sin(ang + d)) * r * 0.32, p);
      }
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => old.opacity != opacity;
}

/// 섹션 제목: 작은 눈꽃 + 제목 + 오른쪽으로 옅어지는 선 (편집 디자인 느낌)
class SectionHeader extends StatelessWidget {
  final String title;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.title, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8)});
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          ExcludeSemantics(child: Image.asset('assets/brand/snowflake_blue.png', width: 14, height: 14)),
          const SizedBox(width: 7),
          Text(title, style: TextStyle(color: Brand.navy, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0x332560AC), Color(0x002560AC)]),
              ),
            ),
          ),
        ]),
      );
}

/// 빈 화면 그림: 눈 덮인 산 두 개와 기문(旗門) 깃발
class AlpineEmptyArt extends StatelessWidget {
  const AlpineEmptyArt({super.key});
  @override
  Widget build(BuildContext context) =>
      ExcludeSemantics(child: CustomPaint(size: const Size(132, 72), painter: _AlpineArtPainter()));
}

class _AlpineArtPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    // 바닥 눈 언덕
    c.drawPath(
        Path()
          ..moveTo(0, h)
          ..quadraticBezierTo(w * 0.5, h * 0.78, w, h)
          ..close(),
        Paint()..color = const Color(0xFFE3ECF8));
    // 뒤 산
    final back = Path()
      ..moveTo(w * 0.30, h * 0.92)
      ..lineTo(w * 0.62, h * 0.18)
      ..lineTo(w * 0.94, h * 0.92)
      ..close();
    c.drawPath(back, Paint()..color = const Color(0xFFC9D9EF));
    // 앞 산
    final front = Path()
      ..moveTo(w * 0.04, h * 0.95)
      ..lineTo(w * 0.36, h * 0.30)
      ..lineTo(w * 0.70, h * 0.95)
      ..close();
    c.drawPath(front, Paint()..color = const Color(0xFFA9C2E6));
    // 눈 덮인 봉우리
    void cap(double px, double py, double sw) {
      c.drawPath(
          Path()
            ..moveTo(px, py)
            ..lineTo(px - sw, py + sw * 1.15)
            ..lineTo(px - sw * 0.35, py + sw * 0.85)
            ..lineTo(px, py + sw * 1.2)
            ..lineTo(px + sw * 0.4, py + sw * 0.85)
            ..lineTo(px + sw, py + sw * 1.15)
            ..close(),
          Paint()..color = Colors.white);
    }
    cap(w * 0.36, h * 0.30, w * 0.07);
    cap(w * 0.62, h * 0.18, w * 0.06);
    // 기문 깃발 (빨강)
    final pole = Paint()
      ..color = const Color(0xFF6B7684)
      ..strokeWidth = 1.6;
    final fx = w * 0.80, fy = h * 0.50;
    c.drawLine(Offset(fx, fy), Offset(fx, h * 0.96), pole);
    c.drawPath(
        Path()
          ..moveTo(fx, fy)
          ..lineTo(fx + w * 0.11, fy + h * 0.08)
          ..lineTo(fx, fy + h * 0.16)
          ..close(),
        Paint()..color = const Color(0xFFE5484D));
  }

  @override
  bool shouldRepaint(_AlpineArtPainter old) => false;
}

/// 헤더 배경: 단색 + 흩날리는 눈송이. Container(decoration: AlpineHeaderDecoration()) 로 사용.
class AlpineHeaderDecoration extends Decoration {
  final Color? color; // 기본: 머리 영역 바탕색
  const AlpineHeaderDecoration({this.color});
  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _AlpineHeaderPainter(color ?? Brand.header);
}

class _AlpineHeaderPainter extends BoxPainter {
  final Color color;
  _AlpineHeaderPainter(this.color);
  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size ?? Size.zero;
    canvas.drawRect(offset & size, Paint()..color = color);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _SnowPainter(1).paint(canvas, size);
    canvas.restore();
  }
}
