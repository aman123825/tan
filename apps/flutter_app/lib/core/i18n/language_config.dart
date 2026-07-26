import 'package:shared_preferences/shared_preferences.dart';

/// A single common word in a supported language, carrying the native-script
/// form, a romanized transliteration, and the English gloss.
///
/// The romanization lets the (English-first) research UI show a readable
/// fallback, while [native] is what a future generated-speech pipeline would
/// synthesise.
class LanguageWord {
  const LanguageWord({
    required this.native,
    required this.roman,
    required this.english,
  });

  /// Native-script spelling (e.g. Devanagari, Tamil, Telugu, Kannada).
  final String native;

  /// Latin-script transliteration (e.g. "paani").
  final String roman;

  /// English gloss (e.g. "water").
  final String english;
}

/// Configuration for one supported language: its code, display names, the
/// asset-folder prefix where generated speech WAVs would live, and a small
/// pool of common words used by recognition tasks.
///
/// NOTE: the actual per-language speech WAV generation is a separate step
/// (`tools/generate_speech_words.py`). This class only defines the pools and
/// wiring so the app can select a language today; audio for non-English
/// languages is not bundled yet.
class LanguageConfig {
  const LanguageConfig({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.speechAssetPrefix,
    required this.wordPool,
  });

  /// BCP-47-style code, e.g. `en-IN`, `hi-IN`, `ta-IN`, `te-IN`, `kn-IN`.
  final String code;

  /// English display name, e.g. "Hindi".
  final String name;

  /// Endonym / native display name, e.g. "हिन्दी".
  final String nativeName;

  /// Asset folder prefix for this language's generated speech, e.g.
  /// `assets/stimuli/hi`. The English demo assets live under the existing
  /// `assets/stimuli/...` folders (prefix `assets/stimuli/en`).
  final String speechAssetPrefix;

  /// Common-word pool for recognition/closure tasks (10 words per language).
  final List<LanguageWord> wordPool;

  /// Whether generated speech assets are actually bundled for this language.
  /// Only English (`en-IN`) ships demo audio today; the others are configured
  /// but await `tools/generate_speech_words.py`.
  bool get hasBundledSpeech => code == 'en-IN';

  @override
  String toString() => 'LanguageConfig($code)';
}

/// Indian English — the default. Uses the existing bundled demo speech.
const LanguageConfig kEnglishIndia = LanguageConfig(
  code: 'en-IN',
  name: 'English (India)',
  nativeName: 'English',
  speechAssetPrefix: 'assets/stimuli/en',
  wordPool: <LanguageWord>[
    LanguageWord(native: 'water', roman: 'water', english: 'water'),
    LanguageWord(native: 'food', roman: 'food', english: 'food'),
    LanguageWord(native: 'mother', roman: 'mother', english: 'mother'),
    LanguageWord(native: 'father', roman: 'father', english: 'father'),
    LanguageWord(native: 'house', roman: 'house', english: 'house'),
    LanguageWord(native: 'book', roman: 'book', english: 'book'),
    LanguageWord(native: 'hand', roman: 'hand', english: 'hand'),
    LanguageWord(native: 'eye', roman: 'eye', english: 'eye'),
    LanguageWord(native: 'sun', roman: 'sun', english: 'sun'),
    LanguageWord(native: 'moon', roman: 'moon', english: 'moon'),
  ],
);

/// Hindi (Devanagari) common-word pool.
const LanguageConfig kHindi = LanguageConfig(
  code: 'hi-IN',
  name: 'Hindi',
  nativeName: 'हिन्दी',
  speechAssetPrefix: 'assets/stimuli/hi',
  wordPool: <LanguageWord>[
    LanguageWord(native: 'पानी', roman: 'paani', english: 'water'),
    LanguageWord(native: 'खाना', roman: 'khaana', english: 'food'),
    LanguageWord(native: 'माता', roman: 'maata', english: 'mother'),
    LanguageWord(native: 'पिता', roman: 'pita', english: 'father'),
    LanguageWord(native: 'घर', roman: 'ghar', english: 'house'),
    LanguageWord(native: 'किताब', roman: 'kitaab', english: 'book'),
    LanguageWord(native: 'हाथ', roman: 'haath', english: 'hand'),
    LanguageWord(native: 'आँख', roman: 'aankh', english: 'eye'),
    LanguageWord(native: 'सूरज', roman: 'sooraj', english: 'sun'),
    LanguageWord(native: 'चाँद', roman: 'chaand', english: 'moon'),
  ],
);

/// Tamil common-word pool.
const LanguageConfig kTamil = LanguageConfig(
  code: 'ta-IN',
  name: 'Tamil',
  nativeName: 'தமிழ்',
  speechAssetPrefix: 'assets/stimuli/ta',
  wordPool: <LanguageWord>[
    LanguageWord(native: 'தண்ணீர்', roman: 'thanneer', english: 'water'),
    LanguageWord(native: 'உணவு', roman: 'unavu', english: 'food'),
    LanguageWord(native: 'அம்மா', roman: 'amma', english: 'mother'),
    LanguageWord(native: 'அப்பா', roman: 'appa', english: 'father'),
    LanguageWord(native: 'வீடு', roman: 'veedu', english: 'house'),
    LanguageWord(native: 'புத்தகம்', roman: 'puthagam', english: 'book'),
    LanguageWord(native: 'கை', roman: 'kai', english: 'hand'),
    LanguageWord(native: 'கண்', roman: 'kan', english: 'eye'),
    LanguageWord(native: 'சூரியன்', roman: 'sooriyan', english: 'sun'),
    LanguageWord(native: 'நிலா', roman: 'nila', english: 'moon'),
  ],
);

/// Telugu common-word pool.
const LanguageConfig kTelugu = LanguageConfig(
  code: 'te-IN',
  name: 'Telugu',
  nativeName: 'తెలుగు',
  speechAssetPrefix: 'assets/stimuli/te',
  wordPool: <LanguageWord>[
    LanguageWord(native: 'నీరు', roman: 'neeru', english: 'water'),
    LanguageWord(native: 'ఆహారం', roman: 'aahaaram', english: 'food'),
    LanguageWord(native: 'అమ్మ', roman: 'amma', english: 'mother'),
    LanguageWord(native: 'నాన్న', roman: 'nanna', english: 'father'),
    LanguageWord(native: 'ఇల్లు', roman: 'illu', english: 'house'),
    LanguageWord(native: 'పుస్తకం', roman: 'pustakam', english: 'book'),
    LanguageWord(native: 'చెయ్యి', roman: 'cheyyi', english: 'hand'),
    LanguageWord(native: 'కన్ను', roman: 'kannu', english: 'eye'),
    LanguageWord(native: 'సూర్యుడు', roman: 'sooryudu', english: 'sun'),
    LanguageWord(native: 'చంద్రుడు', roman: 'chandrudu', english: 'moon'),
  ],
);

/// Kannada common-word pool.
const LanguageConfig kKannada = LanguageConfig(
  code: 'kn-IN',
  name: 'Kannada',
  nativeName: 'ಕನ್ನಡ',
  speechAssetPrefix: 'assets/stimuli/kn',
  wordPool: <LanguageWord>[
    LanguageWord(native: 'ನೀರು', roman: 'neeru', english: 'water'),
    LanguageWord(native: 'ಆಹಾರ', roman: 'aahaara', english: 'food'),
    LanguageWord(native: 'ಅಮ್ಮ', roman: 'amma', english: 'mother'),
    LanguageWord(native: 'ಅಪ್ಪ', roman: 'appa', english: 'father'),
    LanguageWord(native: 'ಮನೆ', roman: 'mane', english: 'house'),
    LanguageWord(native: 'ಪುಸ್ತಕ', roman: 'pustaka', english: 'book'),
    LanguageWord(native: 'ಕೈ', roman: 'kai', english: 'hand'),
    LanguageWord(native: 'ಕಣ್ಣು', roman: 'kannu', english: 'eye'),
    LanguageWord(native: 'ಸೂರ್ಯ', roman: 'soorya', english: 'sun'),
    LanguageWord(native: 'ಚಂದ್ರ', roman: 'chandra', english: 'moon'),
  ],
);

/// All supported languages, English first (the default).
const List<LanguageConfig> kSupportedLanguages = <LanguageConfig>[
  kEnglishIndia,
  kHindi,
  kTamil,
  kTelugu,
  kKannada,
];

/// The default language code when none has been chosen.
const String kDefaultLanguageCode = 'en-IN';

/// Looks up a [LanguageConfig] by [code], falling back to English if the code
/// is unknown.
LanguageConfig languageByCode(String? code) {
  for (final lang in kSupportedLanguages) {
    if (lang.code == code) return lang;
  }
  return kEnglishIndia;
}

/// Persists the selected UI/stimulus language code in SharedPreferences.
///
/// This is a small, self-contained seam: selecting a language only records the
/// preference today. Wiring the choice into the generated-speech pipeline is a
/// separate content step.
class LanguageStore {
  LanguageStore({this.key = 'hearbloom.language.v1'});

  final String key;

  /// Loads the saved language code, defaulting to [kDefaultLanguageCode].
  Future<String> loadCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key) ?? kDefaultLanguageCode;
  }

  /// Loads the saved [LanguageConfig] (never null; defaults to English).
  Future<LanguageConfig> load() async => languageByCode(await loadCode());

  /// Saves [code]. Unknown codes are coerced to English's code so the store
  /// never persists an invalid value.
  Future<void> save(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, languageByCode(code).code);
  }
}
