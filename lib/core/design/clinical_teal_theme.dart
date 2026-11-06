import 'package:flutter/material.dart';

/// Module-independent semantic tokens. Personnel/rank colors are not statuses.
abstract final class AkysTokens {
  static const primary = Color(0xFF006B68), navy = Color(0xFF123047);
  static const background = Color(0xFFF5F8FA), selected = Color(0xFFDDF3EF);
  static const warning = Color(0xFFE7A34C), warningText = Color(0xFF513000);
  static const success = Color(0xFF17643B), successSurface = Color(0xFFE7F4EC);
  static const error = Color(0xFFA4262C), errorSurface = Color(0xFFFCEBED);
  static const info = Color(0xFF245B81), infoSurface = Color(0xFFE9F2FA);
  static const border = Color(0xFF647985),
      disabled = Color(0xFF526470),
      disabledSurface = Color(0xFFE6ECEF);
  static const softBorder = Color(0xFFE2E9EB);
  static const muted = Color(0xFF4C626F), surface = Colors.white;
  static const spaceXs = 4.0,
      spaceSm = 8.0,
      spaceMd = 16.0,
      spaceLg = 24.0,
      spaceXl = 32.0;
  static const radiusSm = 8.0, radiusMd = 16.0, radiusLg = 24.0;
  static const elevationFlat = 0.0,
      elevationRaised = 2.0,
      elevationDialog = 6.0;
  static const tablet = 720.0, desktop = 1100.0, maxContent = 1200.0;
}

abstract final class ClinicalTealTheme {
  static ThemeData get light {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AkysTokens.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AkysTokens.primary,
          onPrimary: Colors.white,
          primaryContainer: AkysTokens.selected,
          onPrimaryContainer: AkysTokens.navy,
          secondary: AkysTokens.navy,
          onSecondary: Colors.white,
          surface: AkysTokens.surface,
          onSurface: AkysTokens.navy,
          onSurfaceVariant: AkysTokens.muted,
          outline: AkysTokens.border,
          error: AkysTokens.error,
          onError: Colors.white,
        );
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AkysTokens.radiusMd),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AkysTokens.background,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: base.textTheme
          .apply(bodyColor: AkysTokens.navy, displayColor: AkysTokens.navy)
          .copyWith(
            headlineLarge: const TextStyle(
              fontSize: 36,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: AkysTokens.navy,
            ),
            headlineSmall: const TextStyle(
              fontSize: 24,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: AkysTokens.navy,
            ),
            titleLarge: const TextStyle(
              fontSize: 20,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AkysTokens.navy,
            ),
            bodyLarge: const TextStyle(
              fontSize: 16,
              height: 1.5,
              color: AkysTokens.navy,
            ),
            bodyMedium: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AkysTokens.navy,
            ),
          ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AkysTokens.background,
        foregroundColor: AkysTokens.navy,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shadowColor: AkysTokens.navy.withValues(alpha: .12),
        margin: EdgeInsets.zero,
        shape: shape.copyWith(
          side: const BorderSide(color: AkysTokens.softBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          disabledForegroundColor: AkysTokens.disabled,
          disabledBackgroundColor: AkysTokens.disabledSurface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: shape,
          side: const BorderSide(color: AkysTokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AkysTokens.border),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: AkysTokens.primary, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: AkysTokens.elevationDialog,
        shape: shape,
      ),
      dividerTheme: const DividerThemeData(
        color: AkysTokens.border,
        thickness: 1,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AkysTokens.navy,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AkysTokens.primary,
      ),
      focusColor: AkysTokens.selected,
    );
  }
}
