import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Brand: emerald (Turkmen green) + teal gradient, warm gold accent.
class DostColors {
  static const emerald = Color(0xFF0B8A5E);
  static const teal = Color(0xFF13B3A0);
  static const gold = Color(0xFFF4B740);
  static const deep = Color(0xFF062A22);
  static const red = Color(0xFFE5484D);

  static const brand = LinearGradient(
    colors: [emerald, teal],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// avatar gradients, picked by id
  static const avatars = [
    [Color(0xFF0B8A5E), Color(0xFF13B3A0)],
    [Color(0xFFF59E0B), Color(0xFFEF4444)],
    [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    [Color(0xFF0EA5E9), Color(0xFF2563EB)],
    [Color(0xFFEC4899), Color(0xFFF43F5E)],
    [Color(0xFF14B8A6), Color(0xFF84CC16)],
    [Color(0xFFA855F7), Color(0xFFEC4899)],
    [Color(0xFFF97316), Color(0xFFF4B740)],
  ];
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: DostColors.emerald,
    brightness: b,
    primary: dark ? const Color(0xFF3DD9A4) : DostColors.emerald,
    secondary: DostColors.gold,
    surface: dark ? const Color(0xFF0F1A17) : Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0A1311) : const Color(0xFFF6F8F7),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xFF0F1A17) : Colors.white,
      foregroundColor: dark ? Colors.white : const Color(0xFF0F1A17),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: dark ? Colors.white : const Color(0xFF0F1A17),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF16231F) : const Color(0xFFEFF3F1),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF0F1A17) : Colors.white,
      indicatorColor: DostColors.emerald.withValues(alpha: dark ? 0.35 : 0.14),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      height: 66,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    splashFactory: InkRipple.splashFactory,
  );
}
