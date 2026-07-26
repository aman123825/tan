# HearBloom — Master Upgrade List v4 (VERIFIED)
## Every status ground-truthed against the codebase — 26 July 2026 (Tier passes 1/2/3: 26–27 Jul 2026)

Supersedes `UPGRADE_PLAN_V3.md`, whose statuses had drifted badly: **31 items
marked ❌ missing were already implemented** (LiSN-S, SSW, DSI, the tinnitus
battery, dichotic-integration training, prosody, kids mode, SSQ12, HHIE-S…).
Every row below was verified by reading the code, and the whole suite passes:
pytest + self-test, 30 headless Dart harnesses, `dart analyze`
clean (0 errors/warnings), `flutter test` green.

**Legend:** ✅ have (verified in code) · ⚠️ partial · ❌ missing · 🆕 26 Jul verification pass · 🆕2 Tier-1 · 🆕3 Tier-2 · 🆕4 Tier-3 (26–27 Jul 2026)

---

## WHAT THE TIER-1 PASS BUILT (🆕2) — all ten Tier-1 roadmap items

1. **Hum-back response mode for FPT/DPT (A4).** `PatternResponseMode` in
   `core/pattern_test.dart` + in-page chooser: hum the pattern aloud →
   reveal/replay → self-/helper-score matched. Hummed runs persist under
   `*_hum` group ids so labeled-response norms are never applied to hummed
   scores. Pattern sessions now also PERSIST (they previously never reached
   `_persistRun` — fixed at all four launch sites).
2. **Screening audiogram (A7).** `core/audiogram.dart` (modified
   Hughson-Westlake down-10/up-5, 2-of-ascending threshold, seeded catch
   trials, −10 dBFS hard cap) + `features/audiogram/` page with a painted
   audiogram (right = red O, left = blue X, ▼ no-response), per-frequency
   table, PTA per ear, false-alarm rate. Explicitly dBFS, NOT dB HL.
3. **ITD/ILD lateralization JNDs (A12).** `core/binaural_jnd.dart`
   (fractional-delay ITD tones at 500 Hz, ±ILD/2 noise, 2-interval assembly)
   + `features/binaural_jnd/` page: centred-vs-off-centre 2AFC, 2-down/1-up
   with Levitt step reduction (ITD 500→ min 20 µs; ILD 6→ min 0.5 dB).
4. **Fixed-SNR figure-ground words (A5).** `core/figure_ground.dart` +
   page: +8/0/−8 dB SNR word blocks (SCAN-3-style), per-SNR percents, no
   feedback (locked test), voice rotation.
5. **Real confusion matrix + phoneme analysis (I1/I3).** Per-trial
   (target, response) pairs persist on `SessionRecord` (`cf` key,
   interval-choice labels excluded, capped); `aggregateConfusions` feeds the
   report's confusion + phoneme-feature sections from REAL data with a
   source caption; the demo sample remains only in demo mode.
6. **Session A-vs-B comparison + test-retest ICC (I10/I11).**
   `icc21`/`icc31` (Shrout & Fleiss) added to the mirrored
   psychometrics pair (Dart+Python, golden-pinned both sides).
   `features/compare/session_compare_page.dart` (More menu → "Compare
   sessions"): pick any two same-test sessions → headline/sub-score deltas
   (lower-is-better aware) + across-patients ICC when ≥2 patients have ≥2
   administrations, honest fallback text otherwise.
7. **4 proxy voices across word/sentence tasks (B2).**
   `core/audio/voice_variants.dart` — deterministic pitch/rate transposition
   (the LiSN-S different-talker mechanism), rotated per trial in word/sentence
   closed sets, speech-in-noise TRAINING (never locked tests) and
   figure-ground, always labelled "(proxy)".
8. **Adaptive sentence closure (B6).** Response-set size ladder 2→8 choices,
   2-up/1-down (`kClosureChoiceLevels`), generator pads large sets from other
   items' answers; metric records max set reached + per-trial set trajectory.
9. **Localization room view + feedback arrow (B9).** `_RoomPainter`: room
   walls, listening arc, painted head (nose/ears = facing), green arrow to
   the true source + red arrow to a wrong choice after answering.
10. **Accessibility (H4/H6/H11).** Theme-level focus visibility: focused
    outline on all Filled/Elevated/Outlined/Text buttons + `focusColor`
    highlight for every InkWell-based control (all three themes) + FocusRing
    on the transports (H4 ✅). "Show stimulus text" setting reveals a caption
    AFTER each answer via the shared scaffold (H6 ✅). Consistent Help `?` on
    every trial page (same position, same sheet: task, controls, shortcuts)
    (H11 ✅).
11. **APHAB + Fisher questionnaires (C3/C5).** Full 24-item APHAB (A–G scale,
    EC/BN/RV/AV with reversals, global score; Cox & Alexander 1995) + 25-item
    Fisher's checklist (4 pts/item; Fisher 1976), plus a Questionnaires hub
    (More menu) that also surfaces SSQ12 + HHIE-S.
12. **Real PDF report bytes (I7).** `core/pdf_writer.dart` — dependency-free
    PDF 1.4 writer (Helvetica, wrapped paragraphs, tables, pagination,
    verified xref) + Download PDF button (browser download on web, temp-file
    path elsewhere).

All new measurement logic is covered by `tool/verify/diagnostics_harness.dart`
(registered in verify_all.sh/ps1 + CI) and `test/tier1_v4_test.dart`; the ICC
functions are golden-pinned in BOTH `tests/test_psychometrics.py` and
`tool/verify/psychometrics_harness.dart`.

---

## WHAT THE TIER-2 PASS BUILT (🆕3 — 27 Jul 2026, same session)

1. **TMTF multi-rate curve (A9).** `core/psychoacoustics.dart` `TmtfSession` —
   abbreviated modulation staircase at 4/8/32/128/512 Hz, 3AFC, painted TMTF
   curve on the results page (`features/psychoacoustics/tmtf_page.dart`);
   metric = mean threshold with per-rate sub-scores.
2. **Spectral ripple discrimination (A10).** 160-component rippled noise,
   3AFC phase-inversion oddball; the staircase adapts the ripple PERIOD in
   octaves (reported as ripples/octave); runs on the shared
   `IntervalTaskPage`.
3. **IRN pitch strength (A11).** Delay-and-add iterated rippled noise
   (RMS-matched per iteration), 2AFC IRN-vs-noise; the staircase adapts the
   iteration count. Harness verifies autocorrelation at the delay lag grows
   with iterations.
4. **Rhythm change in melody (E6).** Same seeded melody twice, one rendition
   with an interior onset displaced by an adaptive Δms; 2AFC on the shared
   interval page.
5. **Music in noise (E9).** Familiar-melody 4AFC inside synthetic babble at
   an adaptive SNR (`music_in_noise_page.dart`, reuses the golden-pinned SNR
   staircase; demo stimuli, labelled).
6. **Beat tapping (E11).** Production task: tap along with a click track;
   scored on asynchrony SD (consistency — device latency cancels), hit rate
   and tempo ratio (`BeatTapSession` + tap-pad page).
7. **G4 leftovers.** Repeat-trial flag (`flagLastTrial` — the shared scaffold
   grows a "Flag trial (I was distracted)" control; the flag rides the
   exported record, scoring untouched) · stimulus level meter
   (`levelEnvelope` + `StimulusLevelMeter`, wired into the mixing pages;
   static under reduced motion) · session naming (optional name on the
   post-session sheet → `SessionRecord.label` (`lbl`), shown in history and
   the A/B pickers).
8. **G5.** Personal-bests self-leaderboard (best run per test,
   lower-is-better aware) · daily practice reminder (ReminderStore + Home
   banner + settings; honestly in-app only, no OS push) · level-up chime on
   badge celebrations (quiet fixed-amplitude arpeggio).
9. **G2.** Painted per-module thumbnails (gradient + motif per module id) ·
   favorites (star toggles on module/training cards, persisted, "Your
   favorites" quick-access chips on Home).
10. **Kids (F1/F6/F7).** ABC listening worlds — the letter game in four
    acoustics (quiet / café babble / reverberant hall / phone band-pass) via
    a new `processor` hook on `ClosedSetPage` · "Pip's listening journey"
    story path (6 original chapters unlocked by completed-session count,
    painted dotted trail) · Guardian view (plain-language weekly summary +
    recent results in words).

Covered by `tool/verify/psychoacoustics_harness.dart` (registered in
verify_all.sh/ps1 + CI) and `test/tier2_v4_test.dart`.

---


## WHAT THE TIER-3 PASS BUILT (🆕4 — 27 Jul 2026, same session)

Tier 3 is the infrastructure/content tier; everything buildable from software
was built, and the two genuinely external needs (a hosted server, recorded
validated speech) are now one documented step away.

1. **Accounts + consent + erasure (J5/J8).** Backend: `/accounts/register|
   login|me`, `/profiles/{id}/link|consent`, `DELETE /profiles/{id}`,
   `DELETE /accounts/me` — stdlib crypto only (PBKDF2 passwords, HMAC
   expiring bearer tokens), all pre-existing endpoints stay
   anonymous-capable (`tests/test_accounts.py`). Client: consent screen
   (docs/CONSENT.md text, version-pinned, decline = NOTHING persists),
   Settings → Privacy & data (consent review, full JSON export of every
   stored key, delete-everything), optional study-account card on the
   remote-monitoring page.
2. **Deployment readiness (J1).** Production `Dockerfile` (+healthcheck),
   `.dockerignore`, CORS middleware with `HEARBLOOM_CORS_ORIGINS`,
   `docs/DEPLOYMENT.md` (keys, TLS, backups, erasure/portability endpoints).
   Actual hosting remains the operator's step — by design.
3. **Tinnitus completion (D4/D7/D8/C7).** Residual inhibition (60-s masker
   at MML+10 capped → suppression report + return timer, persisted);
   14-day graded desensitization program (ladder ≥10 dB below LDL, one step
   per day, stopping early never advances); TRT-model education page
   (original content, cited); THI (full 25 items, grades) and a TFI-STYLE
   paraphrased 8-domain screen (licensing-honest banner) in the
   questionnaires hub + Tinnitus tab.
4. **NOAH-style export + local analytics (J4/J10).** `core/noah_export.dart`
   — audiogram XML structured after HIMSA's audiogram 500 format, explicitly
   unofficial with dBFS caveats embedded, exported from the audiogram
   results (clipboard + download). Opt-in ON-DEVICE usage counters
   (off by default, view/clear in settings, included in data export).
5. **Content maskers + voice pipeline (K3/K4/K1/K6).**
   `assets/stimuli/noise_babble_speech.wav` — a real speech-derived babble
   generated OFFLINE from the shipped word recordings
   (`tools/generate_babble.py`, deterministic, stdlib-only) and used as the
   default music-in-noise masker (synthetic fallback); `musicMaskerStimulus`
   — a competing-music masker (K4) selectable in music-in-noise;
   `tools/generate_speech_words.py` now generates ALL 16 words × the 4 study
   voices in one (network) run. Recorded validated speech remains the K1
   gap.
6. **Platform (L2–L8).** CI now BUILDS web (PWA), Android APK and Windows
   with uploaded artifacts (`build-web`/`build-android`/`build-windows`
   jobs); the PWA manifest is complete (standalone, icons, scope) and the
   release web build ships Flutter's asset-precaching service worker (L4);
   Lite visuals mode (L8) — system fonts + all decorative animation off —
   replaces the retired html-renderer idea.

Covered by `tool/verify/tier3_harness.dart` (registered in verify_all.sh/ps1
+ CI), `test/tier3_v4_test.dart` and `tests/test_accounts.py`.

---

## WHAT THE 26 JUL 2026 PASS FIXED / ADDED (🆕)

1. **Report tab is now REAL.** It was a hard-coded mock (`kSampleReportTests`)
   in every build. Now each completed session persists its *engine-exact*
   headline metric (`core/session_summary.dart` → `SessionRecord`): the
   reversal-based threshold for adaptive tests (accuracy is deliberately
   pinned ≈70.7% by the 2-down/1-up rule and was scientifically wrong to
   report), per-ear percents (DDT/DSI/DPT/FPT/CST/filtered), SSW condition
   scores, LiSN-S advantage measures, MLD dB, RGDT ms, digit span. The Report
   tab (`report_tab.dart` + `report_data.dart`) builds the results table,
   Buffalo profile, narrative, staircase plot and FHIR export from that real
   history — age-banded via the new listener-age setting. The demo report
   remains only as a clearly-bannered fallback before any data exists.
2. **Psychometric analytics (I5 + I6).** New `core/psychometrics.dart` +
   `packages/protocol_engine/psychometrics.py` (mirrored, golden-pinned by
   `tests/test_psychometrics.py` + `tool/verify/psychometrics_harness.dart`,
   registered in verify_all.* and CI): maximum-likelihood logistic
   psychometric-function fit (threshold @ target proportion, slope, fixed
   guess/lapse rates) shown in the report for the latest staircase; m-AFC d′
   (Hacker & Ratcliff, 1979) shown on interval-task results.
3. **WCAG fixes.** `0xff64748b` muted text failed AA (3.75:1 page / 3.07:1
   card) — replaced with `0xff8b9bb4` (6.33 / 5.19) across 17 files (H1). Text
   size now reaches 150% and 200% (SC 1.4.4, H5). Reduced-motion now also
   covers the response-time flash, encouragement banner and confetti burst
   (H7/2.3.3). Haptic feedback on correct/incorrect via the shared trial
   scaffold (G1e).
4. **UX.** Home search across catalog modules/groups + trainings (G2a);
   "Continue where you left off" resume card (G2b); 10-week practice-calendar
   heatmap (G5a); post-session confidence rating stored with the session (C9);
   session-history rows and per-test trends now show the real metric — trends
   plot thresholds with lower-is-better-aware classification instead of
   staircase-pinned accuracy.
5. **Settings.** Listener age (4–110) drives the already-age-stratified norms
   in report + narrative.

---

## PART A — DIAGNOSTIC TESTS

| # | Test | v3 said | VERIFIED | Evidence / gap |
|---|------|---------|----------|----------------|
| A1 | LiSN-S | ❌ | ✅ | `core/lisns.dart` + `features/lisns/` — 4 conditions, talker/spatial/total advantages; reachable (home diagnostics). Synthesized proxy voices, labelled unvalidated. |
| A2 | SSW | ❌ | ✅ | `core/ssw.dart` + `features/ssw/` — RC/LC/RNC/LNC scoring. |
| A3 | DSI | ❌ | ✅ | `core/dsi.dart` + `features/dsi/` — per-ear closed-set sentences. |
| A4 | Pattern test verbal + **hum-back** response modes | ⚠️ | ✅ 🆕2 | In-page mode chooser; hummed runs self-/helper-scored, persisted as `*_hum` (label norms never applied). |
| A5 | SCAN-style figure-ground (fixed +8/0/−8 dB SNR) | ❌ | ✅ 🆕2 | `core/figure_ground.dart` + page — per-SNR percents, no feedback, task-relative (not normed). |
| A6 | Phonemic synthesis (scored test) | ❌ | ⚠️ | Sound-*blending* exists as training (`training/phonological.dart`); no scored Buffalo PST. |
| A7 | Screening audiogram (plotted 250–8k curve) | ⚠️ | ✅ 🆕2 | `core/audiogram.dart` + plotted page — Hughson-Westlake per ear/freq, catch trials, PTA; dBFS not dB HL. |
| A8 | LDL / hyperacusis screen | ❌ | ✅ | `core/tinnitus/ldl.dart` — ascending "too loud", **hard amplitude cap verified** (`kMaxSafeAmp` 0.7). |
| A9 | TMTF full curve (4–512 Hz) | ⚠️ | ✅ 🆕3 | `TmtfSession` — abbreviated staircases at 4/8/32/128/512 Hz + painted curve. |
| A10 | Spectral ripple discrimination | ❌ | ✅ 🆕3 | Rippled-noise 3AFC phase-inversion oddball; adapts ripple period (reports ripples/oct). |
| A11 | Iterated rippled noise pitch strength | ❌ | ✅ 🆕3 | Delay-add IRN vs noise 2AFC; adapts iteration count; RMS-matched. |
| A12 | ITD/ILD JND thresholds | ⚠️ | ✅ 🆕2 | `core/binaural_jnd.dart` + page — 2-interval centred-vs-lateralized, adaptive ITD (µs) and ILD (dB) staircases. |
| — | **Bonus already built, absent from v3's list:** | | ✅ | MLD (`mld_test.dart`), RGDT (`rgdt.dart`), Binaural Fusion, DPT/FPT (`pattern_test.dart`), Competing Sentences, Low-pass Filtered Speech, Time-compressed Speech, HINT-style SRT (`hint_sin.dart`). |

## PART B — TRAINING MODULES

| # | Module | v3 said | VERIFIED |
|---|--------|---------|----------|
| B1 | Dichotic integration (CAPDOTS-style) | ❌ | ✅ `training/dichotic_integration.dart` — progressive interaural-asymmetry narrowing, 2-down/1-up. |
| B2 | Multi-speaker training (2M+2F) | ❌ | ✅ 🆕2 4 proxy voice variants (deterministic transposition, LiSN-S mechanism) rotate through word/sentence closed sets, SIN training and figure-ground, labelled "(proxy)". Recorded multi-talker audio remains a K1/K2 content gap. |
| B3 | Prosody (question/stress/emotion) | ❌ | ✅ `training/prosody.dart`. |
| B4 | Interhemispheric transfer | ❌ | ✅ `training/interhemispheric.dart` (hear one ear → tap opposite hand). |
| B5 | Speech tracking | ❌ | ✅ `training/speech_tracking_page.dart` (WPM). |
| B6 | Sentence-closure prediction | ⚠️ | ✅ 🆕2 24-item bank, difficulty now ADAPTS on response-set size (2→8 choices, 2-up/1-down). |
| B7 | Rapid speech | ✅ | ✅ |
| B8 | Reverberation training | ❌ | ✅ `training/reverb_training.dart` (RT60 ladder 0.3–1.2 s). |
| B9 | Localization w/ visual feedback | ⚠️ | ✅ 🆕2 Top-down room + painted head (facing/ears) + green true-source arrow and red wrong-choice arrow after each answer. |
| B10 | Music pitch/timbre/harmony/emotion | ⚠️ | ⚠️ pitch-ranking ✅, timbre ✅, emotion ✅; harmony *training* still missing (chord test exists). |
| B11 | Complex directions (conditional etc.) | ⚠️ | ⚠️ basic directions only; no if-then / 5 HearBuilder types. |
| B12 | Phonological awareness | ❌ | ✅ `training/phonological.dart` (rhyme, blend, delete). |
| B13 | Real-world scenes | ❌ | ✅ `training/scene_training.dart` (restaurant babble+dishes / classroom / phone band-pass, adaptive SNR each). |

## PART C — QUESTIONNAIRES

| # | Instrument | v3 said | VERIFIED |
|---|-----------|---------|----------|
| C1 | SSQ12 | ❌ | ✅ `questionnaires/ssq12_page.dart` — full 12 items, 0–10, subscale + overall means (Noble & Gatehouse). |
| C2 | HHIE-S | ❌ | ✅ `questionnaires/hhie_page.dart` — 10 items, 4/2/0 scoring, cut-offs (Ventry & Weinstein). |
| C3 | APHAB | ❌ | ✅ 🆕2 `questionnaires/aphab_page.dart` — 24 items, A–G, EC/BN/RV/AV + reversals, global score (Cox & Alexander, 1995). |
| C4 | HEAR-QL | ❌ | ❌ |
| C5 | Fisher's checklist | ❌ | ✅ 🆕2 `questionnaires/fisher_page.dart` — 25 observed behaviours, 4 pts each (Fisher, 1976); Questionnaires hub in the More menu. |
| C6 | CHILD / LIFE | ❌ | ❌ |
| C7 | THI + TFI | ❌ | ✅ 🆕4 THI full (25 items, McCombe grades); TFI as a clearly-labelled PARAPHRASED 8-domain screen (licensed TFI needs OHSU). |
| C8 | Listening-effort scale | ⚠️ | ⚠️ 0–10 fatigue self-report only. |
| C9 | Post-session confidence rating | ❌ | ✅ 🆕 confidence 0–10 collected with the fatigue sheet, stored on the session record. |

## PART D — TINNITUS & HYPERACUSIS

| # | Feature | v3 said | VERIFIED |
|---|---------|---------|----------|
| D1 | Pitch matching | ❌ | ✅ `tinnitus/pitch_match.dart` — 2AFC binary search 125 Hz–16 kHz. |
| D2 | Loudness matching | ❌ | ✅ `tinnitus/loudness_match.dart` (dB SL at matched pitch). |
| D3 | Minimum masking level | ❌ | ✅ `tinnitus/mml.dart` (ascending, averaged runs). |
| D4 | Residual inhibition | ❌ | ✅ 🆕4 `tinnitus/residual_inhibition.dart` + page — capped MML+10 masker, suppression report, return timer, persisted. |
| D5 | Sound-therapy player | ❌ | ✅ `tinnitus/sound_therapy_page.dart` — white/pink/brown/rain/ocean, timer, volume hard-capped. |
| D6 | Notched-noise therapy | ❌ | ✅ RBJ biquad notch at matched pitch (`therapy_sounds.dart`). |
| D7 | Hyperacusis desensitization program | ❌ | ✅ 🆕4 14-day graded pink-noise program, ladder ≥10 dB below LDL + capped, one step/day. |
| D8 | TRT counseling content | ❌ | ✅ 🆕4 original education page on the Jastreboff model (explicitly not therapy). |
| — | All tinnitus results persist (`tinnitus_store.dart`) and the matched pitch feeds the notch filter. | | ✅ |

## PART E — MUSIC

E1 ⚠️ (4 synth instruments) · E2 ✅ pitch ranking · E3 ✅ · E4 ✅ · E5 ✅ ·
E6 ✅ 🆕3 rhythm-change-in-melody (adaptive onset shift) · E7 ✅ · E8 ✅ emotion
(mode+tempo+consonance) · E9 ✅ 🆕3 music-in-noise (melody 4AFC, adaptive SNR)
· E10 ✅ timbre · E11 ✅ 🆕3 beat tapping (production; asynchrony SD).

## PART F — CHILDREN

F1 ✅ 🆕3 ABC×4-environments (quiet/café/hall/phone via ClosedSetPage
processor hook) · F2 ⚠️ (food/animal emoji sets only) · F3 ⚠️ · F4 ✅ Kids
Mode (theme + mascot banner, `kids/kids_mode.dart`) · F5 ⚠️ (4 sticker
slots, not a collectible system) · F6 ✅ 🆕3 story path (Pip's journey, 6
chapters by session count) · F7 ✅ 🆕3 guardian view (plain-language weekly
summary).

## PART G — UI/UX

- **G1:** response-time flash ✅ (🆕 reduced-motion aware) · confidence rating ✅ 🆕 · countdown ring ✅ · pulsing "Listen" prompt ⚠️ (static label) · haptics ✅ 🆕.
- **G2:** search ✅ 🆕 · back-stack ⚠️ · resume card ✅ 🆕 · module thumbnails ✅ 🆕3 (painted per-module art) · level progress map ✅ (consonant/vowel trainings) · favorites ✅ 🆕3 (stars + quick-access chips).
- **G3:** spectrogram toggle ✅ · light theme ✅ · reduced motion ✅ (🆕 full coverage) · empty states ⚠️ · skeleton loaders ❌ · print stylesheet ⚠️ (report prints via browser).
- **G4:** speed control ✅ (0.8–1.5×) · stereo/mono/L/R ✅ · volume meter ✅ 🆕3 (stimulus level meter) · pause/resume ✅ · repeat-trial flag ✅ 🆕3 (flag rides the record) · session compare ✅ 🆕2 (A/B page) · session name ✅ 🆕3 (post-session sheet).
- **G5:** practice heatmap ✅ 🆕 · self-leaderboard ✅ 🆕3 (personal bests) · milestone celebrations ✅ (badges + confetti + chime) · reminders ✅ 🆕3 (in-app daily banner; OS push still ❌) · level-up sound ✅ 🆕3.
- **G6:** press ripple ⚠️ (no scale) · number-key answering ✅ (0–9 via trial scaffold) · swipe gestures ❌ · per-test "what does this measure" ⚠️ (module sheets describe; no inline tooltip).

## PART H — ACCESSIBILITY (WCAG 2.2 AA)

| # | Criterion | VERIFIED |
|---|-----------|----------|
| H1 | Contrast ≥ 4.5:1 | ✅ 🆕 `0xff64748b` (3.07:1 on cards) replaced with `0xff8b9bb4` (5.19:1) in all 17 files; `0xff94a3b8` passes (5.71:1). |
| H2 | Semantics labels | ✅ broad coverage (verified in widget tests); keep auditing new pages. |
| H3 | Keyboard operability | ✅ Space/Enter/Esc + digit keys 0–9; Tab order default. |
| H4 | Focus indicators | ✅ 🆕2 Theme-level focused outline on all button families + `focusColor` ink highlight for every InkWell control (all 3 themes) + FocusRing transports; `FocusRing` stays on DSI/SSW/LiSN-S/dichotic answers. |
| H5 | Text resize 200% | ✅ 🆕 XL 150% + XXL 200% options. |
| H6 | "Show text" caption toggle | ✅ 🆕2 Settings toggle → caption chip reveals the stimulus text AFTER each answer (shared trial scaffold; never leaks an answer early). |
| H7 | Reduced motion | ✅ 🆕 user toggle + `MediaQuery.disableAnimations`, now honoured by countdown, dots, wave, flash, banner, confetti. |
| H8 | Target size | ✅ 56 px transports. |
| H9 | Not color-alone | ⚠️ correct/wrong uses icon+color; audit charts. |
| H10 | Drag alternatives | ✅ n/a. |
| H11 | Consistent help | ✅ 🆕2 Same-position `?` Help sheet on every trial page: task, optional what-it-measures, shared controls + shortcuts (WCAG 3.2.6). |
| H12 | i18n UI strings | ⚠️ stimulus languages configurable; UI strings English. |
| H13 | High-contrast mode | ✅ |

## PART I — REPORTING & ANALYTICS

| # | Feature | v3 said | VERIFIED |
|---|---------|---------|----------|
| I1 | Confusion matrix | ✅ | ✅ 🆕2 per-trial (target, response) pairs persist on `SessionRecord` (`cf`); the report aggregates REAL confusions across sessions with a source caption. |
| I2 | CAPD profile classification | ✅ | ✅ now driven by REAL results 🆕. |
| I3 | Phoneme feature-error analysis | ❌ | ✅ 🆕2 `core/phoneme_analysis.dart` in the report now runs on the REAL aggregated confusions (demo sample only in demo mode). |
| I4 | Staircase trajectory plot | ❌ | ✅ 🆕 real trajectories persisted per session and plotted (reversal markers + threshold line). |
| I5 | Psychometric function fit | ❌ | ✅ 🆕 ML logistic fit (Dart+Python golden-pinned). |
| I6 | d′ signal detection | ❌ | ✅ 🆕 m-AFC d′ on interval-task results. |
| I7 | Real downloadable PDF | ⚠️ | ✅ 🆕2 `core/pdf_writer.dart` (dependency-free PDF 1.4, verified xref) + Download PDF button (browser download / temp-file path). Print + copy retained. |
| I8 | Longitudinal dashboard | ⚠️ | ✅ report = latest-per-test 🆕; trends plot real thresholds 🆕; clinician dashboard groups by patient. |
| I9 | Percentile + z-score | ⚠️ | ⚠️ age-banded 4-level bands (cited); no percentile/z. |
| I10 | Test-retest ICC | ❌ | ✅ 🆕2 `icc21`/`icc31` in the mirrored psychometrics pair (golden-pinned both sides); shown on the compare page when ≥2 patients have ≥2 administrations. |
| I11 | Session A-vs-B comparison | ❌ | ✅ 🆕2 `session_compare_page.dart` (More menu): any two same-test sessions, headline + sub-score deltas, lower-is-better aware, honest reliability panel. |
| I12 | Per-trial CSV/JSON export in UI | ⚠️ | ✅ backend `/export.csv|.json` + results-page export. |
| I13 | Narrative summary | ❌ | ✅ 🆕 rule-based narrative now fed real measured values + listener age. |

## PART J — BACKEND & INTEROP

J1 ⚠️ 🆕4 deployment-READY (Dockerfile + healthcheck + CORS +
docs/DEPLOYMENT.md); hosting itself is the operator's step · J2 ⚠️ sync
plumbing + offline queue + optional accounts, no host · J3 ✅ FHIR R4 bundle
export from the real report 🆕 (copy-to-clipboard) · J4 ✅ 🆕4 NOAH-style
audiogram XML (unofficial, dBFS caveats embedded) · J5 ✅ 🆕4 opt-in accounts
(PBKDF2 + HMAC tokens, anonymous stays first-class) · J6 ⚠️ patient grouping
only · J7 ⚠️ local AES-GCM, no cloud backup · J8 ✅ 🆕4 consent screen
(version-pinned, decline = nothing persists) + export-my-data +
delete-everything + server erasure endpoints · J9 ✅ manifest + install
prompt + release-build service worker precaches assets · J10 ✅ 🆕4 opt-in
ON-DEVICE usage counters (view/clear/export; nothing transmitted).

## PART K — CONTENT

K1 ❌ still TTS (edge-tts `demo_only`) — biggest scientific gap · K2 ✅ 4
voices (2M+2F) shipped for speaker-ID; other tasks now rotate 4 *proxy*
transposed variants 🆕2 (recorded per-voice word audio still a content gap) ·
K3 ✅ 🆕4 speech-derived babble asset generated offline from the shipped word recordings (synthetic fallback retained) · K4 ✅ 🆕4 competing-music masker (runtime synth, selectable in music-in-noise) · K5 ⚠️ pools small
but CNC 10×50 + NU-6 lists exist · K6 ⚠️ multilang framework + word lists; word audio now one documented network run (4-voice generator upgraded) but not committed · K7 ✅ `core/word_lists.dart` · K8 ⚠️ 20 generic
HINT-style sentences · K9 ⚠️ emoji · K10 ✅ SHA-256 + HMAC.

## PART L — PLATFORM

L1 ✅ web deployed (`/tan/`) · L2/L3/L5 ✅ 🆕4 CI builds web + Android APK +
Windows with uploaded artifacts · L4 ✅ 🆕4 complete PWA manifest + Flutter's
release service worker precaches the asset bundle · L6/L7 ⚠️ ·
L8 ✅ 🆕4 Lite visuals mode (system fonts, no decorative animation; the html
renderer itself is retired upstream).

---

## REMAINING ROADMAP (true gaps only, re-prioritized)

### TIER 1 — ✅ COMPLETE (26 Jul 2026, second session — see 🆕2 above)
All ten items shipped and verified: A4 hum-back · A7 screening audiogram ·
A12 ITD/ILD JNDs + A5 fixed-SNR figure-ground · I1/I3 real confusions ·
I10/I11 ICC + A/B compare · B2 proxy voices + B6 adaptive closure · B9 room
visualization · H4/H6/H11 accessibility · C3/C5 APHAB + Fisher · I7 real PDF.

### TIER 2 — ✅ COMPLETE (27 Jul 2026 — see 🆕3 above)
All five items shipped and verified: E6/E9/E11 music additions · G5/G2
engagement (reminders remain in-app only — OS push needs platform plumbing)
· F1/F6/F7 kids content · A9 TMTF + A10/A11 ripple & IRN · G4 level meter,
trial flag and session naming.

### TIER 3 — ✅ software side COMPLETE (27 Jul 2026 — see 🆕4 above)
Everything buildable in software shipped: accounts/consent/erasure + deploy
readiness (J1/J2/J5/J8) · speech-babble + music maskers + 4-voice generation
pipeline (K3/K4; K1 recorded speech and K6 multilang audio remain CONTENT
steps: run the documented generators / record validated stimuli) · CI
web/Android/Windows builds + PWA offline + lite mode (L2–L8; iOS/macOS need
an Apple toolchain+account) · NOAH-style export + local-only analytics
(J4/J10) · tinnitus battery complete (D4/D7/D8/C7). The remaining
operator steps: host the backend (docs/DEPLOYMENT.md) and license/record
validated stimuli.

---

*Verified 27 July 2026 (Tier-1/2/3 passes): pytest (incl. ICC goldens +
accounts/consent) · self-test · 30 Dart harnesses (🆕2 `diagnostics`,
🆕3 `psychoacoustics`, 🆕4 `tier3`) · `dart analyze` 0 errors/0 warnings ·
`flutter test` green (incl. tier1/2/3_v4 test files). Research software —
not a medical device, not a diagnosis.*
