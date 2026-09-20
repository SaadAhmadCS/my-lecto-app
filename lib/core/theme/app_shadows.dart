import 'package:flutter/material.dart';

/// Lecto Design System — Shadows & Elevation
class AppShadows {
  AppShadows._();

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get glow => [
        BoxShadow(
          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          blurRadius: 20,
          spreadRadius: 2,
        ),
      ];

  static List<BoxShadow> get recordingGlow => [
        BoxShadow(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
          blurRadius: 24,
          spreadRadius: 4,
        ),
      ];
}
