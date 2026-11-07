import 'package:flutter/foundation.dart';
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

  /// 구글·카카오 로그인 (처음이면 자동 가입 → 가입 정보 입력 화면)
  Future<void> _social(OAuthProvider provider) async {
    await run(context, () async {
      await db.auth.signInWithOAuth(
        provider,
        redirectTo: kIsWeb ? appUrl : mobileAuthCallback,
        authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
      );
    });
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
      body: SingleChildScrollView(
        child: Column(children: [
          const BrandHero(),
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                  const SizedBox(height: 20),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('또는', style: TextStyle(color: Brand.muted, fontSize: 13)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 20),
                  _SocialButton(
                    label: '카카오로 계속하기',
                    background: const Color(0xFFFEE500),
                    foreground: const Color(0xD9000000),
                    icon: const Icon(Icons.chat_bubble, size: 18, color: Color(0xD9000000)),
                    onPressed: () => _social(OAuthProvider.kakao),
                  ),
                  const SizedBox(height: 10),
                  _SocialButton(
                    label: 'Google로 계속하기',
                    background: Colors.white,
                    foreground: const Color(0xFF1F1F1F),
                    border: const Color(0xFF747775),
                    icon: const Text('G',
                        style: TextStyle(color: Color(0xFF4285F4), fontWeight: FontWeight.w800, fontSize: 18)),
                    onPressed: () => _social(OAuthProvider.google),
                  ),
                ],
              ),
            ),
          ),
          ),
          const SupportProgramMark(),
        ]),
      ),
    );
  }
}

/// 로그인 상단 브랜드 영역: 로고 파랑 배경 + WINREF ACADEMY 로고(눈꽃·워드마크·슬로건)
class BrandHero extends StatelessWidget {
  const BrandHero({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Brand.gold, // 로고 원본 배경색 #4A90E2
      padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 40, 24, 32),
      child: Column(children: [
        Image.asset('assets/brand/lockup_white.png', width: 260, semanticLabel: 'WINREF ACADEMY'),
        const SizedBox(height: 14),
        const Text('스포츠 인재은행', style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 3)),
      ]),
    );
  }
}

/// 지원사업 결과물 표기: 사회적기업 창업지원사업
class SupportProgramMark extends StatelessWidget {
  const SupportProgramMark({super.key});
  @override
  Widget build(BuildContext context) {
    const gray = Color(0xFF9AA5B4);
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 20, child: Divider(color: Color(0xFFD5DCE6), thickness: 1)),
        SizedBox(width: 10),
        Text('사회적기업 창업지원사업',
            style: TextStyle(color: gray, fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 1.2)),
        SizedBox(width: 10),
        SizedBox(width: 20, child: Divider(color: Color(0xFFD5DCE6), thickness: 1)),
      ]),
    );
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

class _SocialButton extends StatelessWidget {
  final String label;
  final Color background, foreground;
  final Color? border;
  final Widget icon;
  final VoidCallback onPressed;
  const _SocialButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size.fromHeight(50),
        side: BorderSide(color: border ?? background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon,
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      ]),
    );
  }
}

/// 구글·카카오로 처음 들어온 회원: 회원 유형·연락처·동의를 받아 가입을 마친다
class OnboardingScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.profile, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile['name'] ?? '');
  final _phone = TextEditingController();
  final _org = TextEditingController();
  String _role = 'referee';
  bool _agree = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_agree) {
      toast(context, '개인정보 수집·이용에 동의해주세요.');
      return;
    }
    setState(() => _busy = true);
    final organizer = _role == 'organizer';
    final ok = await run(
      context,
      () => db.from('profiles').update({
        'role': _role,
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'organization': organizer ? _org.text.trim() : null,
        'org_status': organizer ? 'pending' : null,
        'onboarded': true,
        'agreed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid),
      done: '가입이 완료되었습니다.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가입 정보 입력'), actions: [
        TextButton(onPressed: signOut, child: const Text('취소', style: TextStyle(color: Brand.ivory))),
      ]),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const Text('처음 오셨네요. 몇 가지만 입력하면 가입이 끝납니다.', style: TextStyle(color: Brand.muted)),
          const SizedBox(height: 20),
          Text('회원 유형', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'referee', label: Text('심판·교육신청자')),
              ButtonSegment(value: 'organizer', label: Text('대회관계자')),
            ],
            selected: {_role},
            onSelectionChanged: (v) => setState(() => _role = v.first),
          ),
          if (_role == 'organizer')
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('대회관계자는 관리자 승인 후 대회 등록이 가능합니다.', style: TextStyle(color: Brand.muted, fontSize: 13)),
            ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: '이름'),
            validator: (v) => (v ?? '').trim().isEmpty ? '필수 입력' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '휴대폰 번호'),
            validator: (v) => (v ?? '').trim().isEmpty ? '필수 입력' : null,
          ),
          if (_role == 'organizer') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _org,
              decoration: const InputDecoration(labelText: '소속 기관'),
              validator: (v) => (v ?? '').trim().isEmpty ? '필수 입력' : null,
            ),
          ],
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
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('가입 완료')),
        ]),
      ),
    );
  }
}
