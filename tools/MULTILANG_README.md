# Multi-language demo speech assets

**Run this script to generate non-English speech assets** for the Hindi, Tamil,
Telugu and Kannada word pools that the app's `LanguageConfig` framework already
declares (`apps/flutter_app/lib/core/i18n/language_config.dart`).

```bash
pip install edge-tts miniaudio
python tools/generate_multilang.py            # all four languages
python tools/generate_multilang.py --langs hi # just Hindi
```

- Word pools (10 words per language) live in `tools/multilang_words.json` — edit
  the words or the per-language `voice` there, then re-run.
- Output: `apps/flutter_app/assets/stimuli/<lang>/word_<roman>.wav` plus a
  per-language `manifest.json`.
- After generating, register the new folders in `apps/flutter_app/pubspec.yaml`
  under `flutter: assets:` (e.g. `- assets/stimuli/hi/`) so they are bundled.

These are **demonstration voices (`demo_only`)** produced by edge-tts — they are
**not validated clinical stimuli** and must not be used for diagnosis.
