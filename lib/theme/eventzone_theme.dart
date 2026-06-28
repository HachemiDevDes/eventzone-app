import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class EventzoneTheme {
  // Colors - Premium Palette
  static const Color backgroundStart = Color(0xFF0B0F19);
  static const Color backgroundEnd = Color(0xFF06080F);
  static const Color cardColor = Color(0xFF111827);
  static const Color primaryAction = Color(0xFF1A73E8);
  static const Color accentSuccess = Color(0xFF10B981);
  static const Color accentWarning = Color(0xFFF59E0B);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color glassBackground = Color(0x0AFFFFFF); 
  static const Color glassBorder = Color(0x1AFFFFFF);

  static ThemeData get darkTheme {
    final baseTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
    );

    return baseTheme.copyWith(
      primaryColor: primaryAction,
      scaffoldBackgroundColor: backgroundEnd,
      colorScheme: const ColorScheme.dark(
        primary: primaryAction,
        secondary: accentSuccess,
        surface: cardColor,
        onSurface: textPrimary,
      ),
      // Apply Space Grotesk globally to all text
      textTheme: GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme).copyWith(
        displayLarge: GoogleFonts.spaceGrotesk(
          color: textPrimary,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.0,
        ),
        headlineMedium: GoogleFonts.spaceGrotesk(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: GoogleFonts.spaceGrotesk(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: GoogleFonts.spaceGrotesk(
          color: textPrimary,
          fontSize: 16,
          height: 1.6,
        ),
        bodyMedium: GoogleFonts.spaceGrotesk(
          color: textSecondary,
          fontSize: 14,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.spaceGrotesk(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  static Widget buildPlayfulBackground({required Widget child}) {
    return Container(
      decoration: const BoxDecoration(color: backgroundStart),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryAction.withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: 200,
            left: -150,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentSuccess.withOpacity(0.08),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  backgroundStart,
                  backgroundStart.withOpacity(0.8),
                  backgroundEnd,
                ],
              ),
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  static BoxDecoration get mainGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [backgroundStart, backgroundEnd, Color(0xFF000000)],
          stops: [0.0, 0.6, 1.0],
        ),
      );
}
