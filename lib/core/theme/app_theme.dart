import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Builds the dark (default) and light [ThemeData] for Karlshare.
///
/// We seed Material 3's [ColorScheme] from the brand gold so all derived
/// container/surface/onColor slots stay coherent, then override the bits we
/// care about (warm surface ladder, scaffold background, text). Gold always
/// carries DARK foreground text — white-on-gold fails contrast. On light
/// surfaces the interactive gold deepens ([AppColors.goldDeep]) for the same
/// reason. Custom colors not covered by ColorScheme live in [KarlshareColors].
class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(brightness: Brightness.dark);
  static ThemeData get light => _build(brightness: Brightness.light);

  static ThemeData _build({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;

    // Interactive gold per surface brightness (contrast, not taste).
    final accent = isDark ? AppColors.gold : AppColors.goldDeep;
    // Foreground ON gold fills is always the warm near-black.
    const onGold = AppColors.lightTextPrimary;

    final background = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final surfaceElevated = isDark
        ? AppColors.darkSurfaceElevated
        : AppColors.lightSurfaceElevated;
    final surfaceSunken =
        isDark ? AppColors.darkBackground : AppColors.lightSurfaceSunken;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final borderStrong =
        isDark ? AppColors.darkBorderStrong : AppColors.lightBorderStrong;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final textTertiary =
        isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    final base = ColorScheme.fromSeed(
      seedColor: AppColors.gold,
      brightness: brightness,
    );
    final colorScheme = base.copyWith(
      primary: accent,
      onPrimary: onGold,
      secondary: AppColors.forest,
      onSecondary: Colors.white,
      tertiary: AppColors.goldDeep,
      onTertiary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerLowest: background,
      surfaceContainerLow: surfaceSunken,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceElevated,
      surfaceContainerHighest: surfaceElevated,
      outline: border,
      outlineVariant: borderStrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: colorScheme,
      textTheme: AppTypography.textTheme(textPrimary, textSecondary),
      dividerColor: border,
      splashColor: accent.withValues(alpha: isDark ? 0.10 : 0.06),
      highlightColor: accent.withValues(alpha: isDark ? 0.06 : 0.04),
      iconTheme: IconThemeData(color: textPrimary),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: textPrimary,
        iconTheme: IconThemeData(color: textPrimary),
        titleTextStyle:
            AppTypography.heading3.copyWith(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        color: surfaceElevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textSecondary,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.heading3.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppTypography.heading3.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? onGold : textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark
            ? AppColors.darkSurfaceElevated
            : AppColors.lightTextPrimary,
        contentTextStyle: AppTypography.bodyRegular.copyWith(
          color: isDark ? AppColors.darkTextPrimary : Colors.white,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
      ),
      extensions: <ThemeExtension<dynamic>>[
        KarlshareColors(
          background: background,
          surface: surface,
          surfaceElevated: surfaceElevated,
          surfaceSunken: surfaceSunken,
          border: border,
          borderStrong: borderStrong,
          textPrimary: textPrimary,
          textSecondary: textSecondary,
          textTertiary: textTertiary,
          accent: accent,
          accentSoft: accent.withValues(alpha: isDark ? 0.20 : 0.12),
          // Warm-black shadows; dark mode elevates via the surface ladder
          // instead of shadows.
          shadow: isDark ? Colors.transparent : const Color(0x0F1C170E),
          shadowStrong: isDark ? Colors.transparent : const Color(0x1A1C170E),
        ),
      ],
    );
  }
}

/// Karlshare-specific colors not covered by [ColorScheme]. Access via
/// `Theme.of(context).extension<KarlshareColors>()!`.
@immutable
class KarlshareColors extends ThemeExtension<KarlshareColors> {
  const KarlshareColors({
    required this.background,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceSunken,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.shadow,
    required this.shadowStrong,
  });

  final Color background;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceSunken;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;
  final Color shadow;
  final Color shadowStrong;

  @override
  KarlshareColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceSunken,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? shadow,
    Color? shadowStrong,
  }) =>
      KarlshareColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
        accentSoft: accentSoft ?? this.accentSoft,
        shadow: shadow ?? this.shadow,
        shadowStrong: shadowStrong ?? this.shadowStrong,
      );

  @override
  KarlshareColors lerp(KarlshareColors? other, double t) {
    if (other == null) return this;
    return KarlshareColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      shadowStrong: Color.lerp(shadowStrong, other.shadowStrong, t)!,
    );
  }
}
