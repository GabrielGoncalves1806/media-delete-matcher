import 'package:flutter/material.dart';

/// Paleta do design.html. Escuro por padrão: a mídia é o conteúdo.
abstract final class AppColors {
  static const bg = Color(0xFF0B0B0F);
  static const surface = Color(0xFF15151C);
  static const surface2 = Color(0xFF1E1E28);
  static const line = Color(0xFF2A2A36);
  static const text = Color(0xFFF2F2F5);
  static const muted = Color(0xFF8B8B99);
  static const delete = Color(0xFFFF4D5E);
  static const keep = Color(0xFF2FD47A);
  static const accent = Color(0xFF7C6CFF);
  static const warn = Color(0xFFFFB020);
  static const sky = Color(0xFF3FB6FF);
  static const orange = Color(0xFFFF7A45);
  static const pink = Color(0xFFE14BD7);
  static const system = Color(0xFF55556A);
  static const apps = Color(0xFF3A3A48);
}

/// Space Grotesk pra números e títulos; o resto é Inter (padrão do tema).
TextStyle display(double size, {FontWeight weight = FontWeight.w700, Color? color}) => TextStyle(
      fontFamily: 'SpaceGrotesk',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: -0.02 * size,
      height: 1.1,
      color: color,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.bg,
      error: AppColors.delete,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: display(20, color: AppColors.text),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text, fontFamily: 'Inter'),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.surface),
  );
}
