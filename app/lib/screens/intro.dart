import 'package:flutter/material.dart';

import '../common.dart';
import '../theme.dart';

/// 첫 실행 안내 (3장): 이 앱으로 무엇을 하는지 회원 유형별로 보여준다. 관리자는 없음.
const introSlides = <String, List<(IconData, String, String)>>{
  'referee': [
    (Icons.flag_outlined, '대회 심판 모집을 한눈에', '모집 중인 알파인 스키 대회를 확인하고\n원하는 직무에 바로 지원하세요.'),
    (Icons.badge_outlined, '자격과 교육을 한 곳에서', '자격을 등록해 승인받고,\n만료 전에 보수교육까지 신청할 수 있어요.'),
    (Icons.qr_code_2, '선발부터 출석, 이력까지', '선발 알림을 받고 현장에서 QR 로 출석하면\n활동 이력과 확인서가 차곡차곡 쌓여요.'),
  ],
  'organizer': [
    (Icons.flag_outlined, '대회와 모집공고 등록', '대회를 등록하고 직무별 심판 모집공고를 올리세요.\n지난 대회 공고를 복사해 쓸 수도 있어요.'),
    (Icons.how_to_reg_outlined, '지원자 확인과 선발', '경험·자격·평가를 보고 선발하면\n결과 알림이 자동으로 전달돼요.'),
    (Icons.qr_code_scanner, '현장 출석과 활동 기록', '대회 당일 QR 로 출석을 확인하고,\n활동완료와 평가까지 한 번에 남기세요.'),
  ],
};

/// 이 기기에서 안내를 이미 봤는가
bool introSeen(String role) => introSlides[role] == null || (prefs?.getBool('intro_seen_$role') ?? false);
void markIntroSeen(String role) => prefs?.setBool('intro_seen_$role', true);

class IntroScreen extends StatefulWidget {
  final String role;
  final VoidCallback onDone;
  const IntroScreen({super.key, required this.role, required this.onDone});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _page = PageController();
  int _i = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = introSlides[widget.role] ?? introSlides['referee']!;
    final last = _i == slides.length - 1;
    return Scaffold(
      backgroundColor: Brand.card,
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 8, 0),
              child: TextButton(onPressed: widget.onDone, child: const Text('건너뛰기')),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (context, i) {
                final (icon, title, body) = slides[i];
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // 눈 내리는 남색 원 안의 큰 아이콘 + 아래 설산 능선
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        height: 220,
                        decoration: AlpineHeaderDecoration(color: Brand.header),
                        child: Stack(children: [
                          Center(
                            child: Container(
                              width: 112,
                              height: 112,
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), shape: BoxShape.circle),
                              child: Icon(icon, size: 56, color: Colors.white),
                            ),
                          ),
                          Positioned(left: 0, right: 0, bottom: -1, child: MountainRidge(height: 30, color: Brand.card)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text('${i + 1} / ${slides.length}', style: TextStyle(color: Brand.muted, fontSize: 12, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Brand.ink, letterSpacing: -0.4)),
                    const SizedBox(height: 12),
                    Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.6, color: Brand.muted)),
                  ]),
                );
              },
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var k = 0; k < slides.length; k++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: k == _i ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(color: k == _i ? Brand.navy : Brand.line, borderRadius: BorderRadius.circular(4)),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: FilledButton(
              onPressed: last
                  ? widget.onDone
                  : () => _page.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut),
              child: Text(last ? '시작하기' : '다음'),
            ),
          ),
        ]),
      ),
    );
  }
}
