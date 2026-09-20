import 'package:flutter/material.dart';

/// Lecto Design System — Spacing & Layout
///
/// Based on 4px base unit, primarily using 8px grid.
class AppSpacing {
  AppSpacing._();

  // === Base Units ===
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double base = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 40.0;
  static const double huge = 48.0;
  static const double massive = 64.0;

  // === Border Radius ===
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 999.0;

  // === Common Padding ===
  static const EdgeInsets pagePadding = EdgeInsets.symmetric(
    horizontal: base,
    vertical: sm,
  );

  static const EdgeInsets cardPadding = EdgeInsets.all(base);

  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: base,
    vertical: md,
  );

  // === Icon Sizes ===
  static const double iconSm = 16.0;
  static const double iconMd = 20.0;
  static const double iconBase = 24.0;
  static const double iconLg = 28.0;
  static const double iconXl = 32.0;

  // === Touch Targets ===
  static const double minTouchTarget = 48.0;

  // === Animation Durations ===
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 300);
  static const Duration animSlow = Duration(milliseconds: 500);
  static const Duration animVerySlow = Duration(milliseconds: 800);
}
