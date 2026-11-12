import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../theme.dart';
import 'auth.dart' show SupportProgramMark;

const appName = 'WINREF 알파인 스키 심판 인재은행';
const _build = String.fromEnvironment('BUILD');
const appVersion = _build == '' ? '1.0.0' : '1.0.0 (빌드 $_build)';
const supportEmail = 'winrefacademy@gmail.com';

/// 앱 정보: 버전·운영사·문의·약관·오픈소스 라이선스
class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 정보')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
        children: [
          Center(
            child: Column(children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(color: Brand.ivoryDeep, borderRadius: BorderRadius.circular(24)),
                padding: const EdgeInsets.all(16),
                child: Image.asset('assets/brand/snowflake_blue.png'),
              ),
              const SizedBox(height: 16),
              const Text(appName,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Brand.ink)),
              const SizedBox(height: 6),
              const Text('버전 $appVersion', style: TextStyle(color: Brand.muted, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 28),
          _Group(children: [
            const _Row(icon: Icons.business_outlined, title: '운영', value: '주식회사 윈렙아카데미'),
            const _Row(icon: Icons.code, title: '개발', value: '빠드빠닉'),
            _Row(
              icon: Icons.mail_outline,
              title: '문의',
              value: supportEmail,
              onTap: () => launchUrl(Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent('WINREF 앱 문의')}')),
            ),
          ]),
          const SizedBox(height: 16),
          _Group(children: [
            const _Row(icon: Icons.privacy_tip_outlined, title: '개인정보처리방침', onTap: openPrivacy),
            _Row(
              icon: Icons.person_remove_outlined,
              title: '계정 삭제 안내',
              onTap: () => launchUrl(Uri.parse('${appUrl}delete-account.html'), mode: LaunchMode.externalApplication),
            ),
            _Row(
              icon: Icons.description_outlined,
              title: '오픈소스 라이선스',
              onTap: () => showLicensePage(
                context: context,
                applicationName: appName,
                applicationVersion: appVersion,
                applicationIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset('assets/brand/snowflake_blue.png', width: 48, height: 48),
                ),
                applicationLegalese: '© 주식회사 윈렙아카데미',
              ),
            ),
          ]),
          const SizedBox(height: 32),
          const Center(child: SupportProgramMark()),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Brand.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52),
            children[i],
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  const _Row({required this.icon, required this.title, this.value, this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: Brand.navy),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: value == null ? null : Text(value!, style: const TextStyle(color: Brand.muted)),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right, color: Brand.muted),
        onTap: onTap,
      );
}
