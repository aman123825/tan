# Kiro / Claude Opus Handoff

## Mission
Turn this research monorepo into a premium installed auditory-training application while preserving deterministic measurement, explainable personalization, and strict non-diagnostic boundaries.

## Read first
1. `docs/SAFETY.md`
2. `protocols/catalog.json`
3. `packages/protocol_engine/engine.py`
4. `services/api/main.py`
5. `tools/generate_stimuli.py`
6. `apps/flutter_app/lib/main.dart`

## Non-negotiable architecture
- Flutter UI on Windows/macOS/Linux/Android/iOS; no browser-tab product.
- Deterministic protocol engine controls trials, stopping and scoring.
- AI recommends training but cannot alter locked assessment scoring.
- Never increase master volume based on incorrect responses.
- Keep wired/Bluetooth/speaker results separate.
- Store app, protocol, stimulus and model versions with every trial.
- Separate training and assessment token pools.
- Store right, left and binaural sessions separately.
- Generated speech is `demo_only` until linguist/audiologist review.

## Status — implemented and verified
The original backlog is complete and has since been extended with research-grounded
accuracy, normative interpretation, adaptive noise beyond speech-in-noise, a
one-command launcher and a professional Material-3 UI. Verified by
`tools/verify_all.ps1` (pytest 67, self-test 40/40, 26 headless Dart harnesses,
`dart analyze lib test` clean, `flutter test` 38) and a full web build
(`flutter build web` → `✓ Built build\web`, which compiles `main.dart` and every
renderer and resolves all declared assets).

1. Flutter platform runners generated (`flutter create .`; windows/macos/linux/android/ios + web). ✅
2. `protocols/catalog.json` shipped at `apps/flutter_app/assets/protocols/catalog.json`. ✅
3. Catalog repository + typed Dart models. ✅
4. Audio via `just_audio` (`JustAudioPort`) over a pure-Dart PCM/DSP layer (tones, noise, gaps, AM, timbres, SFX, melodies, WAV encode/decode, SNR mixing). ✅
5. Renderers — **all 56 explicit catalog groups render**: closed-set (word/number/letter/phoneme/color), 3AFC oddball (pitch/frequency-JND), adaptive 3AFC (gap/modulation-depth/modulation-rate/level/detection incl. forward masking), 4AFC adaptive SNR (all six speech-in-noise groups, real word-in-noise), rhythm, chord, MCI 9-choice (+masker), typed open-set (word/sentence/matrix/CNC), sequence entry (digit + note + instrument), instrument/melody/environmental/speaker identification, picture (food/animals/colors), dichotic digits (stereo, per-ear), and composite batteries. ✅
6. Comfortable-level workflow; master volume never changes in-test and never rises on errors. ✅ Optional post-session fatigue self-report (0–10) recorded as `fatigue_after`; informational only, never alters scoring; the recommender may use it to suggest shorter/easier blocks. ✅
7. Offline-first trial persistence, encrypted at rest (AES-GCM), version lineage on every trial. ✅
8. FastAPI profile/session/trial/results/recommendation/catalog/manifest endpoints + Dart client. ✅
9. Clinician review mode and CSV/JSON export. ✅
10. Content-pack SHA-256 hashes + HMAC signature + version retirement. ✅
11. Tests for protocol state transitions and safety invariants (headless harnesses + widget tests). ✅
12. Research-grounded adaptive engine: a transformed up-down staircase (Levitt, 1971) with **step-size reduction** on the gap (4→1 ms), amplitude-modulation (4→1 dB) and frequency (2→0.25 semitone) tracks, plus a `targetProportion` getter (2-down/1-up ≈ 0.707, 3-down ≈ 0.794). Mirrored Dart⇄Python and pinned by shared golden vectors (the fixed-step SNR trajectory **and** the gap step-reduction trajectory). ✅
13. Research-only normative interpretation (`lib/core/norms.dart` + `packages/protocol_engine/norms.py`): cited reference bands for gap-in-noise (Musiek 2005), frequency DL (Wier 1977), AM TMTF (Viemeister 1979; Bacon & Viemeister 1985), speech-in-noise (cf. QuickSIN, Killion 2004) and dichotic digits (Musiek 1983), surfaced as a cited badge in result cards and unit-tested (`test_norms.py`, `norms_harness.dart`). Clearly illustrative, never diagnostic. Also guessing-corrected accuracy (Abbott's formula) and a reversal-based threshold SD (± precision) shown on the threshold cards. ✅
14. Adaptive noise beyond speech-in-noise: closed-set **word recognition is presented in adaptive-SNR babble** (2-down/1-up on SNR), reporting a research-only SNR threshold with interpretation. The `ClosedSetSession` takes an optional `AdaptiveTrack snrTrack`; verified in `closed_harness.dart`. ✅
15. One-command launcher (`tools/run_app.ps1` / `run_app.sh`) that builds and serves the web app locally (verified serving HTTP 200), and a professional Material-3 theme (flat app bar, rounded bordered cards, consistent buttons/chips/inputs) with a branded home hero surfacing the adaptive/volume-locked/research story. ✅

## Remaining — content and optional research work (not code-blocked)
- Replace `demo_only` demonstrations with reviewed content and run linguist/audiologist validation: Indian-English speech, real environmental-sound and instrument recordings, familiar-melody sets, and food/animal images (the app currently ships synthesized timbres/effects/melodies, generated voices, and emoji pictures, each surfaced with its validation status).
- Optional/future: offline ASR answer-assistance is wired as a pluggable, correctable seam (`AsrProvider`, disabled by default so no model/network is bundled) that only *pre-fills* the open-set answer field and never auto-submits or scores — plugging in a concrete on-device engine (e.g. Vosk/`speech_to_text`) is the remaining product/platform/licensing decision. Native DSP/FFI remains available if sample-critical timing ever needs it.

## Prompt for Kiro (continuation)
> Continue the HearBloom research monorepo as a production-quality Flutter app. Do not replace the deterministic protocol engine with an LLM. Keep medical claims disabled, generated content `demo_only`, and every safety invariant intact. Implement one verified vertical slice at a time and run `tools/verify_all.ps1` (or `.sh`) after every change.

## Definition of done for a protocol
- Introduction, Preview, Training, Test, Results
- Stimulus eligibility and exclusion rules
- Response renderer
- Feedback behavior
- Adaptation and bounds
- Stop rule
- Score and reliability
- Trial event schema
- Unit, integration and UI tests
- Audiologist review field
- Validation status shown in UI
