import 'package:flutter/material.dart';

/// 남색 + 아이보리 + 절제된 골드 포인트
/// WINREF ACADEMY 로고 색(#4A90E2) 기반 팔레트
/// 이름은 기존 코드 호환을 위해 유지: navy=주색(진한 파랑), gold=강조(로고 파랑), ivory=배경
class Brand {
  /// 다크 모드 여부 (main.dart 가 화면 모드 설정에 따라 정한다). 아래 색들은 이 값에 따라 바뀐다.
  static bool dark = false;

  static Color get navy => dark ? const Color(0xFF4A8BEA) : const Color(0xFF2560AC);      // 주색: 버튼·선택·강조
  static Color get navyLight => dark ? const Color(0xFF24385C) : const Color(0xFF3B7BCB); // 머리 영역 안 박스
  static const gold = Color(0xFF4A90E2);      // 로고 파랑: 밝은 강조 (밝은·어두운 화면 공통)
  static const ice = Color(0xFFD6E8FF);       // 진한 파랑 위 강조 글자
  static Color get warn => dark ? const Color(0xFFF0A04B) : const Color(0xFFD9822B);      // 경고 (자격 만료 임박 등)
  static Color get ivory => dark ? const Color(0xFF0F1622) : const Color(0xFFF4F6F9);     // 화면 배경
  static Color get ivoryDeep => dark ? const Color(0xFF1E2D47) : const Color(0xFFE8F0FB); // 선택·칩 옅은 파랑
  static Color get ink => dark ? const Color(0xFFE6EAF0) : const Color(0xFF191F28);       // 본문
  static Color get muted => dark ? const Color(0xFF9AA5B4) : const Color(0xFF6B7684);     // 보조 글자
  static Color get line => dark ? const Color(0xFF2A3546) : const Color(0xFFE5E8EB);      // 구분선·테두리
  static Color get card => dark ? const Color(0xFF182233) : Colors.white;                 // 카드·시트·상단바 바탕
  static Color get header => dark ? const Color(0xFF16253F) : const Color(0xFF2560AC);    // 눈 내리는 머리 영역 바탕
  static Color get outline => dark ? const Color(0xFF3A475A) : const Color(0xFFD1D6DB);   // 입력칸·버튼 테두리
  static Color get fill => dark ? const Color(0xFF222E42) : const Color(0xFFF2F4F6);      // 옅은 회색 채움

  /// 밝은 화면용 옅은 색 바탕(연노랑·연초록 등)을 다크 모드에서는 같은 색조의 어두운 바탕으로 바꾼다
  static Color soft(Color light) => dark ? Color.lerp(light, const Color(0xFF0F1622), 0.80)! : light;
}

/// 화면 모드 설정: 'light'(기본) · 'dark' · 'system'(휴대폰 설정을 따름). 앱 정보 화면에서 바꾼다.
final themeSetting = ValueNotifier<String>('light');
const themeLabels = {'light': '밝은 화면', 'dark': '어두운 화면 (다크 모드)', 'system': '휴대폰 설정에 맞춤'};

ThemeData buildTheme() {
  final scheme = ColorScheme(
    brightness: Brand.dark ? Brightness.dark : Brightness.light,
    primary: Brand.navy,
    onPrimary: Colors.white,
    primaryContainer: Brand.ivoryDeep,
    onPrimaryContainer: Brand.navy,
    secondary: Brand.gold,
    onSecondary: Colors.white,
    secondaryContainer: Brand.ivoryDeep,
    onSecondaryContainer: Brand.navy,
    surface: Brand.card,
    onSurface: Brand.ink,
    surfaceContainerHighest: Brand.fill,
    onSurfaceVariant: Brand.muted,
    outline: Brand.outline,
    outlineVariant: Brand.line,
    error: const Color(0xFFD22030),
    onError: Colors.white,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Pretendard');
  final text = base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.ink, fontFamily: 'Pretendard');

  return base.copyWith(
    scaffoldBackgroundColor: Brand.ivory,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: Brand.ink, letterSpacing: -0.2),
      bodyLarge: text.bodyLarge?.copyWith(letterSpacing: -0.2),
      bodyMedium: text.bodyMedium?.copyWith(letterSpacing: -0.1, height: 1.45),
    ),
    // 흰 상단바 + 왼쪽 정렬 굵은 제목 (요즘 국내 앱 기본형)
    appBarTheme: AppBarTheme(
      backgroundColor: Brand.card,
      foregroundColor: Brand.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      shape: Border(bottom: BorderSide(color: Brand.line)),
      titleTextStyle: TextStyle(
          fontFamily: 'Pretendard', color: Brand.ink, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4),
      iconTheme: IconThemeData(color: Brand.ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Brand.card,
      indicatorColor: Colors.transparent,
      elevation: 0,
      height: 64,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Brand.navy : const Color(0xFFB0B8C1))),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
          color: s.contains(WidgetState.selected) ? Brand.navy : const Color(0xFF8B95A1))),
    ),
    // 관리자 웹 사이드바: 흰 바탕
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Brand.card,
      indicatorColor: Brand.ivoryDeep,
      selectedIconTheme: IconThemeData(color: Brand.navy),
      unselectedIconTheme: IconThemeData(color: Color(0xFF8B95A1)),
      selectedLabelTextStyle: TextStyle(fontFamily: 'Pretendard', color: Brand.navy, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(fontFamily: 'Pretendard', color: Color(0xFF6B7684), fontWeight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: Brand.card,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Brand.line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: Colors.transparent,
      iconColor: Brand.navy,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      titleTextStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 15.5, fontWeight: FontWeight.w600, color: Brand.ink, letterSpacing: -0.3),
      subtitleTextStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 13, color: Brand.muted, height: 1.45),
    ),
    dividerTheme: DividerThemeData(color: Brand.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Brand.line,
        disabledForegroundColor: const Color(0xFF8B95A1),
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.ink,
        side: BorderSide(color: Brand.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Brand.navy,
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Brand.navy,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Brand.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Brand.navy, width: 1.6),
      ),
      labelStyle: TextStyle(color: Brand.muted),
      hintStyle: const TextStyle(color: Color(0xFF8B95A1)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Brand.card,
      selectedColor: Brand.ivoryDeep,
      side: BorderSide(color: Brand.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      labelStyle: TextStyle(fontFamily: 'Pretendard', color: Brand.ink, fontSize: 13, fontWeight: FontWeight.w600),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Brand.card,
        selectedBackgroundColor: Brand.ivoryDeep,
        selectedForegroundColor: Brand.navy,
        foregroundColor: Brand.muted,
        side: BorderSide(color: Brand.outline),
        textStyle: const TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: Brand.navy,
      unselectedLabelColor: Color(0xFF8B95A1),
      indicatorColor: Brand.navy,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Brand.line,
      labelStyle: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w700, fontSize: 15),
      unselectedLabelStyle: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600, fontSize: 15),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF333D4B),
      contentTextStyle: const TextStyle(fontFamily: 'Pretendard', color: Colors.white, fontSize: 14),
      behavior: SnackBarBehavior.floating, // 하단 버튼·FAB 를 가리지 않게 떠 있는 알림
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actionTextColor: Brand.ice,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 19, fontWeight: FontWeight.w700, color: Brand.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Brand.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Brand.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    expansionTileTheme: const ExpansionTileThemeData(shape: Border(), collapsedShape: Border()),
    drawerTheme: DrawerThemeData(backgroundColor: Brand.card, surfaceTintColor: Colors.transparent),
  );
}

/// 상태 배지 (선발=골드, 미선발/취소=회색, 그 외 남색 톤)
class StatusChip extends StatelessWidget {
  final String text;
  final String status;
  const StatusChip(this.text, this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'selected' || 'approved' || 'confirmed' || 'attending' =>
        Brand.dark ? (const Color(0xFF1E3A5F), const Color(0xFF9CC4F5)) : (const Color(0xFFE3EFFC), const Color(0xFF1F5FAF)),
      'rejected' || 'cancelled' || 'absent' => (Brand.fill, Brand.muted),
      _ => (Brand.ivoryDeep, Brand.navy),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// 대화상자 버튼: 기본 버튼의 꽉 찬 폭 대신 내용 폭 (취소·확인이 한 줄에)
final dialogAction = FilledButton.styleFrom(minimumSize: const Size(88, 44), padding: const EdgeInsets.symmetric(horizontal: 20));
