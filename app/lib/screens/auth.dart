import 'package:flutter/material.dart';

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
    await run(context, () => db.auth.signInWithPassword(email: _email.text.trim(), password: _pw.text));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reset() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      toast(context, '이메일을 먼저 입력하세요.');
      return;
    }
    await run(context, () => db.auth.resetPasswordForEmail(email), done: '비밀번호 재설정 메일을 보냈습니다.');
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
      final res = await db.auth.signUp(email: _email.text.trim(), password: _pw.text, data: {
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
