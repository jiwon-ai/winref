import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
import 'screens/auth.dart';
import 'screens/profile.dart';
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
String authMessage(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login credentials')) return '이메일 또는 비밀번호가 올바르지 않습니다.';
  if (m.contains('email not confirmed')) return '이메일 인증이 필요합니다. 받은 메일의 링크를 눌러주세요.';
  if (m.contains('already registered') || m.contains('already been registered')) return '이미 가입된 이메일입니다. 로그인해 주세요.';
  if (m.contains('password should be') || m.contains('weak')) return '비밀번호가 너무 짧거나 쉽습니다. 8자 이상으로 정해주세요.';
  if (m.contains('rate limit') || m.contains('too many')) return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
  if (m.contains('invalid email') || m.contains('unable to validate email')) return '이메일 형식이 올바르지 않습니다.';
  if (m.contains('same') && m.contains('password')) return '이전과 다른 비밀번호를 입력해 주세요.';
  if (m.contains('expired') || (m.contains('invalid') && m.contains('token'))) return '링크가 만료되었습니다. 다시 요청해 주세요.';
  if (e is AuthRetryableFetchException || m.contains('fetch') || m.contains('socket')) {
    return '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
  }
  debugPrint('인증 오류: ${e.message}');
  return '로그인 처리 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// 로그아웃: 이전 사용자 화면의 안내 메시지를 지우고 세션 종료
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
  return '일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요.';
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
            const Icon(Icons.cloud_off_outlined, size: 40, color: Brand.muted),
            const SizedBox(height: 12),
            Text(error == null ? '불러오지 못했습니다.' : friendlyError(error!),
                textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted)),
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
          Icon(icon, size: 40, color: const Color(0xFFB4C2D4)),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Brand.muted, height: 1.5)),
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

// ---------- 입력 폼 다이얼로그 ----------

enum FieldType { text, multiline, number, date, datetime, file }

class Field {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final String? initial;
  final String? helper; // 입력칸 아래 안내
  /// 날짜 자동 채움: [autoFrom] 날짜를 고르면 그 날짜 + [autoYears]년으로 채운다(직접 고치면 그 값 유지)
  final String? autoFrom;
  final int autoYears;
  const Field(this.key, this.label,
      {this.type = FieldType.text, this.required = false, this.initial, this.helper, this.autoFrom, this.autoYears = 0});
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
    final init = DateTime.tryParse(_values[f.key]?.toString() ?? '')?.toLocal() ?? now;
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(1950), lastDate: DateTime(now.year + 30));
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
                  readOnly: f.type == FieldType.date || f.type == FieldType.datetime || f.type == FieldType.file,
                  onTap: f.type == FieldType.date || f.type == FieldType.datetime || f.type == FieldType.file
                      ? () => _pick(f)
                      : null,
                  keyboardType: f.type == FieldType.number ? TextInputType.number : null,
                  maxLines: f.type == FieldType.multiline ? 5 : 1,
                  decoration: InputDecoration(
                    labelText: f.required ? '${f.label} *' : f.label,
                    helperText: f.helper,
                    border: const OutlineInputBorder(),
                    suffixIcon: switch (f.type) {
                      FieldType.date || FieldType.datetime => const Icon(Icons.calendar_today),
                      FieldType.file => const Icon(Icons.upload_file),
                      _ => null,
                    },
                  ),
                  validator: (v) {
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
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: rows.isEmpty
              ? ListView(children: [EmptyView(widget.empty)])
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => widget.item(c, rows[i], reload),
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
          child: const Text('모두 읽음', style: TextStyle(color: Brand.ivory)),
        ),
      ]),
      body: AsyncList(
        key: _key,
        load: () => db.from('notifications').select().eq('user_id', uid).order('created_at', ascending: false).limit(100),
        empty: '알림이 없습니다.',
        item: (c, n, reload) {
          final unread = n['read_at'] == null;
          return ListTile(
            tileColor: unread ? const Color(0xFFF1F7FF) : Colors.white,
            leading: Icon(_icons[n['kind']] ?? Icons.campaign_outlined, color: unread ? Brand.gold : Brand.muted),
            title: Text(n['title'], style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text('${n['body'] ?? ''}\n${fmtDateTime(n['created_at'])}'),
            isThreeLine: true,
            onTap: !unread
                ? null
                : () async {
                    await db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', n['id']);
                    reload();
                  },
          );
        },
      ),
    );
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
    Field('name', '이름', required: true, initial: p['name']),
    Field('phone', '휴대폰', initial: p['phone']),
    Field('birth_date', '생년월일', type: FieldType.date, initial: p['birth_date']),
    if (p['role'] == 'organizer') Field('organization', '소속 기관', initial: p['organization']),
    if (referee) ...[
      Field('region', '활동 지역 (예: 서울)', initial: p['region']),
      Field('sport', '주 종목 (예: 축구)', initial: p['sport']),
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
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('탈퇴')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
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
  if (done) await signOut();
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
                editProfile(context, profile);
              }
            case 'logout':
              signOut();
            case 'delete':
              deleteAccount(context);
            case 'about':
              showAboutDialog(
                context: context,
                applicationName: 'WINREF 인재은행',
                applicationVersion: '1.0.0',
                applicationIcon: Image.asset('assets/brand/snowflake_blue.png', width: 48, height: 48),
                applicationLegalese: '운영 윈렙아카데미 · 개발 빠드빠닉',
                children: [
                  TextButton(onPressed: openPrivacy, child: const Text('개인정보처리방침')),
                  const SizedBox(height: 8),
                  const SupportProgramMark(),
                ],
              );
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'notice', child: Text('공지사항')),
          const PopupMenuItem(value: 'me', child: Text('내 정보')),
          const PopupMenuItem(value: 'about', child: Text('앱 정보')),
          const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
          if (profile['role'] != 'admin') const PopupMenuItem(value: 'delete', child: Text('회원 탈퇴')),
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
        Image.asset('assets/brand/snowflake_white.png', width: 24, height: 24, semanticLabel: 'WINREF 로고'),
        const SizedBox(width: 8),
        Flexible(child: Text(text, overflow: TextOverflow.ellipsis)),
      ]);
}

/// 자격 입력 항목 (등록·수정 공용). 만료일은 취득일 기준 2년으로 자동 입력.
List<Field> qualFields([Map? q]) => [
      Field('name', '자격명', required: true, initial: q?['name']),
      Field('grade', '등급', initial: q?['grade']),
      Field('cert_no', '자격번호', initial: q?['cert_no']),
      Field('acquired_on', '취득일', type: FieldType.date, initial: q?['acquired_on']),
      Field('expires_on', '유효기간(만료일)',
          type: FieldType.date,
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
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(ok)),
        ],
      ),
    ) ==
    true;
