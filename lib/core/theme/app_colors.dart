import 'package:flutter/material.dart';

/// Lecto Design System — Color Palette
///
/// Dark mode is the primary theme. All colors follow
/// a consistent naming convention with semantic meaning.
class AppColors {
  AppColors._();

  // === Brand Colors ===
  static const Color primary = Color(0xFF6366F1); // Indigo-500
  static const Color primaryLight = Color(0xFF818CF8); // Indigo-400
  static const Color primaryDark = Color(0xFF4F46E5); // Indigo-600
  static const Color primaryDeep = Color(0xFF1E1B4B); // Indigo-950

  static const Color accent = Color(0xFF06B6D4); // Cyan-500
  static const Color accentLight = Color(0xFF22D3EE); // Cyan-400
  static const Color accentDark = Color(0xFF0891B2); // Cyan-600

  // === Dark Theme Surfaces ===
  static const Color darkBg = Color(0xFF0F0F14); // Deep dark background
  static const Color darkSurface = Color(0xFF1A1A24); // Card/surface
  static const Color darkSurfaceLight = Color(0xFF252536); // Elevated surface
  static const Color darkBorder = Color(0xFF2E2E42); // Subtle borders

  // === Light Theme Surfaces ===
  static const Color lightBg = Color(0xFFF8FAFC); // Slate-50
  static const Color lightSurface = Color(0xFFFFFFFF); // White
  static const Color lightSurfaceLight = Color(0xFFF1F5F9); // Slate-100
  static const Color lightBorder = Color(0xFFE2E8F0); // Slate-200

  // === Text Colors ===
  static const Color textPrimaryDark = Color(0xFFF8FAFC); // Slate-50
  static const Color textSecondaryDark = Color(0xFF94A3B8); // Slate-400
  static const Color textTertiaryDark = Color(0xFF64748B); // Slate-500

  static const Color textPrimaryLight = Color(0xFF0F172A); // Slate-900
  static const Color textSecondaryLight = Color(0xFF475569); // Slate-600
  static const Color textTertiaryLight = Color(0xFF94A3B8); // Slate-400

  // === Semantic Colors ===
  static const Color success = Color(0xFF10B981);        // Emerald-500
  static const Color successBg = Color(0x2010B981);      // 12% opacity
  static const Color error = Color(0xFFEF4444);          // Red-500
  static const Color errorBg = Color(0x20EF4444);
  static const Color warning = Color(0xFFF59E0B);        // Amber-500
  static const Color warningBg = Color(0x20F59E0B);
  static const Color info = Color(0xFF3B82F6);           // Blue-500
  static const Color infoBg = Color(0x203B82F6);

  // === Recording Colors ===
  static const Color recordingRed = Color(0xFFFF3B30); // Active recording
  static const Color recordingPulse = Color(0xFFFF6B6B); // Recording pulse
  static const Color waveformActive = Color(0xFF6366F1); // Waveform bars
  static const Color waveformInactive = Color(0xFF2E2E42);

  // === Subject Palette (for folder colors) ===
  static const List<Color> subjectColors = [
    Color(0xFF6366F1), // Indigo
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEC4899), // Pink
    Color(0xFFEF4444), // Red
    Color(0xFFF97316), // Orange
    Color(0xFFF59E0B), // Amber
    Color(0xFF10B981), // Emerald
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Blue
    Color(0xFF6B7280), // Gray
  ];
}
