import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography — Plus Jakarta Sans.
///
/// Rounded and slightly geometric, which suits the soft cards and warm
/// background better than a neutral grotesque.
class AppTypography {
  AppTypography._();

  static TextTheme get textTheme => TextTheme(
    // Display
    displayLarge: GoogleFonts.plusJakartaSans(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    displayMedium: GoogleFonts.plusJakartaSans(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    displaySmall: GoogleFonts.plusJakartaSans(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.25,
      height: 1.3,
    ),

    // Headline
    headlineLarge: GoogleFonts.plusJakartaSans(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    headlineMedium: GoogleFonts.plusJakartaSans(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    headlineSmall: GoogleFonts.plusJakartaSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),

    // Title
    titleLarge: GoogleFonts.plusJakartaSans(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleMedium: GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),
    titleSmall: GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      height: 1.4,
    ),

    // Body
    bodyLarge: GoogleFonts.plusJakartaSans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    bodySmall: GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),

    // Label
    labelLarge: GoogleFonts.plusJakartaSans(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: 0.1,
    ),
    labelMedium: GoogleFonts.plusJakartaSans(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: 0.5,
    ),
    labelSmall: GoogleFonts.plusJakartaSans(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: 0.5,
    ),
  );
}
