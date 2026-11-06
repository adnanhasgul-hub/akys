import 'package:flutter/material.dart';

import '../design/clinical_teal_theme.dart';

import '../../modules/work_schedule/domain/models.dart';

abstract final class AkysColors {
  // Compatibility aliases: one shared theme, separate personnel palettes.
  static const brand = AkysTokens.primary, background = AkysTokens.background;
  static const forbidden = AkysTokens.error,
      fixed = AkysTokens.success,
      warning = AkysTokens.warning;
  // Identity colors from the approved reference; never used as rule severity.
  static const ranks = [
    Color(0xFF00A7AA),
    Color(0xFF006B70),
    Color(0xFF007775),
    Color(0xFF008859),
    Color(0xFF006E78),
    Color(0xFF48AA52),
    Color(0xFFE5AA24),
  ];
  static Color rank(int rank) => ranks[(rank - 1).clamp(0, 6)];
  static const weekdays = [
    AkysTokens.surface,
    AkysTokens.surface,
    AkysTokens.surface,
    AkysTokens.surface,
    AkysTokens.surface,
    AkysTokens.background,
    AkysTokens.background,
  ];
  static const taskColors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF16A34A),
    Color(0xFFDC2626),
    Color(0xFFD97706),
  ];
  static Color task(ClinicTask task) => taskColors[task.index];
  static ThemeData get theme => ClinicalTealTheme.light;
}
