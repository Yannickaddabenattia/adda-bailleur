// ════════════════════════════════════════════════════════════════════
// ADDA BAILLEUR — Améliorations design + UI + aide plans (FICHIER UNIQUE)
// ════════════════════════════════════════════════════════════════════
//
// 👉 OÙ LE METTRE : remplacez lib/core/theme/app_theme.dart par ce fichier.
// ✅ Tous les noms de couleurs existants sont conservés → rien ne casse.
// 🧩 Contient : design global + composants UI + aide de l'éditeur de plans.
// ▶️ Aide plans : appelez showPlanHelpSheet(context, terrain: plan.kind == PlanKind.terrain)
//    depuis un bouton « ? » dans la barre du haut de l'éditeur.
// ════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

// ╔══════════════════════════════════════════════════════════════════╗
// ║  1. COULEURS & DESIGN SYSTEM                                       ║
// ╚══════════════════════════════════════════════════════════════════╝

class AppColors {
  static const Color primary = Color(0xFF4B46C4);
  static const Color primaryLight = Color(0xFF7F77DD);
  static const Color primaryDark = Color(0xFF3A338F);
  // Teinte douce de la couleur primaire (fonds de bannières info).
  static const Color violetSoft = Color(0xFFEDECFB);

  static const Color accent = Color(0xFFF59E0B);
  static const Color accentSoft = Color(0xFFFDEBD3);

  static const Color background = Color(0xFFF6F6FB);
  static const Color surface = Colors.white;
  static const Color surfaceAlt = Color(0xFFF1F2FA);
  static const Color textPrimary = Color(0xFF15172E);
  static const Color textSecondary = Color(0xFF5B6480);
  static const Color divider = Color(0xFFE7E9F4);

  static const Color error = Color(0xFFDC2626);
  static const Color errorSoft = Color(0xFFFEE2E2);
  static const Color success = Color(0xFF0E9F6E);
  static const Color successSoft = Color(0xFFDCF5E9);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSoft = Color(0xFFFDEBD3);

  static const Color navy = Color(0xFF0F1B3A);
  static const Color darkBackground = Color(0xFF0E1326);
  static const Color darkSurface = Color(0xFF151D33);
  static const Color darkSurfaceAlt = Color(0xFF1E2A46);
  static const Color darkTextPrimary = Color(0xFFE6E9F5);
  static const Color darkTextSecondary = Color(0xFF98A2C0);
  static const Color darkDivider = Color(0xFF263254);

  // ── Palette de marque unifiée (refonte design) ──────────────────────
  // Indigo = navigation/marque par défaut. Vert/Rouge/Ambre/Bleu = sens
  // (vert = encaissé/positif, rouge = perte/retard, ambre = action à faire,
  // bleu = information/attendu). Couleurs alignées sur les icônes 3D.
  static const Color brandIndigo = Color(0xFF4B46C4);
  static const Color brandNavy = Color(0xFF1B2347);
  static const Color brandGreen = Color(0xFF1F9D6B);
  static const Color brandRed = Color(0xFFE0524F);
  static const Color brandAmber = Color(0xFFF0A431);
  static const Color brandBlue = Color(0xFF2F86D8);
}

class AppRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const double pill = 100;
}

class AppTheme {
  static ThemeData get light => _build(
        brightness: Brightness.light,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        scaffold: AppColors.background,
        surface: AppColors.surface,
        surfaceAlt: AppColors.surfaceAlt,
        textPrimary: AppColors.textPrimary,
        textSecondary: AppColors.textSecondary,
        divider: AppColors.divider,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        primary: AppColors.primaryLight,
        onPrimary: Colors.white,
        scaffold: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        surfaceAlt: AppColors.darkSurfaceAlt,
        textPrimary: AppColors.darkTextPrimary,
        textSecondary: AppColors.darkTextSecondary,
        divider: AppColors.darkDivider,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color onPrimary,
    required Color scaffold,
    required Color surface,
    required Color surfaceAlt,
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
  }) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      primary: primary,
      surface: surface,
      error: AppColors.error,
    ).copyWith(
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceAlt,
      outlineVariant: divider,
    );

    final base =
        isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    final textTheme = base
        .copyWith(
          displaySmall: base.displaySmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.1),
          headlineMedium: base.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.15),
          headlineSmall: base.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2),
          titleLarge: base.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.5),
          labelLarge: base.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
        )
        .apply(bodyColor: textPrimary, displayColor: textPrimary);

    OutlineInputBorder border(Color c, [double w = 1.4]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: c, width: w),
        );

    ButtonStyle baseButton(Color bg, Color fg) => ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(bg),
          foregroundColor: WidgetStatePropertyAll(fg),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md))),
          overlayColor:
              WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.12)),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      dividerColor: divider,
      splashFactory: InkSparkle.splashFactory,
      hoverColor: primary.withValues(alpha: isDark ? 0.16 : 0.06),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: baseButton(primary, onPrimary)),
      filledButtonTheme:
          FilledButtonThemeData(style: baseButton(primary, onPrimary)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(primary),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
          side: WidgetStatePropertyAll(BorderSide(color: divider, width: 1.4)),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md))),
          overlayColor:
              WidgetStatePropertyAll(primary.withValues(alpha: 0.07)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(primary),
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm))),
          overlayColor:
              WidgetStatePropertyAll(primary.withValues(alpha: 0.08)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor:
              WidgetStatePropertyAll(primary.withValues(alpha: 0.10)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceAlt : AppColors.surface,
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.8)),
        labelStyle:
            TextStyle(color: textSecondary, fontWeight: FontWeight.w600),
        floatingLabelStyle:
            TextStyle(color: primary, fontWeight: FontWeight.w700),
        border: border(divider),
        enabledBorder: border(divider),
        focusedBorder: border(primary, 2),
        errorBorder: border(AppColors.error),
        focusedErrorBorder: border(AppColors.error, 2),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: divider),
        ),
        color: surface,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceAlt : surfaceAlt,
        selectedColor: primary.withValues(alpha: 0.14),
        secondarySelectedColor: primary.withValues(alpha: 0.14),
        side: BorderSide(color: divider),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill)),
        labelStyle: TextStyle(
            color: textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
        secondaryLabelStyle:
            TextStyle(color: primary, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        elevation: 12,
        modalElevation: 12,
        showDragHandle: true,
        dragHandleColor: divider,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.14),
        elevation: 1,
        height: 66,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? primary : textSecondary);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        titleTextStyle:
            textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle:
            textTheme.bodyMedium?.copyWith(color: textSecondary),
      ),
      dividerTheme: DividerThemeData(color: divider, thickness: 1, space: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14.5),
        actionTextColor: AppColors.primaryLight,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
        insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: divider,
        circularTrackColor: divider,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : null),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? primary.withValues(alpha: 0.45)
                : null),
      ),
      textTheme: textTheme,
    );
  }
}

extension AppThemeContext on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceColor =>
      isDark ? AppColors.darkSurface : AppColors.surface;
  Color get surfaceAltColor =>
      isDark ? AppColors.darkSurfaceAlt : AppColors.surfaceAlt;
  Color get backgroundColor =>
      isDark ? AppColors.darkBackground : AppColors.background;
  Color get textPrimaryColor =>
      isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  Color get textSecondaryColor =>
      isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  Color get dividerColor => isDark ? AppColors.darkDivider : AppColors.divider;

  ThemeData get theme => Theme.of(this);
  Color get primaryColor => isDark ? AppColors.primaryLight : AppColors.primary;
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  2. TROUSSE DE COMPOSANTS RÉUTILISABLES (UI kit)                   ║
// ╚══════════════════════════════════════════════════════════════════╝

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool highlight;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.lg);
    final bg = color ?? context.surfaceColor;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: Border.all(
          color: highlight
              ? context.primaryColor.withValues(alpha: 0.55)
              : context.dividerColor,
          width: highlight ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.22 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: radius, onTap: onTap, child: card),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  final IconData? icon;

  const SectionTitle(this.title,
      {super.key, this.subtitle, this.action, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: context.primaryColor),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.textSecondaryColor)),
                ],
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

enum BannerKind { info, success, warning, danger }

class InfoBanner extends StatelessWidget {
  final String message;
  final String? title;
  final BannerKind kind;
  final IconData? icon;
  final VoidCallback? onClose;

  const InfoBanner(
    this.message, {
    super.key,
    this.title,
    this.kind = BannerKind.info,
    this.icon,
    this.onClose,
  });

  const InfoBanner.info(this.message,
      {super.key, this.title, this.icon, this.onClose})
      : kind = BannerKind.info;
  const InfoBanner.success(this.message,
      {super.key, this.title, this.icon, this.onClose})
      : kind = BannerKind.success;
  const InfoBanner.warning(this.message,
      {super.key, this.title, this.icon, this.onClose})
      : kind = BannerKind.warning;
  const InfoBanner.danger(this.message,
      {super.key, this.title, this.icon, this.onClose})
      : kind = BannerKind.danger;

  ({Color fg, Color bg, IconData icon}) _palette() {
    switch (kind) {
      case BannerKind.success:
        return (
          fg: AppColors.success,
          bg: AppColors.successSoft,
          icon: Icons.check_circle_outline
        );
      case BannerKind.warning:
        return (
          fg: AppColors.warning,
          bg: AppColors.warningSoft,
          icon: Icons.warning_amber_rounded
        );
      case BannerKind.danger:
        return (
          fg: AppColors.error,
          bg: AppColors.errorSoft,
          icon: Icons.error_outline
        );
      case BannerKind.info:
        return (
          fg: AppColors.primaryDark,
          bg: AppColors.violetSoft,
          icon: Icons.info_outline
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette();
    final fg = context.isDark ? Colors.white : p.fg;
    final bg = context.isDark ? p.fg.withValues(alpha: 0.18) : p.bg;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.fg.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? p.icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!,
                      style: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5)),
                  const SizedBox(height: 2),
                ],
                Text(message,
                    style: TextStyle(
                        color: context.isDark
                            ? Colors.white
                            : context.textPrimaryColor,
                        fontSize: 14,
                        height: 1.45)),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: fg,
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
            ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: context.primaryColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(icon, size: 36, color: context.primaryColor),
            ),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: context.textSecondaryColor)),
            ],
            if (action != null) ...[
              const SizedBox(height: 22),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusChip(this.label, {super.key, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class StepHeader extends StatelessWidget {
  final int step;
  final int total;
  final String title;
  final String? subtitle;

  const StepHeader({
    super.key,
    required this.step,
    required this.total,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight]),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text('$step',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Étape $step sur $total',
                  style: TextStyle(
                      color: context.textSecondaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
              const SizedBox(height: 1),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.textSecondaryColor)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;

  const FeatureRow(this.text,
      {super.key, this.icon = Icons.check, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final c = iconColor ?? AppColors.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, size: 15, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  3. AIDE GUIDÉE DE L'ÉDITEUR DE PLANS                              ║
// ╚══════════════════════════════════════════════════════════════════╝

class PlanHelpBanner extends StatelessWidget {
  final bool terrain;
  final VoidCallback? onClose;

  const PlanHelpBanner({super.key, this.terrain = false, this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => showPlanHelpSheet(context, terrain: terrain),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight]),
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Première fois ? Créez votre plan en 4 étapes',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5)),
                      SizedBox(height: 1),
                      Text('Appuyez ici pour voir le mode d’emploi rapide.',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12.5)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Masquer',
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showPlanHelpSheet(BuildContext context, {bool terrain = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: context.surfaceColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => _PlanHelpSheet(terrain: terrain),
  );
}

class _PlanHelpSheet extends StatelessWidget {
  final bool terrain;
  const _PlanHelpSheet({required this.terrain});

  @override
  Widget build(BuildContext context) {
    final steps = terrain ? _terrainSteps : _roomSteps;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(terrain ? Icons.park_outlined : Icons.grid_on,
                    color: context.primaryColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  terrain
                      ? 'Dessiner un plan de terrain'
                      : 'Créer un plan en 4 étapes',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pas besoin d’être précis au pixel : placez vos éléments, puis '
            'calibrez l’échelle une seule fois — les mesures se calculent '
            'toutes seules.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: context.textSecondaryColor, height: 1.5),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < steps.length; i++) ...[
            _StepTile(
              number: i + 1,
              icon: steps[i].icon,
              title: steps[i].title,
              body: steps[i].body,
            ),
            if (i < steps.length - 1) const SizedBox(height: 14),
          ],
          const SizedBox(height: 18),
          const InfoBanner.info(
            'L’échelle est essentielle : tant que le plan n’est pas calibré, '
            'les surfaces affichées sont approximatives (canvas de 12 m × 12 m).',
            title: 'Astuce calibrage',
            icon: Icons.straighten,
          ),
          const SizedBox(height: 12),
          const InfoBanner.success(
            'Vous pouvez tout annuler / rétablir avec les flèches ↶ ↷ en haut. '
            'Rien n’est définitif tant que vous n’avez pas exporté.',
            icon: Icons.undo,
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.check),
            label: const Text('J’ai compris, commencer'),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int number;
  final IconData icon;
  final String title;
  final String body;
  const _StepTile({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceAltColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight]),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text('$number',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: context.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.textSecondaryColor, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpStep {
  final IconData icon;
  final String title;
  final String body;
  const _HelpStep(this.icon, this.title, this.body);
}

const _roomSteps = <_HelpStep>[
  _HelpStep(
    Icons.add_box_outlined,
    'Ajoutez vos pièces',
    'Touchez une pièce dans la liste (Cuisine, Salon, Chambre…) : elle '
        'apparaît sur le plan. Besoin d’une forme particulière ? Utilisez '
        '« Tracer une pièce » pour la dessiner librement.',
  ),
  _HelpStep(
    Icons.open_with,
    'Déplacez et redimensionnez',
    'Glissez une pièce pour la positionner. Sélectionnez-la pour faire '
        'apparaître les poignées : tirez les coins pour ajuster la taille, '
        'et utilisez « Pivoter » si besoin. « Aligner les pièces » recolle '
        'automatiquement les coins voisins.',
  ),
  _HelpStep(
    Icons.straighten,
    'Calibrez l’échelle (important)',
    'Appuyez sur « Calibrer », touchez 2 points dont vous connaissez la '
        'distance réelle (ex. la longueur d’un mur), puis saisissez cette '
        'mesure en mètres. Tout le plan se met aussitôt aux bonnes '
        'dimensions — les m² sont alors exacts.',
  ),
  _HelpStep(
    Icons.ios_share,
    'Vérifiez puis exportez',
    'Les murs sont numérotés (M1, M2…) ; vous pouvez les renommer ou y '
        'ajouter des photos. Quand le plan vous convient, utilisez le bouton '
        'd’export pour générer un PDF prêt à joindre au dossier du bien.',
  ),
];

const _terrainSteps = <_HelpStep>[
  _HelpStep(
    Icons.home_outlined,
    'Placez les éléments du jardin',
    'Touchez les éléments (Maison, Garage, Terrasse, Piscine, Arbre…) pour '
        'les poser sur le terrain. Glissez-les ensuite à la bonne place.',
  ),
  _HelpStep(
    Icons.gesture,
    'Tracez les zones et clôtures',
    '« Tracer une zone » dessine une pelouse, une dalle… « Tracer une '
        'clôture / un mur » trace les limites, et « Placer un portail » '
        'ajoute l’accès.',
  ),
  _HelpStep(
    Icons.straighten,
    'Calibrez l’échelle (important)',
    'Appuyez sur « Calibrer », touchez 2 points de distance connue (ex. la '
        'largeur du portail), saisissez la mesure en mètres : tout le plan '
        'passe à la bonne échelle et les surfaces deviennent exactes.',
  ),
  _HelpStep(
    Icons.ios_share,
    'Vérifiez puis exportez',
    'Ajoutez si besoin des photos, vérifiez les distances, puis exportez le '
        'plan en PDF pour l’état des lieux ou le dossier du bien.',
  ),
];
