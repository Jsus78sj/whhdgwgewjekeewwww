import 'package:flutter/material.dart';

/// Color tokens mirrored directly from the GitHub Nexus dark Glassmorphism UI.
abstract final class NexusColors {
  static const Color bgDeep = Color(0xFF020617); // slate-950
  static const Color bgSurface = Color(0xFF0F172A); // slate-900
  static const Color bgElevated = Color(0xFF1E293B); // slate-800
  static const Color bgHover = Color(0xFF334155); // slate-700

  static const Color primary = Color(0xFF3B82F6); // blue-500
  static const Color primaryDark = Color(0xFF1D4ED8); // blue-700
  static const Color primaryBright = Color(0xFF2563EB); // blue-600
  static const Color primarySoft = Color(0xFF60A5FA); // blue-400
  static const Color indigo = Color(0xFF6366F1); // indigo-500
  static const Color violet = Color(0xFF8B5CF6); // violet-500

  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color successSoft = Color(0xFF34D399); // emerald-400
  static const Color successDark = Color(0xFF047857); // emerald-700

  static const Color danger = Color(0xFFEF4444); // red-500
  static const Color rose = Color(0xFFF43F5E); // rose-500
  static const Color roseSoft = Color(0xFFFB7185); // rose-400

  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color warningSoft = Color(0xFFFBBF24); // amber-400

  static const Color textPrimary = Color(0xFFF8FAFC); // slate-50
  static const Color textSecondary = Color(0xFFE2E8F0); // slate-200
  static const Color textMuted = Color(0xFF94A3B8); // slate-400
  static const Color textSubtle = Color(0xFF64748B); // slate-500

  static const Color borderSubtle = Color(0x14FFFFFF); // white 8%
  static const Color borderAccent = Color(0x333B82F6); // blue 20%
  static const Color borderInput = Color(0x80475569); // slate-600 50%

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryBright, primaryDark],
  );

  static const LinearGradient brandLogoGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [primaryBright, indigo],
  );

  static const LinearGradient successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF059669), successDark],
  );
}
