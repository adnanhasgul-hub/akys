import 'package:flutter/material.dart';

import '../../modules/work_schedule/domain/models.dart';

abstract final class AkysColors {
  static const brand = Color(0xFF176B65), background = Color(0xFFF8FAFC);
  static const forbidden = Color(0xFFDC2626),
      fixed = Color(0xFF16A34A),
      warning = Color(0xFFF59E0B);
  static const ranks = [
    Color(0xFF1E3A8A),
    Color(0xFF2563EB),
    Color(0xFF0891B2),
    Color(0xFF16A34A),
    Color(0xFFD97706),
    Color(0xFFDB2777),
    Color(0xFF7C3AED),
  ];
  static Color rank(int rank) => ranks[(rank - 1).clamp(0, 6)];
  static const weekdays = [
    Color(0xFFF8FAFC),
    Color(0xFFF8FAFC),
    Color(0xFFF8FAFC),
    Color(0xFFF3E8FF),
    Color(0xFFEFF6FF),
    Color(0xFFFFF1F2),
    Color(0xFFFEE2E2),
  ];
  static const taskColors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF16A34A),
    Color(0xFFDC2626),
    Color(0xFFD97706),
  ];
  static Color task(ClinicTask task) => taskColors[task.index];
  static ThemeData get theme => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: brand),
    scaffoldBackgroundColor: background,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 6),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}
