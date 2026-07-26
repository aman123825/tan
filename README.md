# HearBloom Whole-System Research Source

A non-diagnostic, protocol-driven auditory-training research system for ANSD/CAPD product development. This repository contains all source layers required for Kiro/Claude-assisted continuation.

## Included
- Flutter source for Windows, macOS, Linux, Android and iOS
- Nine-module protocol catalog with 64 configurations (56 explicit + 8 Telephone inherited)
- Deterministic adaptive protocol engine
- Indian-English generated-voice pipeline
- Psychoacoustic WAV generator: tones, noise, gaps, modulation and melodic contours
- FastAPI backend with SQLite persistence
- Explainable local AI recommender
- Patient/listening-condition/session/trial schemas
- Safety restrictions for ANSD-oriented research use
- Automated Python tests
- Docker configuration

## Important
This is research-development source, not a medical device and not a diagnosis or treatment. Generated voices are demonstrations, not validated clinical stimuli. Do not use home audio output for absolute dB HL measurements.

## Quick start: backend
```bash
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
python tools/generate_stimuli.py --output stimuli/demo
uvicorn services.api.main:app --reload
```

API: http://127.0.0.1:8000/docs

## Flutter client
Install Flutter, then:
```bash
cd apps/flutter_app
flutter create . --platforms=windows,macos,linux,android,ios,web
flutter pub get
flutter run -d windows
```

The `flutter create .` command adds platform runner files without replacing `lib/` or `pubspec.yaml`.

## Run the app (one command)

Build the Flutter web app and serve it locally:
```bash
# Windows
pwsh tools/run_app.ps1             # then open http://127.0.0.1:8080
# macOS / Linux
bash tools/run_app.sh
```
Options: `-Port 9000` / first arg to pick a port; `-NoBuild` (Windows) or `NOBUILD=1` (bash) to serve an existing build immediately. Set `HEARBLOOM_FLUTTER` to the `flutter` executable if it is not on `PATH`. This serves the research web build — not a medical device and not for diagnosis. For a native desktop window use `flutter run -d windows` (requires the Visual Studio "Desktop development with C++" workload).

## Implemented (verified)
- Catalog-driven UI (typed Dart models) with validation-status surfaced on every group.
- Five-stage workflow per protocol: Introduction → Preview → Training → Test → Results.
- Comfortable-level check with locked master volume (no in-test volume change; wrong answers never raise volume).
- Renderers with real audio: adaptive speech-in-noise (4AFC, real word-in-noise — Indian-English demo speech decoded and mixed with noise at the adaptive SNR; all six speech-in-noise groups), typed open-set word recognition (type what you heard, normalized scoring), temporal gap detection (3AFC), amplitude-modulation detection (3AFC), modulation-rate discrimination (3AFC oddball), pitch / frequency-JND discrimination (3AFC oddball, synthesized tones), loudness/level discrimination (3AFC), tone detection incl. forward masking (3AFC, research-only, not a dB HL test), rhythm discrimination (3AFC odd-one-out), chord identification (Major/Minor/Diminished/Augmented, additive synthesis), melodic contour identification (9-choice, shipped contour assets), melody recall (synthesized note sequence, tap-to-recall), and digit-span sequence entry.
- Every adaptive interval task shares one deterministic engine and one generic renderer (`IntervalTaskPage`), keeping adaptation in the locked staircase and never touching master volume.
- Closed-set identification (generic renderer): everyday word, number, letter, and phoneme-contrast recognition (spoken `demo_only` items, choose from a closed set). **Word recognition runs in adaptive noise** — the babble SNR tracks the listener 2-down/1-up and a research-only SNR threshold + normative interpretation is reported — while the other sets run quiet or at a fixed SNR. Also color identification (spoken color → tap the matching swatch).
- Open-set recognition: typed word, sentence, and runtime-concatenated matrix-sentence recognition (word-accuracy scoring), plus CNC word lists.
- Identification (generic renderer): synthesized instrument identification and instrument sequences (additive timbres), familiar-melody identification (public-domain tunes, synthesized), environmental-sound identification (synthesized sound effects), speaker/talker identification (multiple generated voices), and food/animal picture identification (emoji pictures with a generated spoken label).
- Composite assessment batteries (`BatteryRunnerPage`): resolution, music, cognition, speech-in-noise, recognition-threshold, phoneme, and a music-appreciation sampler run their sub-tests in sequence and show a combined summary; each sub-test is still stored separately with its own reliability.
- Content is generated Indian-English (`en-IN`, edge-tts) `demo_only` demonstration speech plus fully synthesized tones/timbres/effects — regenerate speech with `python tools/generate_speech_words.py` and `python tools/generate_demo_assets.py` (digits/letters/phonemes/words/sentences/matrix/colors/food/animals/speaker). Not validated clinical stimuli.
- Dichotic digits (`auditory/dichotic_digits`): a different digit is presented to each ear at once (stereo, wired headphones required) and the listener reports the cued ear; results are tracked per ear (left/right).
- Optional post-session fatigue self-report (0–10) recorded as the session's `fatigue_after`: informational only — it never changes the locked scoring or master volume — and the explainable recommender may use it to suggest a shorter/easier next block. "Fatigue is not failure."
- Optional speech-to-text answer assistance for open-set tasks is a pluggable, correctable seam (`AsrProvider`), disabled by default (no model or network bundled). When a provider is supplied it shows a microphone that only *pre-fills* the answer field; the listener always edits/confirms and presses Submit — ASR never auto-submits or scores. Plugging in a concrete on-device engine is a product/platform decision.
- Coverage: all 56 explicit catalog groups now have a working renderer. Where a group would normally use recorded content, the app ships a clearly-labeled demonstration instead (synthesized instruments/effects/melodies, multiple generated voices, emoji pictures with generated speech) and surfaces each group's validation status. None of these are validated clinical stimuli; replacing the demos with reviewed recordings/images is the remaining research/content work.
- Generated speech is Indian-English (`en-IN`, edge-tts) demonstration material (`demo_only`), not validated clinical stimuli; regenerate with `python tools/generate_speech_words.py`. The SNR mix adapts speech-to-noise ratio and never master volume.
- Accessibility: interactive controls carry Semantics labels (verified with `find.bySemanticsLabel`).
- Results are separated per condition/output-device with reliability and an accuracy-by-condition chart (fl_chart).
- Research-only normative interpretation: each measured threshold is situated against published reference data with inline citations — gaps-in-noise ≤ 6 ms (Musiek et al., 2005), frequency difference limen (Wier, Jesteadt & Green, 1977), amplitude-modulation TMTF −20…−26 dB (Viemeister, 1979; Bacon & Viemeister, 1985), QuickSIN SNR-loss bands (Killion et al., 2004) and dichotic digits ≥ 90%/ear (Musiek, 1983). Clearly labeled illustrative (demonstration stimuli on uncalibrated audio), never a diagnosis; mirrored in Dart + Python and unit-tested. Forced-choice scores are also reported guessing-corrected (Abbott's formula — the 1/n chance floor removed), and every adaptive threshold is shown with its reversal-based standard deviation (± precision).
- Deterministic adaptive engine mirrored in Dart and Python and pinned by shared golden vectors. It is a transformed up-down staircase (Levitt, 1971, JASA 49:467–477): 2-down/1-up targets ~70.7% correct (3-down ~79.4%), with **step-size reduction** — a coarse initial step that halves over the first reversals down to a fine floor — on the gap (4→1 ms), amplitude-modulation (4→1 dB) and frequency (2→0.25 semitone) tracks for more precise thresholds. The speech-in-noise SNR track is deliberately fixed-step (its golden trajectory is pinned in three places). Adaptation only ever moves a task parameter or the SNR — never master volume. Each reported threshold carries its reversal-based standard deviation (± SD) as a research-only precision indicator.
- Offline-first trial persistence, encrypted at rest (AES-GCM), with version lineage on every trial.
- Results separated per condition/output-device with reliability; explainable recommendation (reason + confidence); clinician review mode; CSV/JSON export; content-pack SHA-256 hashes + HMAC signature + version retirement.
- **Real on-device report**: every completed session stores its engine-exact headline metric (`lib/core/session_summary.dart` — the reversal-based threshold for adaptive tests, per-ear percents for dichotic/pattern tests, LiSN-S advantages, MLD dB, digit span…), and the Report tab builds the results table, Buffalo-profile classification, rule-based narrative, staircase-trajectory plot and FHIR R4 export from that real history (age-banded via the listener-age setting). A clearly-bannered demonstration report shows only until data exists.
- **Psychometric analytics**: maximum-likelihood logistic psychometric-function fit (threshold at the staircase's target proportion + slope) and m-AFC d′ (Hacker & Ratcliff, 1979) — mirrored in Dart (`lib/core/psychometrics.dart`) and Python (`packages/protocol_engine/psychometrics.py`) and pinned by shared golden values (`tests/test_psychometrics.py`, `tool/verify/psychometrics_harness.dart`).
- Trends plot each adaptive test's *threshold* over sessions (lower-is-better aware) rather than staircase-pinned accuracy; session history rows show the real metric; a "Continue where you left off" card, home search across tests/trainings, and a 10-week practice-calendar heatmap round out the home screen.
- Accessibility (WCAG 2.2 AA pass, 26 Jul 2026): muted-text contrast fixed to ≥ 4.5:1, text scaling to 200%, reduced-motion honoured by every decorative animation (countdown, dots, wave, response-time flash, encouragement, confetti), haptic feedback on answers, number-key (0–9) answering, optional post-session confidence self-report alongside fatigue.

## Verification
Backend (Python):
```bash
pytest -q
python tests/run_selftest.py
```

Full suite (backend + headless Dart harnesses + Flutter analyze + Flutter tests) in one command:
```bash
# Windows
pwsh tools/verify_all.ps1
# macOS/Linux
bash tools/verify_all.sh
```
Set `HEARBLOOM_DART` / `HEARBLOOM_FLUTTER` to the executable paths if `dart` / `flutter` are not on `PATH`. CI runs the same steps (`.github/workflows/ci.yml`).

The pure-Dart logic (engine, safety, audio DSP, protocols, persistence, models) is verified headlessly via `apps/flutter_app/tool/verify/*_harness.dart` (`dart run ...`), so it can be checked without launching the GUI. Launching the desktop window (`flutter run -d windows`) additionally requires the Visual Studio "Desktop development with C++" workload; mobile requires the Android SDK.

## Kiro
Open the repository in Kiro and read `KIRO_HANDOFF.md` first.
