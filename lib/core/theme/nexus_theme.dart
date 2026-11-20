import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'nexus_colors.dart';

abstract final class NexusTheme {
  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      primary: NexusColors.primary,
      secondary: NexusColors.indigo,
      surface: NexusColors.bgSurface,
      error: NexusColors.rose,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: NexusColors.textSecondary,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NexusColors.bgDeep,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        foregroundColor: NexusColors.textPrimary,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: NexusColors.textPrimary,
          letterSpacing: -0.4,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: NexusColors.textPrimary,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: NexusColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: NexusColors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: NexusColors.textMuted,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexusColors.bgDeep.withOpacity(0.65),
        hintStyle: const TextStyle(
          color: NexusColors.textSubtle,
          fontSize: 13,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexusColors.borderInput),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexusColors.borderInput),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: NexusColors.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: NexusColors.rose),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: NexusColors.borderSubtle,
        thickness: 1,
      ),
    );
  }
}
