# HearBloom — EXHAUSTIVE Master Upgrade List v3
> **⚠️ SUPERSEDED by `UPGRADE_PLAN_V4.md` (26 July 2026).** Every status below
> was re-verified against the codebase and 31 items marked ❌ here were in
> fact already implemented (LiSN-S, SSW, DSI, tinnitus battery, dichotic
> integration training, SSQ12, HHIE-S, kids mode…). V4 carries the corrected,
> code-verified statuses and the re-prioritized remaining roadmap. This file
> is kept as history only.

## Complete Feature Gap Analysis (Deep Research, 25 July 2026)
### Nothing left out.

**Sources read this round:** Angel Sound (all 9 modules), LACE, CAPDOTS (dichotic integration training), Acoustic Pioneer / Feather Squadron (gamified dichotic + pattern games, ASHA-approved), Cochlear CoPilot, MED-EL/Meludia music training, Neuromonics tinnitus, AAA/ASHA CAPD guidelines, StatPearls, Bellis & Beck, VA NCRAR CAPD Working Group, LiSN-S (Cameron & Dillon spatial test), SSW (Katz), DSI, QuickSIN/HINT/WIN/BKB-SIN, SSQ/SSQ12, HHIE, APHAB, HEAR-QL, Fisher's checklist, gamification adherence meta-analyses, WCAG 2.2 AA, HL7 FHIR / USCDI audiogram standard.

**Legend:** ✅ have · ⚠️ partial · ❌ missing

---

## PART A — DIAGNOSTIC TESTS STILL MISSING

| # | Test | Status | What's needed |
|---|------|--------|---------------|
| A1 | **LiSN-S (Listening in Spatialized Noise – Sentences)** | ❌ | Target sentences + competing stories at 0° vs ±90° azimuth (HRTF/ITD-ILD spatialization). Reports SRT + 3 "advantage" measures: talker advantage, spatial advantage, total advantage. Gold-standard spatial-processing test (Cameron & Dillon). We have basic spatial training but NOT this scored diagnostic. |
| A2 | **Staggered Spondaic Word (SSW)** | ❌ | Katz 1962 classic. Overlapping spondees, 40 items, scored RC/LC/RNC/LNC. Maps directly to Buffalo Model categories. We reference it but haven't built it. |
| A3 | **Dichotic Sentence Identification (DSI)** | ❌ | Two sentences simultaneously, closed-set ID, free + directed. AUC 0.83 for CAPD; better than DDT for older adults / mild cases. |
| A4 | **Pitch Pattern Sequence (verbal + humming response modes)** | ⚠️ | Our FPT uses tap response. Clinical FPT also uses verbal labeling AND humming — humming-correct-but-labeling-wrong dissociates left-hemisphere (linguistic) from right-hemisphere (acoustic) deficits. Add a "hum it back" response mode. |
| A5 | **SCAN-3 style Auditory Figure-Ground** | ❌ | Words at fixed +8, +0, −8 dB SNR (multi-talker babble). Standardized subtest we don't replicate exactly. |
| A6 | **Phonemic Synthesis Test** | ❌ | Blend phonemes into words (/k/-/a/-/t/ → "cat"). Buffalo battery component; tests phonemic decoding. |
| A7 | **Pure-tone Audiogram (screening, research-only)** | ⚠️ | Adaptive threshold at 250/500/1k/2k/4k/8k Hz, plot an audiogram. We have tone detection but not a full plotted audiogram with air-conduction curve. NOT a calibrated clinical audiogram — clearly labeled screening. |
| A8 | **Loudness Discomfort Level (LDL) / hyperacusis screen** | ❌ | Ascending level with "too loud" button to estimate uncomfortable loudness — flags hyperacusis. Safety-gated (never exceeds a hard cap). |
| A9 | **Temporal Modulation Transfer Function (TMTF) full curve** | ⚠️ | We detect modulation; add the full TMTF (threshold vs modulation rate 4–512 Hz) plotted as a curve — the definitive temporal-envelope measure. |
| A10 | **Spectral Ripple Discrimination** | ❌ | Ripple density discrimination — the standard spectral-resolution measure for CI users (predicts speech-in-noise). |
| A11 | **Iterated Rippled Noise / Pitch strength** | ❌ | Temporal-fine-structure pitch measure. |
| A12 | **Interaural Time/Level Difference thresholds (ITD/ILD JND)** | ⚠️ | We simulate spatial angles for training; add threshold measurement of the smallest ITD (µs) and ILD (dB) detectable — binaural acuity. |

---

## PART B — TRAINING MODULES STILL MISSING

| # | Module | Status | What's needed |
|---|--------|--------|---------------|
| B1 | **Dichotic Integration Training (CAPDOTS-style)** | ❌ | Progressive dichotic training that starts with large interaural asymmetry and narrows it — directly treats binaural-integration deficit / left-ear disadvantage. Evidence-based (CAPDOTS). |
| B2 | **Multi-speaker training (2M + 2F voices)** | ❌ | Angel Sound uses 4 speakers for everything. We use 1. Generate/record 4 voices; enables talker-normalization training. |
| B3 | **Prosody training (stress, intonation, emotion)** | ❌ | Identify question vs statement, stressed word, emotional tone. Bellis "prosodic deficit" remediation. |
| B4 | **Interhemispheric transfer / cross-modal training** | ❌ | Dichotic + motor tasks (hear left→tap right). Buffalo/Bellis integration remediation. |
| B5 | **Speech tracking** | ❌ | Clinician/recording reads text; user repeats increasingly long chunks. Classic aural-rehab technique. |
| B6 | **Contextual / sentence-closure training** | ⚠️ | "The dog chased the ___" — predict from context (schema induction). We have word closure, not sentence-context prediction. |
| B7 | **Rapid speech / accelerated training** | ✅ | Have (time-compressed). |
| B8 | **Reverberation training** | ❌ | Add room reverb to speech; train listening in echoic spaces. |
| B9 | **Localization training with visual feedback** | ⚠️ | Have basic spatial; add continuous localization with a room visualization and feedback arrow. |
| B10 | **Music: pitch-ranking, timbre, harmony, emotion** | ⚠️ | Meludia-style: rank pitches, identify major/minor emotion, detect harmony changes. |
| B11 | **Following complex directions (multi-clause)** | ⚠️ | Have basic; extend to conditional ("if… then…") and quantitative/spatial/temporal direction types (HearBuilder's 5 types). |
| B12 | **Auditory-verbal / phonological awareness games** | ❌ | Rhyming, sound blending, segmentation, deletion — reading-readiness (FastForWord domain). |
| B13 | **Real-world scene training** | ❌ | Restaurant / classroom / phone scenarios with layered realistic sounds (Angel Sound Scene module). |

---

## PART C — VALIDATED SELF-REPORT QUESTIONNAIRES (currently only SCAP)

| # | Instrument | Status | Use |
|---|-----------|--------|-----|
| C1 | **SSQ12 (Speech, Spatial & Qualities of Hearing, 12-item)** | ❌ | Functional hearing disability across speech/spatial/quality domains. Most-cited outcome scale. |
| C2 | **HHIE-S (Hearing Handicap Inventory, Screening)** | ❌ | Emotional + social impact of hearing difficulty; 10 items, cutoff-scored. |
| C3 | **APHAB (Abbreviated Profile of Hearing Aid Benefit)** | ❌ | Communication in ease/reverb/noise/aversiveness — pre/post benefit. |
| C4 | **HEAR-QL (pediatric quality of life)** | ❌ | Child-specific QoL for hearing difficulty. |
| C5 | **Fisher's Auditory Problems Checklist** | ❌ | 25-item teacher/parent CAPD behavior checklist (classic). |
| C6 | **CHILD / LIFE (classroom listening)** | ❌ | Situational listening difficulty in school. |
| C7 | **Tinnitus Handicap Inventory (THI) + Tinnitus Functional Index (TFI)** | ❌ | If adding tinnitus module. |
| C8 | **Fatigue / listening-effort scale (NASA-TLX style)** | ⚠️ | We record a 0–10 fatigue rating; add a validated listening-effort scale. |
| C9 | **Post-session confidence rating** | ❌ | "How confident were you?" per test — metacognition tracking. |

---

## PART D — TINNITUS & HYPERACUSIS EXTENSION (new domain)

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| D1 | **Tinnitus pitch matching** | ❌ | 2AFC pitch search to match tinnitus frequency (reliability-checked, per literature). |
| D2 | **Tinnitus loudness matching** | ❌ | Level match at the matched pitch → sensation level. |
| D3 | **Minimum masking level** | ❌ | Lowest noise level that masks the tinnitus. |
| D4 | **Residual inhibition test** | ❌ | Play masker, measure how long tinnitus is suppressed after. |
| D5 | **Sound therapy player** | ❌ | Customizable maskers (white/pink/brown noise, nature, notched noise at tinnitus freq). |
| D6 | **Notched-noise / notched-music therapy** | ❌ | Remove energy at tinnitus frequency (evidence-based). |
| D7 | **Hyperacusis desensitization** | ❌ | Gradual, safety-capped level exposure with LDL tracking. |
| D8 | **TRT-style counseling content** | ❌ | Educational modules on habituation. |

*(Tinnitus is a large separate domain — flag as an optional "HearBloom Tinnitus" companion, not core CAPD.)*


---

## PART E — MUSIC MODULE GAPS

| # | Feature | Status |
|---|---------|--------|
| E1 | Instrument identification (multi-level, more instruments) | ⚠️ have basic |
| E2 | **Pitch ranking** (order 3–5 notes low→high) | ❌ |
| E3 | **Melodic contour identification** (9-choice) | ✅ have |
| E4 | **Familiar melody identification** | ✅ have |
| E5 | **Rhythm discrimination** | ✅ have |
| E6 | **Rhythmic-change detection within a melody** | ❌ (Angel Sound Music Rhythm group) |
| E7 | **Harmony/chord-quality (major/minor/dim/aug)** | ✅ have |
| E8 | **Emotion-in-music (happy/sad via mode+tempo)** | ❌ |
| E9 | **Music-in-noise** | ❌ |
| E10 | **Timbre discrimination (same note, different instrument)** | ❌ |
| E11 | **Beat/tempo tapping (rhythm production)** | ❌ |

---

## PART F — CHILDREN / SCENE-BASED MODULE GAPS

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| F1 | **Learning ABC** (26 letters × 4 environments) | ❌ | quiet / phone-band / +10 dB / 0 dB music background |
| F2 | **Category vocabulary builder** (food/animal/family/time, ~100 each, with pictures) | ⚠️ | have small emoji sets, not the full 4-environment builder |
| F3 | **Multi-environment phonetic contrast** | ⚠️ | have contrast training, not the quiet/phone/noise variants |
| F4 | **Age-appropriate visuals & mascot** | ❌ | Angel Sound uses a friendly bear mascot + cartoon UI for kids. We are clinical/dark. Add a **Kids Mode** with light, colorful, cartoon theme + character guide |
| F5 | **Reward stickers / collectible characters** | ❌ | child-friendly gamification (vs points/streaks) |
| F6 | **Story-based learning path** | ❌ | narrative that ties exercises together |
| F7 | **Parent/teacher dashboard for a child** | ⚠️ | have clinician dashboard; add child-progress view for guardians |

---

## PART G — UI / UX DESIGN IMPROVEMENTS (comprehensive)

### G1. Feedback & during-trial UX
- ✅ Live mini-chart (done) · ✅ audio wave animation (done) · ✅ correct-answer reveal (done) · ✅ encouragement (done)
- ❌ **Response-time flash** after each trial ("620 ms")
- ❌ **Confidence slider** on hard trials
- ❌ **Countdown ring** during the 2 s pre-play delay (so the wait feels intentional, not frozen)
- ❌ **"Listen" prompt** that pulses right before audio
- ❌ **Haptic feedback** (mobile) on correct/incorrect

### G2. Navigation & information architecture
- ✅ Bottom nav (done) · ✅ onboarding (done) · ✅ difficulty selector (done)
- ❌ **Search** across all tests/training
- ❌ **Breadcrumb back-stack** consistency (some deep pages hard to exit)
- ❌ **"Resume where you left off"** card
- ❌ **Module thumbnails/preview images** on cards (Angel Sound shows a visual of each)
- ❌ **Level progress map** (chapter-style: done/current/locked) within multi-level modules
- ❌ **Favorites / pinned exercises**

### G3. Visual design polish
- ❌ **Spectrogram/waveform view toggle** for any stimulus (educational + confirms audio)
- ❌ **Light theme option** (currently dark only; clinicians may want light; kids need bright)
- ❌ **Reduced-motion mode** (disable animations — vestibular/accessibility)
- ❌ **Empty-state illustrations** (history, trends, dashboard when no data)
- ❌ **Skeleton loaders** while catalog/audio loads
- ❌ **Consistent iconography** (some Material default icons look generic)
- ⚠️ **Print stylesheet** for the report (make browser Ctrl-P clean)

### G4. Session control (from Angel Sound toolbar)
- ❌ **Manual Speed control** (playback rate override)
- ❌ **Stereo / Mono / Left-only / Right-only** playback selector
- ❌ **Volume meter** (visual level bar confirming output)
- ❌ **Pause/resume mid-session** with state preservation
- ❌ **"Repeat this trial later"** flag (mark tricky items)
- ❌ **Session save/load/name/compare** (Angel Sound's SESSION menu)

### G5. Motivation & engagement (evidence-based — gamification improves adherence)
- ✅ points/streaks/badges (done)
- ❌ **Weekly goal + calendar heatmap** of practice days
- ❌ **Leaderboard (self vs past self)** — never social/competitive for clinical use
- ❌ **Milestone celebrations** (100 trials, first mastery)
- ❌ **Personalized reminders/notifications** (web push / email)
- ❌ **Level-up sound + animation** on advancing difficulty

### G6. Micro-interactions
- ❌ smooth choice-button press animation (scale/ripple)
- ❌ number-key (1–9) answering on choice grids (accessibility + speed)
- ❌ swipe gestures (mobile) between trials
- ❌ tooltip "what does this test measure?" on every test

---

## PART H — ACCESSIBILITY (WCAG 2.2 AA — legally required for public health apps)

| # | Criterion | Status | Action |
|---|-----------|--------|--------|
| H1 | **Color contrast ≥ 4.5:1** | ⚠️ | Audit muted-gray text on dark bg (some 0xff64748b may fail); bump to pass AA |
| H2 | **Screen-reader labels (Semantics) on ALL controls** | ⚠️ | Mostly done; audit new pages |
| H3 | **Full keyboard operability** | ⚠️ | Space/Esc done; add Tab order + number-key answers + focus rings |
| H4 | **Visible focus indicator (2.4.7 / 2.4.11 focus-not-obscured)** | ❌ | Add clear focus outlines |
| H5 | **Text resize to 200% without loss (1.4.4)** | ⚠️ | have text-size setting; verify no clipping |
| H6 | **Captions/transcripts for audio** | ❌ | For a HEARING app this is nuanced — provide a "show text" toggle so deaf/HoH clinicians/parents can see what's playing (not during the test, but in preview/help) |
| H7 | **Reduced motion (2.3.3)** | ❌ | Respect prefers-reduced-motion |
| H8 | **Target size ≥ 24×24 (2.5.8)** | ✅ | transport buttons now 56px |
| H9 | **No reliance on color alone (1.4.1)** | ⚠️ | correct/wrong uses color + icon (good); audit charts |
| H10 | **Dragging alternatives (2.5.7)** | ✅ | no essential drag |
| H11 | **Consistent help (3.2.6)** | ❌ | help affordance in same place every screen |
| H12 | **Language attribute + multi-language UI strings** | ⚠️ | stimuli framework exists; UI itself is English-only — externalize strings for i18n |
| H13 | **High-contrast mode** | ✅ | have toggle |


---

## PART I — REPORTING & ANALYTICS GAPS

| # | Feature | Status |
|---|---------|--------|
| I1 | **Confusion matrix** | ✅ done |
| I2 | **CAPD profile classification (Buffalo/Bellis-Ferre)** | ✅ done |
| I3 | **Phoneme feature-error analysis** (voicing/place/manner error %) | ❌ |
| I4 | **Adaptive staircase trajectory plot** (parameter vs trial, mark reversals) | ❌ |
| I5 | **Psychometric function fit** (% correct vs level, logistic fit, threshold+slope) | ❌ |
| I6 | **d′ / criterion (signal detection)** for yes-no tests | ❌ |
| I7 | **Real downloadable PDF** (currently on-screen printable card only) | ⚠️ |
| I8 | **Longitudinal dashboard** (all tests over time, one view) | ⚠️ have per-test trends |
| I9 | **Normative percentile + z-score** (not just pass/borderline/fail band) | ⚠️ |
| I10 | **Test-retest reliability (ICC) auto-computed** | ❌ |
| I11 | **Session comparison (A vs B side-by-side)** | ❌ |
| I12 | **Exportable per-trial CSV/JSON** | ⚠️ backend has export; surface in UI |
| I13 | **Auto-generated narrative summary** ("Temporal processing below age norm; binaural integration within normal limits…") | ❌ |

---

## PART J — DATA, BACKEND & INTEROPERABILITY

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| J1 | **Deploy the FastAPI backend** | ❌ | exists in repo, not connected/hosted |
| J2 | **Real cloud sync** (remote monitoring is a placeholder) | ❌ | connect app → backend |
| J3 | **HL7 FHIR export** | ❌ | USCDI has an audiogram data class; export results as FHIR Observations for EHR import |
| J4 | **NOAH / audiology-standard export** | ❌ | interoperability with clinical audiology software |
| J5 | **User accounts / auth** | ❌ | currently single local profile |
| J6 | **Multi-profile on one device** (family/clinic) | ⚠️ | dashboard groups by "patient" but no real profile switching |
| J7 | **Encrypted cloud backup / restore** | ⚠️ | local AES exists; no cloud |
| J8 | **GDPR/HIPAA consent + data-deletion flow** | ❌ | needed for real deployment |
| J9 | **Offline PWA install** (service worker, installable) | ⚠️ | Flutter web has SW; verify installable + offline stimuli cache |
| J10 | **Analytics (privacy-respecting) for adherence** | ❌ | |

---

## PART K — CONTENT / STIMULUS GAPS

| # | Feature | Status | Detail |
|---|---------|--------|--------|
| K1 | **Validated recorded speech (not TTS)** | ❌ | biggest scientific gap — reviewed native-speaker recordings |
| K2 | **4 speakers (2M, 2F)** | ❌ | 1 voice currently |
| K3 | **Real multitalker babble** | ❌ | white/generated noise now; need standard 4/8-talker babble |
| K4 | **Music masker** | ❌ | Angel Sound uses music background |
| K5 | **Larger word/sentence corpora** | ⚠️ | ~16 words; Angel Sound has 1000s. Expand pools |
| K6 | **Multi-language stimuli generation** (Hindi/Tamil/Telugu/Kannada WAVs) | ⚠️ | framework + pools defined; audio not generated |
| K7 | **CNC / NU-6 / CID W-22 standard word lists** | ❌ | recognized clinical word lists |
| K8 | **IEEE / HINT / BKB standard sentence lists** | ⚠️ | have generic sentences; add standard lists |
| K9 | **Picture library for children (real images/illustrations)** | ⚠️ | emoji only |
| K10 | **Content pack versioning + signature** | ✅ | have SHA-256 + HMAC |

---

## PART L — PLATFORM & DELIVERY

| # | Feature | Status |
|---|---------|--------|
| L1 | **Web app (GitHub Pages)** | ✅ deployed at /tan/ |
| L2 | **Android APK build** | ❌ (code supports; not built) |
| L3 | **iOS build** | ❌ |
| L4 | **Installable PWA (add to home screen, offline)** | ⚠️ |
| L5 | **Desktop (Windows/macOS/Linux) build** | ⚠️ code supports |
| L6 | **Tablet-optimized layout** | ⚠️ works but not tuned |
| L7 | **Landscape/portrait responsive** | ⚠️ tuned for wide; test portrait |
| L8 | **Low-bandwidth / lite mode** (skip CanvasKit, use HTML renderer) | ❌ |

---

## PART M — COMPETITOR FEATURE MATRIX

| Feature | Angel Sound | LACE | CAPDOTS | Acoustic Pioneer | HearBloom |
|---------|:-----------:|:----:|:-------:|:----------------:|:---------:|
| Clinical diagnostic tests | ⚠️ (assess only) | ❌ | ❌ | ✅ (screening) | ✅✅ (17+) |
| Vowel/consonant training | ✅✅ | ⚠️ | ❌ | ⚠️ | ✅ (new) |
| Dichotic integration training | ⚠️ | ❌ | ✅✅ | ✅ | ⚠️ |
| Speech-in-noise (adaptive) | ✅ | ✅✅ | ❌ | ⚠️ | ✅ |
| Spatial/LiSN-S | ❌ | ❌ | ❌ | ❌ | ⚠️ (training only) |
| Music training | ✅✅ | ❌ | ❌ | ❌ | ✅ |
| Gamification | ⚠️ | ⚠️ | ❌ | ✅✅ | ✅ |
| Kids mode / mascot | ✅✅ | ❌ | ❌ | ✅✅ | ❌ |
| Multi-speaker voices | ✅✅ (4) | ✅ | ✅ | ✅ | ❌ (1) |
| Adaptive difficulty | ✅ | ✅ | ✅ | ✅ | ✅ |
| Age-stratified norms | ⚠️ | ❌ | ⚠️ | ✅ | ✅✅ |
| Confusion matrix | ❌ | ❌ | ❌ | ⚠️ | ✅ (new) |
| Modern UI | ❌ (dated) | ⚠️ | ⚠️ | ✅ | ✅✅ (glass) |
| Free / open | ✅ | ❌ | ❌ | ❌ | ✅✅ |
| Web-based | ⚠️ | ✅ | ✅ | ✅ | ✅ |

**Where HearBloom already LEADS:** clinical diagnostic breadth, age-stratified cited norms, confusion matrix, modern UI, free/open, CAPD profile classification.
**Where HearBloom TRAILS:** validated recorded stimuli, 4 speakers, kids mode, dichotic-integration training depth, real backend/sync, mobile builds.

---

## PART N — PRIORITIZED ROADMAP (everything above, ordered)

### TIER 1 — Highest clinical/UX impact (build next)
1. LiSN-S spatial test (A1) — unique, no competitor has it well
2. Staggered Spondaic Word (A2) + DSI (A3) — complete the dichotic battery
3. Dichotic integration training (B1) — the CAPDOTS treatment
4. 4 speaker voices (K2) + real babble (K3) — credibility
5. SSQ12 + HHIE-S questionnaires (C1, C2)
6. Response-time flash, countdown ring, level progress map (G1, G2)
7. Adaptive staircase trajectory + psychometric fit + d′ (I4, I5, I6)
8. WCAG 2.2 AA audit — contrast, focus rings, number-key answers (H1, H3, H4)

### TIER 2 — Depth & polish
9. Kids Mode (light theme + mascot + sticker rewards) (F4, F5, G3)
10. Prosody, interhemispheric, reverberation, speech-tracking training (B3, B4, B8, B5)
11. Music: pitch ranking, timbre, emotion, rhythm-change (E2, E6, E8, E10)
12. Phoneme feature-error analysis + narrative report (I3, I13)
13. Real PDF download + session compare + percentile/z-score (I7, I9, I11)
14. Manual speed / stereo-mono / volume meter / pause-resume (G4)
15. Light theme + reduced motion + spectrogram toggle (G3)

### TIER 3 — Platform & scale
16. Deploy FastAPI backend + real sync + accounts (J1, J2, J5)
17. FHIR / NOAH export (J3, J4)
18. Android + iOS + PWA installable (L2, L3, L4)
19. Multi-language stimulus generation (K6)
20. Standard word/sentence lists (CNC, NU-6, IEEE, BKB) (K7, K8)

### TIER 4 — New domains (optional companions)
21. Tinnitus module (D1–D8) + THI/TFI (C7)
22. Hyperacusis / LDL (A8, D7)
23. Full audiogram + TMTF + spectral ripple + ITD/ILD JND (A7, A9, A10, A12)
24. Real-world scene training (B13)
25. Phonological-awareness games (B12)

---

## SUMMARY COUNT
- **Diagnostic tests to add:** 12 (LiSN-S, SSW, DSI, PST, figure-ground, phonemic synthesis, audiogram, LDL, TMTF, spectral ripple, IRN, ITD/ILD JND)
- **Training modules to add:** 13
- **Questionnaires to add:** 9
- **Tinnitus/hyperacusis features:** 8
- **Music gaps:** 6
- **Children's gaps:** 7
- **UI/UX improvements:** ~40
- **Accessibility items:** 13
- **Reporting features:** 13
- **Backend/data:** 10
- **Content/stimulus:** 10
- **Platform:** 8

**Total distinct upgrade items: ~150.**

*This is the complete, exhaustive list. Nothing intentionally omitted. Tiers 1–2 keep HearBloom purely software (buildable now); Tiers 3–4 need a backend, recordings, or are optional new domains.*
