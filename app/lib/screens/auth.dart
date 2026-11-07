import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await db.auth.signInWithPassword(email: _email.text.trim(), password: _pw.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.message.toLowerCase().contains('email not confirmed')) {
        _offerResend();
      } else {
        toast(context, authMessage(e));
      }
    } catch (e) {
      if (mounted) toast(context, '서버에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요.');
    }
    if (mounted) setState(() => _busy = false);
  }

  /// 이메일 미인증 계정: 인증 메일 재발송
  Future<void> _offerResend() async {
    final again = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('이메일 인증이 필요합니다'),
        content: Text('${_email.text.trim()} 로 보낸 인증 메일의 링크를 눌러주세요.\n메일이 없다면 다시 보낼 수 있습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('닫기')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('인증 메일 다시 보내기')),
        ],
      ),
    );
    if (again != true || !mounted) return;
    await run(
      context,
      () => db.auth.resend(type: OtpType.signup, email: _email.text.trim(), emailRedirectTo: appUrl),
      done: '인증 메일을 다시 보냈습니다.',
    );
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      toast(context, '이메일을 먼저 입력하세요.');
      return;
    }
    await run(context, () => db.auth.resetPasswordForEmail(email, redirectTo: appUrl), done: '비밀번호 재설정 메일을 보냈습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Wordmark(),
                  const SizedBox(height: 48),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: '이메일'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '비밀번호'),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _busy ? null : _login, child: const Text('로그인')),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    TextButton(onPressed: _reset, child: const Text('비밀번호 재설정')),
                    TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignupScreen())),
                      child: const Text('회원가입'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: Brand.navy, borderRadius: BorderRadius.circular(4)),
        alignment: Alignment.center,
        child: const Text('W', style: TextStyle(color: Brand.gold, fontSize: 32, fontWeight: FontWeight.w700)),
      ),
      const SizedBox(height: 20),
      const Text('WINREF ACADEMY',
          style: TextStyle(color: Brand.navy, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 4)),
      const SizedBox(height: 6),
      Container(width: 32, height: 1, color: Brand.gold),
      const SizedBox(height: 6),
      const Text('스포츠 인재은행', style: TextStyle(color: Brand.muted, letterSpacing: 2)),
    ]);
  }
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _phone = TextEditingController();
  final _org = TextEditingController();
  String _role = 'referee';
  bool _agree = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _pw, _phone, _org]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agree) {
      toast(context, '개인정보 수집·이용에 동의해주세요.');
      return;
    }
    setState(() => _busy = true);
    bool needsConfirm = false;
    final ok = await run(context, () async {
      final res = await db.auth.signUp(email: _email.text.trim(), password: _pw.text, emailRedirectTo: appUrl, data: {
        'role': _role,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        if (_role == 'organizer') 'organization': _org.text.trim(),
      });
      // 이메일 인증을 켠 프로젝트는 세션이 없으므로 안내만 한다.
      needsConfirm = res.session == null;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    if (needsConfirm) toast(context, '가입 확인 메일을 보냈습니다. 메일의 링크를 누른 뒤 로그인하세요.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('회원 유형', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'referee', label: Text('심판·교육신청자')),
                ButtonSegment(value: 'organizer', label: Text('대회관계자')),
              ],
              selected: {_role},
              onSelectionChanged: (s) => setState(() => _role = s.first),
            ),
            if (_role == 'organizer')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('대회관계자는 관리자 승인 후 대회 등록이 가능합니다.', style: TextStyle(color: Brand.muted, fontSize: 13)),
              ),
            const SizedBox(height: 20),
            _f(_name, '이름', required: true),
            _f(_email, '이메일', required: true, type: TextInputType.emailAddress, validator: (v) {
              return v != null && v.contains('@') ? null : '이메일 형식이 아닙니다';
            }),
            _f(_pw, '비밀번호 (8자 이상)', required: true, obscure: true, validator: (v) {
              return (v ?? '').length >= 8 ? null : '8자 이상 입력';
            }),
            _f(_phone, '휴대폰 번호', required: true, type: TextInputType.phone),
            if (_role == 'organizer') _f(_org, '소속 기관', required: true),
            CheckboxListTile(
              value: _agree,
              onChanged: (v) => setState(() => _agree = v ?? false),
              contentPadding: EdgeInsets.zero,
              tileColor: Colors.transparent,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('개인정보 수집·이용 동의 (필수)'),
              subtitle: const Text('이름·연락처·자격정보를 교육·대회 운영 목적으로만 이용합니다.'),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('가입하기')),
          ],
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label,
      {bool required = false, bool obscure = false, TextInputType? type, String? Function(String?)? validator}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(labelText: label),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return '필수 입력';
          return validator?.call(v);
        },
      ),
    );
  }
}

/// 비밀번호 재설정 메일의 링크로 들어왔을 때 새 비밀번호 입력
class NewPasswordScreen extends StatefulWidget {
  final VoidCallback onDone;
  const NewPasswordScreen({super.key, required this.onDone});
  @override
  State<NewPasswordScreen> createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final ok = await run(context, () => db.auth.updateUser(UserAttributes(password: _pw.text)),
        done: '비밀번호를 변경했습니다.');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 비밀번호 설정'), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              TextFormField(
                controller: _pw,
                obscureText: true,
                decoration: const InputDecoration(labelText: '새 비밀번호 (8자 이상)'),
                validator: (v) => (v ?? '').length >= 8 ? null : '8자 이상 입력',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pw2,
                obscureText: true,
                decoration: const InputDecoration(labelText: '새 비밀번호 확인'),
                validator: (v) => v == _pw.text ? null : '비밀번호가 일치하지 않습니다',
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('변경하기')),
            ]),
          ),
        ),
      ),
    );
  }
}
