import 'package:flutter/material.dart';

/// The app's colours.
///
/// A warm, light palette: off-white paper, coral for anything you act on, and
/// soft tints for the cards. Taken from the design mockups rather than picked
/// ad hoc, so screens stay consistent as they are rebuilt.
class AppColors {
  AppColors._();

  // === Brand ===
  /// Coral. Used for the record button, links and anything actionable.
  static const Color primary = Color(0xFFF16743);
  static const Color primaryLight = Color(0xFFFF7B54);
  static const Color primaryDark = Color(0xFFD9502C);

  /// Deep brown-red, for text sitting on a coral tint.
  static const Color primaryInk = Color(0xFF743C28);

  // === Surfaces ===
  /// Page background — warm off-white, not pure white.
  static const Color background = Color(0xFFFAF7F2);

  /// Cards and sheets.
  static const Color surface = Color(0xFFFFFFFF);

  /// A slightly recessed surface, for rows inside a card.
  static const Color surfaceMuted = Color(0xFFF4EEE6);

  /// Hairlines and card outlines.
  static const Color border = Color(0xFFEFE8DE);
  static const Color borderStrong = Color(0xFFD8D0C5);

  /// The floating bottom navigation bar.
  static const Color navBar = Color(0xFF1E1B18);
  static const Color navBarMuted = Color(0xFF2C2723);

  // === Text ===
  static const Color textPrimary = Color(0xFF1C1917);
  static const Color textSecondary = Color(0xFF7C756D);
  static const Color textMuted = Color(0xFFA8A29E);

  /// Text on a coral or dark background.
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // === Card tints ===
  /// Soft backgrounds for the dashboard cards, paired with [tintInk] text.
  static const Color tintCoral = Color(0xFFFCEEE8);
  static const Color tintLavender = Color(0xFFEDE9FE);
  static const Color tintMint = Color(0xFFD9F2E6);
  static const Color tintSky = Color(0xFFDCEBFB);
  static const Color tintYellow = Color(0xFFFFF2CD);
  static const Color tintPink = Color(0xFFFFEBF0);
  static const Color tintCream = Color(0xFFFEF4DC);

  /// Readable ink for each tint above.
  static const Color inkCoral = Color(0xFF743C28);
  static const Color inkLavender = Color(0xFF5244E3);
  static const Color inkMint = Color(0xFF128B62);
  static const Color inkSky = Color(0xFF2E78E6);

  // === Status ===
  static const Color success = Color(0xFF128B62);
  static const Color successBg = Color(0xFFD9F2E6);
  static const Color error = Color(0xFFDC2626);
  static const Color errorBg = Color(0xFFFDE7E7);
  static const Color warning = Color(0xFFB45309);
  static const Color warningBg = Color(0xFFFFF2CD);
  static const Color info = Color(0xFF2E78E6);
  static const Color infoBg = Color(0xFFDCEBFB);

  // === Recording ===
  static const Color recordingRed = Color(0xFFF16743);
  static const Color recordingPulse = Color(0xFFFF7B54);
  static const Color waveformActive = Color(0xFFF16743);
  static const Color waveformInactive = Color(0xFFE2D9CD);

  // === Subject palette ===
  /// Folder colours, muted to sit on the warm background.
  static const List<Color> subjectColors = [
    Color(0xFFF16743), // Coral
    Color(0xFF5244E3), // Indigo
    Color(0xFF128B62), // Green
    Color(0xFF2E78E6), // Blue
    Color(0xFFD946A6), // Pink
    Color(0xFFB45309), // Amber
    Color(0xFF7C3AED), // Violet
    Color(0xFF0E7490), // Teal
    Color(0xFFDC2626), // Red
    Color(0xFF7C756D), // Stone
  ];

  // === Migration shims ===
  // The app was dark-themed and these names are used across screens that have
  // not been rebuilt yet. They point at the new palette so nothing looks out
  // of place, and each one disappears as its screen is redone.
  static const Color accent = primaryLight;
  static const Color accentLight = primaryLight;
  static const Color accentDark = primaryDark;
  static const Color primaryDeep = tintCoral;
  static const Color darkBg = background;
  static const Color darkSurface = surface;
  static const Color darkSurfaceLight = surfaceMuted;
  static const Color darkBorder = border;
  static const Color lightBg = background;
  static const Color lightSurface = surface;
  static const Color lightSurfaceLight = surfaceMuted;
  static const Color lightBorder = border;
  static const Color textPrimaryDark = textPrimary;
  static const Color textSecondaryDark = textSecondary;
  static const Color textTertiaryDark = textMuted;
  static const Color textPrimaryLight = textPrimary;
  static const Color textSecondaryLight = textSecondary;
  static const Color textTertiaryLight = textMuted;
}
