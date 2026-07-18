import 'package:flutter/material.dart';

/// App color palette — optimised for a grades viewer used daily.
/// Philosophy: dark-navy headers, neutral-white scaffold, blue accents.
abstract final class AppColors {
  // Primary brand (dark navy → muted slate-blue gradient)
  static const Color primary = Color(
    0xFF3B5BA8,
  ); // muted slate-blue — buttons, pills, selected
  static const Color primaryDark = Color(
    0xFF1E2D5E,
  ); // deep navy — gradient start, dark emphasis

  // Backgrounds
  static const Color scaffoldBg = Color(
    0xFFF8FAFC,
  ); // Slate 50 — barely off-white, calm
  // (card/surface uses Colors.white)

  // Onboarding surfaces. These are intentionally quiet and slightly warm:
  // the connection flow should feel like a dependable academic tool, not a
  // marketing page.
  static const Color onboardingBg = Color(0xFFF5F6F3);
  static const Color fieldFill = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFCBD3DF);

  // Text
  static const Color textDark = Color(
    0xFF1E293B,
  ); // Slate 800 — headings, strong text
  static const Color textMuted = Color(
    0xFF94A3B8,
  ); // Slate 400 — placeholders, secondary
  static const Color textSecondary = Color(0xFF5B6574);

  // Form feedback
  static const Color error = Color(0xFFB42318);
  static const Color errorSurface = Color(0xFFFFF0EE);

  // Grade semantic colors
  static const Color gradeExcellent = Color(0xFF059669); // Emerald 600 — ≥ 14
  static const Color gradePassing = Color(0xFF0284C7); // Sky 600     — ≥ 10
  static const Color gradeWarning = Color(0xFFEA580C); // Orange 600  — < 10

  // Status (switches, validated units, notification enabled)
  static const Color statusPositive = Color(
    0xFF059669,
  ); // same as gradeExcellent

  // AppBar gradient
  static const List<Color> headerGradient = [primaryDark, primary];
}
