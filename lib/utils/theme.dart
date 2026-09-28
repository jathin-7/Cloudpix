import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Configure these with values from Google Cloud Console ─────────────────
  static const googleClientId = '861248627108-u36jepmqsscq6qgin17qa215h4191itj.apps.googleusercontent.com';
  static const googleWebClientId = '861248627108-eadjej095jvt4d3d1qrdkkmlkbot1c0m.apps.googleusercontent.com';

  // ── Colors (Dark Theme) ───────────────────────────────────────────────────
  static const Color primary = Color(0xFF6366F1);        // Indigo
  static const Color accent = Color(0xFF10B981);         // Emerald
  static const Color danger = Color(0xFFEF4444);         // Red
  static const Color warning = Color(0xFFF59E0B);        // Amber

  // ── Backgrounds (Dark) ────────────────────────────────────────────────────
  static const Color bg = Color(0xFF0F172A);             // Dark blue
  static const Color surface = Color(0xFF1E293B);        // Slate 800
  static const Color surfaceAlt = Color(0xFF334155);     // Slate 700

  // ── Text (Dark) ───────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFF1F5F9);    // Slate 100
  static const Color textSecondary = Color(0xFFCBD5E1);  // Slate 300
  static const Color textHint = Color(0xFF94A3B8);       // Slate 400

  // ── Borders (Dark) ────────────────────────────────────────────────────────
  static const Color border = Color(0xFF334155);         // Slate 700

  // ── Light Theme Colors ────────────────────────────────────────────────────
  static const Color lightBg = Color(0xFFFAFAFA);        // Light gray
  static const Color lightSurface = Color(0xFFFFFFFF);   // White
  static const Color lightSurfaceAlt = Color(0xFFF3F4F6);// Light gray 100
  static const Color lightTextPrimary = Color(0xFF1F2937);    // Dark gray
  static const Color lightTextSecondary = Color(0xFF6B7280);  // Gray
  static const Color lightTextHint = Color(0xFF9CA3AF);       // Light gray 400
  static const Color lightBorder = Color(0xFFE5E7EB);    // Light gray border

  // ── Dark theme ───────────────────────────────────────────────────────────
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    primaryColor: primary,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: textPrimary),
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: textHint,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: textHint),
      labelStyle: const TextStyle(color: textSecondary),
    ),
    textTheme: GoogleFonts.outfitTextTheme(
      const TextTheme(
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: textHint,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );

  // ── Light theme ──────────────────────────────────────────────────────────
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: lightBg,
    primaryColor: primary,
    appBarTheme: const AppBarTheme(
      backgroundColor: lightSurface,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: lightTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: lightTextPrimary),
      centerTitle: false,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: lightSurface,
      selectedItemColor: primary,
      unselectedItemColor: lightTextHint,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: lightTextHint),
      labelStyle: const TextStyle(color: lightTextSecondary),
    ),
    textTheme: GoogleFonts.outfitTextTheme(
      const TextTheme(
        titleLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        titleMedium: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        titleSmall: TextStyle(
          color: lightTextPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodyMedium: TextStyle(
          color: lightTextSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
        ),
        bodySmall: TextStyle(
          color: lightTextHint,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: TextStyle(
          color: lightTextPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ),
  );
}

class AppConstants {
  // ── Google Drive folder names ───────────────────────────────────────────
  static const String driveFolderName = 'Cloudpix';
  static const String drivePhotoFolder = 'Photos';
  static const String driveVideoFolder = 'Videos';
  static const String driveThumbFolder = 'Thumbnails';
  static const String driveSecureFolder = 'Secure';
}
