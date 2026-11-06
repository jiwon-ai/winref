import 'package:flutter/material.dart';

/// 남색 + 아이보리 + 절제된 골드 포인트
class Brand {
  static const navy = Color(0xFF14213D);
  static const navyLight = Color(0xFF2B3A5C);
  static const ivory = Color(0xFFF7F3EA);
  static const ivoryDeep = Color(0xFFEDE6D6);
  static const gold = Color(0xFFB08D57);
  static const ink = Color(0xFF1C1C1C);
  static const muted = Color(0xFF6B6658);
}

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Brand.navy,
    onPrimary: Brand.ivory,
    primaryContainer: Brand.ivoryDeep,
    onPrimaryContainer: Brand.navy,
    secondary: Brand.gold,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFF1E7D3),
    onSecondaryContainer: Brand.navy,
    surface: Brand.ivory,
    onSurface: Brand.ink,
    surfaceContainerHighest: Brand.ivoryDeep,
    onSurfaceVariant: Brand.muted,
    outline: Color(0xFFCFC6B2),
    outlineVariant: Color(0xFFE2DACA),
    error: Color(0xFF9B2C2C),
    onError: Colors.white,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: Brand.ink, displayColor: Brand.navy);

  return base.copyWith(
    scaffoldBackgroundColor: Brand.ivory,
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.5),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: Brand.navy),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Brand.navy,
      foregroundColor: Brand.ivory,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: Brand.ivory, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: Brand.ivoryDeep,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((s) =>
          IconThemeData(color: s.contains(WidgetState.selected) ? Brand.navy : Brand.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Brand.navy : Brand.muted)),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: Brand.navy,
      indicatorColor: Brand.navyLight,
      selectedIconTheme: IconThemeData(color: Brand.gold),
      unselectedIconTheme: IconThemeData(color: Color(0xFFB9C0D0)),
      selectedLabelTextStyle: TextStyle(color: Brand.ivory, fontWeight: FontWeight.w700),
      unselectedLabelTextStyle: TextStyle(color: Color(0xFFB9C0D0)),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE2DACA)),
      ),
    ),
    listTileTheme: const ListTileThemeData(tileColor: Colors.white, iconColor: Brand.navy),
    dividerTheme: const DividerThemeData(color: Color(0xFFE2DACA), space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Brand.navy,
        foregroundColor: Brand.ivory,
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Brand.navy,
        side: const BorderSide(color: Brand.navy),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: Brand.navy)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Brand.gold,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Color(0xFFCFC6B2)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: Brand.navy, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Brand.ivoryDeep,
      side: BorderSide.none,
      labelStyle: const TextStyle(color: Brand.navy, fontSize: 12, fontWeight: FontWeight.w600),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Brand.ivory,
      unselectedLabelColor: Color(0xFFB9C0D0),
      indicatorColor: Brand.gold,
    ),
    snackBarTheme: const SnackBarThemeData(backgroundColor: Brand.navy, contentTextStyle: TextStyle(color: Brand.ivory)),
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
      'selected' || 'approved' || 'confirmed' || 'attending' => (const Color(0xFFF1E7D3), const Color(0xFF7A5C2E)),
      'rejected' || 'cancelled' || 'absent' => (const Color(0xFFEAE7E1), Brand.muted),
      _ => (Brand.ivoryDeep, Brand.navy),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
