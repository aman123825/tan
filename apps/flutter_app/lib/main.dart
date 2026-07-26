import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/settings/app_settings.dart';
import 'features/common/focus_style.dart';
import 'features/common/playback_controls.dart';
import 'features/home/home_page.dart';
import 'features/kids/kids_theme.dart';
import 'features/onboarding/onboarding_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load persisted accessibility preferences before first paint so text-size
  // and high-contrast take effect immediately. Failures fall back to defaults.
  await loadAppSettings();
  // Load manual playback preferences (speed / channel) before first paint.
  await loadPlaybackPrefs();
  // First launch shows the onboarding tour; afterwards go straight to home.
  // A `?preview=` deep link always bypasses onboarding (dev/screenshot tool).
  var onboardingComplete = false;
  try {
    onboardingComplete = await OnboardingStore().isComplete();
  } catch (_) {
    // Storage unavailable → fall back to showing the tour.
  }
  final hasPreview =
      (Uri.base.queryParameters['preview'] ?? '').isNotEmpty;
  runApp(HearBloomApp(showOnboarding: !onboardingComplete && !hasPreview));
}

/// Premium brand palette with depth — designed for glassmorphism.
class HearBloomColors {
  // Core brand
  static const Color seed = Color(0xff246bce);
  static const Color primary = Color(0xff3b82f6);
  static const Color primaryGlow = Color(0x553b82f6);
  static const Color secondary = Color(0xff8b5cf6);
  static const Color accent = Color(0xff06b6d4);

  // Surfaces — glassmorphic
  static const Color background = Color(0xff0f172a); // deep navy
  static const Color surface = Color(0x1affffff); // frosted glass base
  static const Color surfaceSolid = Color(0xff1e293b); // solid dark surface
  static const Color card = Color(0x26ffffff); // glass card
  static const Color border = Color(0x33ffffff); // subtle glass border
  static const Color borderGlow = Color(0x553b82f6); // glow border

  // Text
  static const Color ink = Color(0xfff1f5f9);
  static const Color inkSoft = Color(0xff94a3b8);
  static const Color inkMuted = Color(0xff8b9bb4);

  // Semantic
  static const Color good = Color(0xff22c55e);
  static const Color info = Color(0xff06b6d4);
  static const Color warn = Color(0xfffbbf24);
  static const Color bad = Color(0xffef4444);

  // Gradients
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff1e3a5f), Color(0xff0f172a), Color(0xff1a1033)],
  );

  static const LinearGradient glassGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x1affffff), Color(0x0dffffff)],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff3b82f6), Color(0xff8b5cf6)],
  );
}

/// Frosted glass container decoration.
BoxDecoration glassDecoration({
  double borderRadius = 20,
  Color? borderColor,
  double opacity = 0.12,
}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(opacity),
          Colors.white.withOpacity(opacity * 0.5),
        ],
      ),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderColor ?? HearBloomColors.border,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: HearBloomColors.primaryGlow,
          blurRadius: 40,
          offset: const Offset(0, 4),
          spreadRadius: -10,
        ),
      ],
    );

/// Smooth page route with fade + scale transition.
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  FadeScaleRoute({required WidgetBuilder builder})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        );
}

class HearBloomApp extends StatelessWidget {
  const HearBloomApp({super.key, this.showOnboarding = false});

  /// When true, the first screen is the onboarding tour (first launch).
  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    // Rebuild the app whenever accessibility settings change so high-contrast
    // and text-size take effect immediately.
    return ValueListenableBuilder<AppSettings>(
      valueListenable: appSettings,
      builder: (context, settings, _) => _buildApp(settings),
    );
  }

  Widget _buildApp(AppSettings settings) {
    // High-contrast mode brightens text and borders for legibility. It is a
    // presentation-only setting — it never affects scoring or master volume.
    final bool hc = settings.highContrast;
    final Color ink = hc ? const Color(0xffffffff) : HearBloomColors.ink;
    final Color inkSoft =
        hc ? const Color(0xffe2e8f0) : HearBloomColors.inkSoft;
    final Color border =
        hc ? const Color(0x66ffffff) : HearBloomColors.border;

    final scheme = ColorScheme.fromSeed(
      seedColor: HearBloomColors.seed,
      brightness: Brightness.dark,
    ).copyWith(
      surface: HearBloomColors.surfaceSolid,
      primary: HearBloomColors.primary,
      secondary: HearBloomColors.secondary,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: HearBloomColors.background,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    // Lite mode (L8): system font stack — skips the web-font download and
    // its layout shift on slow connections/low-end devices.
    final text = (settings.liteMode
            ? base.textTheme
            : GoogleFonts.interTextTheme(base.textTheme))
        .apply(
      bodyColor: ink,
      displayColor: ink,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HearBloom Research',
      builder: (context, child) {
        // Apply the app-wide text-size preference via a TextScaler.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(settings.textSize.scale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: settings.themeChoice == ThemeChoice.kids
          ? buildKidsTheme(highContrast: hc)
          : settings.themeChoice == ThemeChoice.light
              ? buildLightTheme(highContrast: hc)
              : base.copyWith(
        textTheme: text,
        // WCAG 2.4.7: keyboard focus visibly highlights every InkWell-based
        // control (choice tiles, transports, dots) app-wide.
        focusColor: kFocusHighlight,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: text.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: HearBloomColors.card,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            backgroundColor: HearBloomColors.primary,
            foregroundColor: Colors.white,
          ).copyWith(side: focusOutline()),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            backgroundColor: HearBloomColors.surfaceSolid,
            foregroundColor: ink,
          ).copyWith(side: focusOutline()),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            side: BorderSide(color: border),
            foregroundColor: ink,
          ).copyWith(side: focusOutline(base: BorderSide(color: border))),
        ),
        textButtonTheme: TextButtonThemeData(
          style: const ButtonStyle().copyWith(side: focusOutline()),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: HearBloomColors.card,
          side: BorderSide(color: border),
          labelStyle: text.labelMedium?.copyWith(color: ink),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: HearBloomColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          labelStyle: TextStyle(color: inkSoft),
          hintStyle: const TextStyle(color: HearBloomColors.inkMuted),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: HearBloomColors.surfaceSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: HearBloomColors.surfaceSolid,
          modalBackgroundColor: HearBloomColors.surfaceSolid,
        ),
        dividerTheme: DividerThemeData(
          color: border,
          thickness: 1,
          space: 1,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: HearBloomColors.surfaceSolid,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        listTileTheme: ListTileThemeData(
          iconColor: inkSoft,
          textColor: ink,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: HearBloomColors.primary,
          linearTrackColor: Color(0x33ffffff),
        ),
        iconTheme: IconThemeData(color: ink),
      ),
      home: showOnboarding ? const OnboardingPage() : const HomePage(),
    );
  }
}



/// Builds the full Material 3 *light* theme (white background, dark text, blue
/// accents). A presentation-only alternative to the dark glassmorphic theme;
/// it never affects scoring, adaptation or master volume. [highContrast]
/// deepens text/borders for legibility.
ThemeData buildLightTheme({bool highContrast = false}) {
  final Color ink = highContrast ? const Color(0xff000000) : const Color(0xff0f172a);
  final Color inkSoft =
      highContrast ? const Color(0xff1e293b) : const Color(0xff475569);
  final Color border =
      highContrast ? const Color(0xff94a3b8) : const Color(0xffcbd5e1);
  const Color surface = Color(0xffffffff);
  const Color scaffold = Color(0xfff1f5f9);

  final scheme = ColorScheme.fromSeed(
    seedColor: HearBloomColors.seed,
    brightness: Brightness.light,
  ).copyWith(
    surface: surface,
    primary: HearBloomColors.primary,
    secondary: HearBloomColors.secondary,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scaffold,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  final text = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: ink,
    displayColor: ink,
  );

  return base.copyWith(
    textTheme: text,
    focusColor: kFocusHighlight,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        backgroundColor: HearBloomColors.primary,
        foregroundColor: Colors.white,
      ).copyWith(side: focusOutline()),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        backgroundColor: Colors.white,
        foregroundColor: ink,
        side: BorderSide(color: border),
      ).copyWith(side: focusOutline(base: BorderSide(color: border))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        side: BorderSide(color: border),
        foregroundColor: HearBloomColors.primary,
      ).copyWith(side: focusOutline(base: BorderSide(color: border))),
    ),
    textButtonTheme: TextButtonThemeData(
      style: const ButtonStyle().copyWith(side: focusOutline()),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: BorderSide(color: border),
      labelStyle: text.labelMedium?.copyWith(color: ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: inkSoft),
      hintStyle: const TextStyle(color: Color(0xff94a3b8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      modalBackgroundColor: Colors.white,
    ),
    dividerTheme: DividerThemeData(
      color: border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xff1e293b),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: inkSoft,
      textColor: ink,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: HearBloomColors.primary,
      linearTrackColor: Color(0xffe2e8f0),
    ),
    iconTheme: IconThemeData(color: ink),
  );
}
