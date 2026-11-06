import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final db = Supabase.instance.client;
final messengerKey = GlobalKey<ScaffoldMessengerState>();

/// 로그아웃: 이전 사용자 화면의 안내 메시지를 지우고 세션 종료
Future<void> signOut() async {
  messengerKey.currentState?.clearSnackBars();
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// 서버 호출을 실행하고 실패 시 메시지를 띄운다. 성공하면 true.
Future<bool> run(BuildContext context, Future<void> Function() action, {String? done}) async {
  try {
    await action();
    if (context.mounted && done != null) toast(context, done);
    return true;
  } on PostgrestException catch (e) {
    if (context.mounted) toast(context, '오류: ${e.message}');
  } on AuthException catch (e) {
    if (context.mounted) toast(context, '오류: ${e.message}');
  } catch (e) {
    if (context.mounted) toast(context, '오류: $e');
  }
  return false;
}

// ---------- 파일 (포스터·브리핑·공지 첨부) ----------

/// 파일을 골라 storage 'files' 버킷에 올리고 경로를 돌려준다. 취소 시 null.
Future<String?> pickAndUpload(BuildContext context, String folder) async {
  final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
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
  const Field(this.key, this.label, {this.type = FieldType.text, this.required = false, this.initial});
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

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.initial != null && f.initial!.isNotEmpty) {
        _values[f.key] = f.initial;
        if (f.type == FieldType.date) _c[f.key]!.text = fmtDate(f.initial);
        if (f.type == FieldType.datetime) _c[f.key]!.text = fmtDateTime(f.initial);
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
    final d = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(1950), lastDate: DateTime(now.year + 5));
    if (d == null || !mounted) return;
    if (f.type == FieldType.date) {
      setState(() { _values[f.key] = DateFormat('yyyy-MM-dd').format(d); _c[f.key]!.text = fmtDate(d.toIso8601String()); });
      return;
    }
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(init));
    if (t == null) return;
    final dt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    setState(() { _values[f.key] = dt.toUtc().toIso8601String(); _c[f.key]!.text = fmtDateTime(dt.toIso8601String()); });
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
          return Center(child: TextButton(onPressed: reload, child: Text('불러오기 실패 (다시 시도)\n${snap.error}')));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final rows = snap.data!;
        return RefreshIndicator(
          onRefresh: () async => reload(),
          child: rows.isEmpty
              ? ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(widget.empty)))])
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

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림')),
      body: AsyncList(
        load: () => db.from('notifications').select().eq('user_id', uid).order('created_at', ascending: false).limit(100),
        empty: '알림이 없습니다.',
        item: (c, n, reload) => ListTile(
          leading: Icon(n['read_at'] == null ? Icons.notifications_active : Icons.notifications_none),
          title: Text(n['title']),
          subtitle: Text('${n['body'] ?? ''}\n${fmtDateTime(n['created_at'])}'),
          isThreeLine: true,
          onTap: n['read_at'] != null
              ? null
              : () async {
                  await db.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', n['id']);
                  reload();
                },
        ),
      ),
    );
  }
}

/// 개인정보·프로필 관리
Future<void> editProfile(BuildContext context, Map<String, dynamic> p) async {
  final v = await showForm(context, '내 정보', [
    Field('name', '이름', required: true, initial: p['name']),
    Field('phone', '휴대폰', initial: p['phone']),
    Field('birth_date', '생년월일', type: FieldType.date, initial: p['birth_date']),
    if (p['role'] == 'organizer') Field('organization', '소속 기관', initial: p['organization']),
  ]);
  if (v == null || !context.mounted) return;
  await run(context, () => db.from('profiles').update(v).eq('id', uid), done: '저장했습니다.');
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
  final done = await run(context, () => db.rpc('delete_my_account'));
  if (done) await signOut();
}

/// 앱바 공통 메뉴: 알림·공지·내정보·로그아웃
List<Widget> commonActions(BuildContext context, Map<String, dynamic> profile) => [
      IconButton(
        tooltip: '알림',
        icon: const Icon(Icons.notifications_outlined),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())),
      ),
      PopupMenuButton<String>(
        onSelected: (v) {
          switch (v) {
            case 'notice':
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NoticesScreen()));
            case 'me':
              editProfile(context, profile);
            case 'logout':
              signOut();
            case 'delete':
              deleteAccount(context);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'notice', child: Text('공지사항')),
          const PopupMenuItem(value: 'me', child: Text('내 정보')),
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
