import 'package:flutter/material.dart';

import '../common/focus_style.dart';
import 'package:google_fonts/google_fonts.dart';

/// Child-friendly ("Kids mode") palette and [ThemeData].
///
/// A soft, colourful *light* theme — the opposite of the clinical dark research
/// theme — with a rounded, bubbly font (Nunito), large touch targets and big
/// text. Purely presentational: it never changes scoring, adaptation, or master
/// volume.
class KidsColors {
  KidsColors._();

  /// Soft sky-blue → mint-green background gradient (not dark navy).
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xffdcf1ff), Color(0xffe9fbef)],
  );

  static const Color primary = Color(0xff2fb1e0); // friendly blue
  static const Color secondary = Color(0xff43c98b); // grass green
  static const Color accent = Color(0xffffb23e); // sunny orange
  static const Color scaffold = Color(0xffeaf6ff);
  static const Color card = Colors.white;
  static const Color ink = Color(0xff274156); // soft dark blue-grey
  static const Color inkSoft = Color(0xff5b7488);
  static const Color border = Color(0xffbfe3f5);
}

/// A large emoji mascot shown in Kids mode (placeholder art).
const String kKidsMascot = '🦉';

/// Cheerful greeting shown in Kids mode instead of clinical language.
const String kKidsGreeting = 'Hi there! Ready to play?';

/// Reward stickers used in Kids mode in place of points / streak counters.
const List<String> kRewardStickers = <String>['⭐', '🌟', '🌈', '🏆'];

/// Returns a reward sticker for a 0-based [index], cycling through the set.
String kidsSticker(int index) =>
    kRewardStickers[index % kRewardStickers.length];

/// The rounded Nunito text theme for Kids mode, with a graceful fallback to the
/// default font when Google Fonts cannot be loaded (offline / tests) so the
/// theme never throws while building.
TextTheme _kidsTextTheme(ThemeData base, Color ink) {
  try {
    return GoogleFonts.nunitoTextTheme(base.textTheme)
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          headlineSmall: GoogleFonts.nunito(
              fontSize: 26, fontWeight: FontWeight.w800, color: ink),
          titleLarge: GoogleFonts.nunito(
              fontSize: 22, fontWeight: FontWeight.w800, color: ink),
          bodyLarge: GoogleFonts.nunito(
              fontSize: 18, fontWeight: FontWeight.w600, color: ink),
          bodyMedium: GoogleFonts.nunito(
              fontSize: 16, fontWeight: FontWeight.w600, color: ink),
          labelLarge: GoogleFonts.nunito(
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        );
  } catch (_) {
    return base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
          headlineSmall:
              TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink),
          titleLarge:
              TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink),
          bodyLarge:
              TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ink),
          bodyMedium:
              TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: ink),
          labelLarge: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
        );
  }
}

/// Builds the child-friendly light [ThemeData].
///
/// Uses a rounded Nunito text theme, larger default text, big rounded buttons
/// and a bright light surface. [highContrast] slightly darkens text for
/// legibility; it never affects scoring.
ThemeData buildKidsTheme({bool highContrast = false}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: KidsColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: KidsColors.primary,
    secondary: KidsColors.secondary,
    surface: KidsColors.card,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: KidsColors.scaffold,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  final Color ink = highContrast ? const Color(0xff11222e) : KidsColors.ink;

  // Nunito is a rounded, friendly font. Scale everything up a little and make
  // it bold for a "bubbly" feel. Falls back to the default font when Google
  // Fonts is unavailable (offline / tests) so the theme never fails to build.
  final text = _kidsTextTheme(base, ink);

  RoundedRectangleBorder rounded([double r = 22]) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));

  return base.copyWith(
    textTheme: text,
    focusColor: kFocusHighlight,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      color: KidsColors.card,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: rounded(24),
      shadowColor: KidsColors.primary.withValues(alpha: 0.2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
        shape: rounded(),
        textStyle: text.labelLarge,
        backgroundColor: KidsColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(64, 60),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        shape: rounded(),
        backgroundColor: KidsColors.secondary,
        foregroundColor: Colors.white,
        textStyle: text.labelLarge,
        minimumSize: const Size(64, 60),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
        shape: rounded(),
        side: const BorderSide(color: KidsColors.primary, width: 2),
        foregroundColor: KidsColors.primary,
        minimumSize: const Size(64, 56),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: KidsColors.border, width: 1.5),
      labelStyle: text.labelMedium?.copyWith(color: ink),
      shape: rounded(14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: rounded(24),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: KidsColors.primary,
      contentTextStyle:
          text.bodyMedium?.copyWith(color: Colors.white, fontSize: 16),
      shape: rounded(16),
    ),
    dividerTheme: const DividerThemeData(
      color: KidsColors.border,
      thickness: 1.5,
      space: 1.5,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: KidsColors.primary,
      linearTrackColor: Color(0xffd6ecf7),
    ),
    iconTheme: const IconThemeData(color: KidsColors.primary, size: 28),
    listTileTheme: const ListTileThemeData(
      iconColor: KidsColors.primary,
      textColor: KidsColors.ink,
    ),
  );
}
