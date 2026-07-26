import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-selectable text size. Applied app-wide via a [TextScaler] at the root.
/// The top step reaches 200% for WCAG 2.2 SC 1.4.4 (resize text).
enum TextSizePreference { small, medium, large, extraLarge, huge }

extension TextSizePreferenceInfo on TextSizePreference {
  /// Multiplicative text-scale factor applied to the whole app.
  double get scale => switch (this) {
        TextSizePreference.small => 0.9,
        TextSizePreference.medium => 1.0,
        TextSizePreference.large => 1.2,
        TextSizePreference.extraLarge => 1.5,
        TextSizePreference.huge => 2.0,
      };

  /// Human-readable label for the settings UI.
  String get label => switch (this) {
        TextSizePreference.small => 'Small',
        TextSizePreference.medium => 'Medium',
        TextSizePreference.large => 'Large',
        TextSizePreference.extraLarge => 'XL (150%)',
        TextSizePreference.huge => 'XXL (200%)',
      };

  /// Stable string used for persistence.
  String get storageKey => name;

  static TextSizePreference fromStorage(String? value) {
    for (final v in TextSizePreference.values) {
      if (v.name == value) return v;
    }
    return TextSizePreference.medium;
  }
}

/// The three selectable app themes.
///
///  * [dark] — the default deep-navy glassmorphic research theme.
///  * [light] — a clean Material 3 light scheme (white background, dark text).
///  * [kids] — a soft, colourful child-friendly theme with rounded fonts.
enum ThemeChoice { dark, light, kids }

extension ThemeChoiceInfo on ThemeChoice {
  /// Human-readable label for the settings UI.
  String get label => switch (this) {
        ThemeChoice.dark => 'Dark',
        ThemeChoice.light => 'Light',
        ThemeChoice.kids => 'Kids',
      };

  /// Stable string used for persistence.
  String get storageKey => name;

  static ThemeChoice fromStorage(String? value) {
    for (final v in ThemeChoice.values) {
      if (v.name == value) return v;
    }
    return ThemeChoice.dark;
  }
}

/// Immutable snapshot of user accessibility / presentation preferences.
///
/// Purely presentational: none of these settings ever affect scoring,
/// adaptation, or master volume.
@immutable
class AppSettings {
  const AppSettings({
    this.highContrast = false,
    this.textSize = TextSizePreference.medium,
    this.themeChoice = ThemeChoice.dark,
    this.reducedMotion = false,
    this.showSpectrogram = false,
    this.showStimulusText = false,
    this.liteMode = false,
    this.listenerAgeYears = 30,
  });

  /// When on, borders and text are rendered at higher opacity for legibility.
  final bool highContrast;

  /// Selected app-wide text size.
  final TextSizePreference textSize;

  /// Selected app theme (dark / light / kids).
  final ThemeChoice themeChoice;

  /// When on, decorative animations are skipped (pulses, countdown fills, etc.)
  /// for listeners who prefer reduced motion.
  final bool reducedMotion;

  /// When on, trial pages may show an optional scrolling-spectrogram panel.
  final bool showSpectrogram;

  /// When on, trial pages reveal the stimulus text (a caption) AFTER the
  /// response is submitted — a comprehension aid (WCAG "show text") that can
  /// never leak the answer before it is given.
  final bool showStimulusText;

  /// Lite visuals for low-end devices / slow connections: system fonts
  /// (skips the web font download) and all decorative animation off. Never
  /// affects scoring, adaptation or master volume.
  final bool liteMode;

  /// Listener age in whole years, used ONLY to pick the age band for the
  /// research-only normative interpretation (report + norm tiles). Never
  /// affects scoring, adaptation or master volume.
  final int listenerAgeYears;

  /// Convenience: whether the child-friendly Kids theme is active.
  bool get kidsMode => themeChoice == ThemeChoice.kids;

  AppSettings copyWith({
    bool? highContrast,
    TextSizePreference? textSize,
    ThemeChoice? themeChoice,
    bool? reducedMotion,
    bool? showSpectrogram,
    bool? showStimulusText,
    bool? liteMode,
    int? listenerAgeYears,
  }) =>
      AppSettings(
        highContrast: highContrast ?? this.highContrast,
        textSize: textSize ?? this.textSize,
        themeChoice: themeChoice ?? this.themeChoice,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        showSpectrogram: showSpectrogram ?? this.showSpectrogram,
        showStimulusText: showStimulusText ?? this.showStimulusText,
        liteMode: liteMode ?? this.liteMode,
        listenerAgeYears: listenerAgeYears ?? this.listenerAgeYears,
      );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.highContrast == highContrast &&
      other.textSize == textSize &&
      other.themeChoice == themeChoice &&
      other.reducedMotion == reducedMotion &&
      other.showSpectrogram == showSpectrogram &&
      other.showStimulusText == showStimulusText &&
      other.liteMode == liteMode &&
      other.listenerAgeYears == listenerAgeYears;

  @override
  int get hashCode => Object.hash(
        highContrast,
        textSize,
        themeChoice,
        reducedMotion,
        showSpectrogram,
        showStimulusText,
        liteMode,
        listenerAgeYears,
      );
}

/// Global, listenable presentation settings. The app root rebuilds when this
/// changes so the theme, text-scaling and high-contrast take effect
/// immediately.
///
/// Purely presentational: these settings never affect scoring, adaptation, or
/// master volume.
final ValueNotifier<AppSettings> appSettings =
    ValueNotifier<AppSettings>(const AppSettings());

/// Whether decorative motion should be suppressed for the current context.
///
/// True when the user enabled our "reduced motion" preference OR the platform
/// requested disabled animations (`MediaQuery.disableAnimations`). Decorative
/// widgets (countdown ring, pulsing dots, wave animation) consult this so a
/// single toggle quiets them everywhere.
bool reduceMotionActive(BuildContext context) {
  // Lite mode implies reduced motion (its whole point is less work).
  if (appSettings.value.reducedMotion || appSettings.value.liteMode) {
    return true;
  }
  return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Loads persisted settings into [appSettings]. Call once at startup (after
/// `WidgetsFlutterBinding.ensureInitialized`). Failures fall back to defaults.
Future<void> loadAppSettings([AppSettingsStore? store]) async {
  try {
    appSettings.value = await (store ?? AppSettingsStore()).load();
  } catch (_) {
    appSettings.value = const AppSettings();
  }
}

/// SharedPreferences-backed persistence for [AppSettings].
class AppSettingsStore {
  AppSettingsStore({this.prefix = 'hearbloom.a11y.v1'});

  final String prefix;

  String get _contrastKey => '$prefix.high_contrast';
  String get _textSizeKey => '$prefix.text_size';
  String get _themeKey => '$prefix.theme_choice';
  String get _reducedMotionKey => '$prefix.reduced_motion';
  String get _spectrogramKey => '$prefix.show_spectrogram';
  String get _stimulusTextKey => '$prefix.show_stimulus_text';
  String get _liteModeKey => '$prefix.lite_mode';
  String get _ageKey => '$prefix.listener_age_years';

  /// Literal `kids_mode` flag kept in sync with [ThemeChoice.kids] so a simple
  /// boolean lookup remains available (and for backward compatibility).
  static const String kidsModeKey = 'kids_mode';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Prefer the explicit theme choice; otherwise fall back to the legacy
    // kids_mode boolean so an earlier install keeps Kids mode.
    final storedTheme = prefs.getString(_themeKey);
    ThemeChoice theme;
    if (storedTheme != null) {
      theme = ThemeChoiceInfo.fromStorage(storedTheme);
    } else if (prefs.getBool(kidsModeKey) ?? false) {
      theme = ThemeChoice.kids;
    } else {
      theme = ThemeChoice.dark;
    }
    return AppSettings(
      highContrast: prefs.getBool(_contrastKey) ?? false,
      textSize:
          TextSizePreferenceInfo.fromStorage(prefs.getString(_textSizeKey)),
      themeChoice: theme,
      reducedMotion: prefs.getBool(_reducedMotionKey) ?? false,
      showSpectrogram: prefs.getBool(_spectrogramKey) ?? false,
      showStimulusText: prefs.getBool(_stimulusTextKey) ?? false,
      liteMode: prefs.getBool(_liteModeKey) ?? false,
      listenerAgeYears: (prefs.getInt(_ageKey) ?? 30).clamp(4, 110),
    );
  }

  Future<void> setHighContrast(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_contrastKey, value);
    appSettings.value = appSettings.value.copyWith(highContrast: value);
  }

  Future<void> setTextSize(TextSizePreference value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_textSizeKey, value.storageKey);
    appSettings.value = appSettings.value.copyWith(textSize: value);
  }

  Future<void> setThemeChoice(ThemeChoice value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, value.storageKey);
    // Keep the literal kids_mode flag in sync.
    await prefs.setBool(kidsModeKey, value == ThemeChoice.kids);
    appSettings.value = appSettings.value.copyWith(themeChoice: value);
  }

  /// Toggles Kids mode on/off. On → [ThemeChoice.kids]; off → [ThemeChoice.dark].
  Future<void> setKidsMode(bool value) =>
      setThemeChoice(value ? ThemeChoice.kids : ThemeChoice.dark);

  Future<void> setReducedMotion(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reducedMotionKey, value);
    appSettings.value = appSettings.value.copyWith(reducedMotion: value);
  }

  Future<void> setShowSpectrogram(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_spectrogramKey, value);
    appSettings.value = appSettings.value.copyWith(showSpectrogram: value);
  }

  Future<void> setShowStimulusText(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_stimulusTextKey, value);
    appSettings.value = appSettings.value.copyWith(showStimulusText: value);
  }

  Future<void> setLiteMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_liteModeKey, value);
    appSettings.value = appSettings.value.copyWith(liteMode: value);
  }

  Future<void> setListenerAge(int years) async {
    final clamped = years.clamp(4, 110);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ageKey, clamped);
    appSettings.value = appSettings.value.copyWith(listenerAgeYears: clamped);
  }
}
