# HearBloom vs Angel Sound — Complete Gap Analysis & Upgrade Plan v2
## Deep Research Edition (25 July 2026)

---

## ANGEL SOUND COMPLETE ARCHITECTURE (9 Modules, 70+ Groups)

### Module 1: BASIC (8 Groups)
| Group | What Angel Sound Has | HearBloom Status |
|-------|---------------------|-----------------|
| 1. Pure Tone Discrimination | 3AFC oddball, 52 tones, 4 levels (7-12 → 1 semitone separation) | ✅ HAVE (Pitch discrimination, adaptive) |
| 2. Environmental Sounds | 100 sounds, ID task, 2/4/6 AFC, quiet + noise, 4 levels | ✅ HAVE (Identification page, environmental pool) |
| 3. Male/Female Recognition | 4 speakers, discrimination → ID, 3 levels (cross-gender → same-gender → 4AFC ID) | ⚠️ PARTIAL (talker ID exists but only basic) |
| 4. Vowel Recognition | 1163 words×4 speakers, discrimination → ID, 5 levels, noise at level 5, 16 steps per level | ❌ MISSING — need vowel-specific training |
| 5. Consonant Recognition | 5132 stimuli, CVC/VCV/CV, 5 levels, noise at level 5, within-category contrasts | ❌ MISSING — need consonant-specific training |
| 6. Word Discrimination | 2400 words (6 categories × 100 × 4 speakers), 4AFC ID | ✅ HAVE (closed-set word recognition) |
| 7. Everyday Sentences | 1440 sentences, 4AFC, 4 noise levels (quiet/15/10/5 dB SNR) | ✅ HAVE (HINT adaptive + SIN) |
| 8. Music Appreciation | Instrument ID (9 instruments) + Melody ID (16 melodies) | ✅ HAVE (chord/instrument/melody pages) |

### Module 2: NOISE (same as Basic but all in background noise)
| What Angel Sound Has | HearBloom Status |
|---------------------|-----------------|
| All Basic groups repeated at multiple SNR levels (15/10/5/0 dB) | ⚠️ PARTIAL — we have adaptive SNR but not fixed-level multi-SNR training across ALL groups |

### Module 3: TELEPHONE (Basic through telephone bandwidth 300-3200 Hz)
| What Angel Sound Has | HearBloom Status |
|---------------------|-----------------|
| All groups filtered to phone bandwidth (300-3200 Hz) | ✅ HAVE (Telephone module inherits Foundation, applies bandpass) |

### Module 4: MELODIC CONTOUR (MCI)
| What Angel Sound Has | HearBloom Status |
|---------------------|-----------------|
| 9-choice contour identification, pure tones | ✅ HAVE (MCI page, 9 contours) |

### Module 5: OPENSET
| What Angel Sound Has | HearBloom Status |
|---------------------|-----------------|
| Open-set word/sentence typing, no choices given | ✅ HAVE (open-set page, typed response) |

### Module 6: MUSIC (Advanced)
| Group | What Angel Sound Has | HearBloom Status |
|-------|---------------------|-----------------|
| Instrument ID | More instruments, multi-level | ✅ HAVE |
| Pitch Ranking | Series of notes, rank from low to high | ❌ MISSING |
| Rhythm Discrimination | Same/different rhythmic patterns | ✅ HAVE (rhythm discrimination) |
| Melody Recognition | Familiar tunes, hum along | ✅ HAVE (familiar melody ID) |
| Music in Noise | Music excerpts + noise | ❌ MISSING |

### Module 7: AUDITORY RESOLUTION (8 Groups — Psychoacoustics)
| Group | What Angel Sound Has | HearBloom Status |
|-------|---------------------|-----------------|
| 1. Frequency Discrimination | Adaptive 3AFC oddball at multiple frequencies | ✅ HAVE (pitch/frequency JND) |
| 2. Modulation Detection | 3AFC, 5 rates (10-200 Hz), adaptive depth | ✅ HAVE (AM detection) |
| 3. Modulation Frequency Discrimination | Oddball rate, adaptive | ✅ HAVE (modulation rate) |
| 4. Temporal Gap Detection | Noise + tone gaps, 3 carrier types | ✅ HAVE (GIN + RGDT) |
| 5. Amplitude Discrimination | 3AFC level difference, 3 carriers | ✅ HAVE (loudness discrimination) |
| 6. Forward Masking | Tone detection after masker, varying gap | ✅ HAVE (tone detection with masking) |
| 7. Pure Tone Threshold | Detection at 250-4000 Hz, adaptive level | ⚠️ PARTIAL (tone detection exists but not full 5-freq audiogram) |
| 8. Music Rhythm Test | Rhythmic pattern changes in melodic sequences | ❌ MISSING — rhythmic change detection in melodies |

### Module 8: ASSESS (Functional Hearing Tests)
| What Angel Sound Has | HearBloom Status |
|---------------------|-----------------|
| Phoneme recognition test (vowels + consonants scored separately) | ❌ MISSING as a formal scored assessment |
| Music perception test (instrument + melody + pitch) | ⚠️ PARTIAL |
| Speech recognition test (words + sentences in quiet + noise) | ✅ HAVE |
| Auditory resolution test (all psychoacoustic thresholds reported) | ✅ HAVE |
| Cognitive test (short-term auditory memory) | ✅ HAVE (digit span) |

### Module 9: SCENE-BASED (Children's Learning Module)
| Group | What Angel Sound Has | HearBloom Status |
|-------|---------------------|-----------------|
| 1. Learning ABC | 26 letters, 4 environments (quiet/phone/10dB/0dB) | ❌ MISSING |
| 2. Learning Food Names | 100 foods, 4 environments | ❌ MISSING (but have food ID with emoji) |
| 3. Learning Animal Names | 100 animals, 4 environments | ❌ MISSING (but have animal ID with emoji) |
| 4. Learning Colors | 12 colors, 4 environments | ✅ HAVE (color identification) |
| 5. Learning Numbers | 20 numbers, 4 environments | ✅ HAVE (digit recognition) |
| 6. Phonetic Contrast | Minimal pair words, 4 environments | ⚠️ PARTIAL (phonemic contrast training exists but not multi-environment) |

---

## WHAT HEARBLOOM IS MISSING (Complete List)

### A. SPEECH PERCEPTION TRAINING (Critical Gaps)

| # | Feature | Priority | Details |
|---|---------|----------|---------|
| 1 | **Vowel Recognition Training** | HIGH | h_d words (heed/hid/head/had/hod/hawed/hoed/hood/who'd/hud/heard), 4 speakers, discrimination → identification, 5 levels with progressive difficulty + noise at level 5. Angel Sound has 1163 words × 4 speakers for this. |
| 2 | **Consonant Recognition Training** | HIGH | Initial/medial/final consonants, CVC (bat/pat/mat), VCV (aBa/aDa), CV (Ba/Da), 4 speakers, 5 levels + noise. Angel Sound has 5132 stimuli. |
| 3 | **Talker Discrimination (Gender + Individual)** | MEDIUM | Same word, different speakers. Level 1: male vs female (easy). Level 2: same gender (hard). Level 3: 4-speaker identification. |
| 4 | **Multi-SNR Fixed Training** | MEDIUM | Run ANY training group at fixed SNR levels (quiet, 15, 10, 5, 0 dB) instead of only adaptive. Shows how performance degrades with noise. |

### B. MUSIC & AUDITORY (Gaps)

| # | Feature | Priority | Details |
|---|---------|----------|---------|
| 5 | **Pitch Ranking** | MEDIUM | Present 3-5 notes, user sorts them low-to-high by tapping in order |
| 6 | **Music in Noise** | LOW | Music excerpts with speech/noise background, identify the piece |
| 7 | **Rhythmic Change Detection in Melodies** | MEDIUM | Same melody with one rhythmic change, detect where |
| 8 | **Full Pure-Tone Detection (5-freq)** | LOW | Adaptive threshold at 250/500/1000/2000/4000 Hz — a simplified audiogram (research only, not clinical) |

### C. CHILDREN'S MODULE (Gaps)

| # | Feature | Priority | Details |
|---|---------|----------|---------|
| 9 | **Learning ABC** | MEDIUM | Letter identification across 4 environments |
| 10 | **Category Vocabulary Builder** | MEDIUM | Foods/animals/family/time words, 4 environments, picture + audio |
| 11 | **Multi-Environment Phonetic Contrast** | HIGH | Run phonemic pairs in quiet → phone → noise (like Angel Sound's Scene module) |

### D. UI/UX IMPROVEMENTS (From Angel Sound Screenshot Comparison)

| # | Issue | Angel Sound Does | HearBloom Should |
|---|-------|-----------------|-----------------|
| 12 | **Visual preview of all stimuli** | "Preview" button lets user listen to ALL sounds in a group before starting | Add a preview/familiarization step before each test showing all possible stimuli |
| 13 | **Progress graph visible during training** | Shows a live performance curve (like the screenshot's "Noise Module" image) | Add a live accuracy-over-trials mini chart during the session |
| 14 | **Spectrogram/waveform visualization** | Shows spectrograms of sounds (Telephone/Auditory module screenshots) | Add optional waveform/spectrogram display when playing a sound |
| 15 | **Favorite/custom settings** | "Favorite" button to save preferred module configurations | Add bookmark/favorite for quick re-launch of specific test configs |
| 16 | **Speed control** | Speed slider in the bottom toolbar | Already have adaptive speed; add manual speed override |
| 17 | **Stereo/mono toggle** | "Stereo" option in toolbar | Add mono/stereo/left-only/right-only playback mode selector |
| 18 | **Volume meter** | Visual volume/level indicator | Add a level meter showing current playback volume (reassures user audio is working) |
| 19 | **Module thumbnail previews** | Each module shows a visual preview image of what it looks like | Add visual previews/thumbnails for each module on the home screen |
| 20 | **Print session results** | "PRINT" menu in top bar | Already have — enhance with actual PDF download |
| 21 | **Session management** | "SESSION" menu to save/load/compare sessions | Add session save points, naming, and comparison view |
| 22 | **Help/tutorial per module** | "HELP" accessible from any screen | Add contextual help tooltips on every test explaining what's being measured and why |

### E. ASSESSMENT & REPORTING (Gaps)

| # | Feature | Priority | Details |
|---|---------|----------|---------|
| 23 | **Phoneme Score Report** | HIGH | Break down word recognition into: vowel%, initial consonant%, final consonant%, place/manner/voicing error patterns |
| 24 | **Confusion Matrix** | HIGH | Show which sounds are confused with which (e.g., /p/ confused with /b/ 60% of time) — this is standard clinical reporting |
| 25 | **Comparison to previous sessions** | MEDIUM | Side-by-side score comparison (session 1 vs session N) with significance test |
| 26 | **Expected vs Actual performance curve** | MEDIUM | Show the adaptive track trajectory (parameter over trials) — how the staircase moved |
| 27 | **Per-trial response log** | LOW | Exportable log of every stimulus presented and response given (for research) |

### F. TECHNICAL/INFRASTRUCTURE (Gaps)

| # | Feature | Priority | Details |
|---|---------|----------|---------|
| 28 | **Multiple speaker voices** | HIGH | Angel Sound uses 4 speakers (2M, 2F) for everything. We use 1 generated voice. Need at minimum 2M + 2F generated or recorded voices. |
| 29 | **Real multitalker babble** | MEDIUM | Our noise is white/generated. Need real 4-talker babble (standard in QuickSIN/HINT) |
| 30 | **Phone-bandwidth simulation** | LOW | Apply 300-3200 Hz bandpass to any stimulus for "telephone" training (already in catalog but not in new tests) |
| 31 | **Background music noise** | MEDIUM | Angel Sound uses music as background noise (not just white/babble). Add music masker option |
| 32 | **Stimulus preview mode** | HIGH | Before any test, let user browse and listen to all possible stimuli to familiarize |
| 33 | **Live accuracy counter** | MEDIUM | Show running accuracy % during the session (not just at end) |
| 34 | **Trial-by-trial difficulty visualization** | LOW | Show the adaptive track parameter on-screen as it changes |

---

## UI DESIGN IMPROVEMENTS (From Screenshot Analysis)

Angel Sound's UI is dated (2010s look) but has FUNCTIONAL features we lack:

| # | What to Add | Why |
|---|------------|-----|
| 35 | **Live performance chart** | Angel Sound shows a real-time line graph of performance. We should show a mini sparkline that updates each trial. |
| 36 | **Stimulus count badge** | Each module card shows how many stimuli it contains (e.g., "100 environmental sounds"). Shows depth. |
| 37 | **Level progress indicator** | Within a multi-level training group, show which levels are completed vs current vs locked. Like a game chapter map. |
| 38 | **Audio waveform animation** | When audio is playing, show an animated waveform (even if cosmetic) to confirm audio is active. Solves the "did it play?" confusion. |
| 39 | **Response time feedback** | After each trial, briefly flash response time (e.g., "620ms"). Fast = good, slow = might need more practice. |
| 40 | **Correct answer reveal** | On wrong answer, ALWAYS show what the correct answer was (audio + visual). Angel Sound does this with "Correct answer is highlighted in green". |
| 41 | **Category tabs within modules** | Angel Sound's Word training has 6 categories (Animal/Food/Color/Family/Number/Time). Show these as tabs, not mixed. |
| 42 | **Session timer with target** | Show "5:30 / 15:00" target time. Helps motivation ("almost done!"). |
| 43 | **Encouragement messages** | After streaks: "Great job! 5 in a row!" After mistakes: "Keep going, this one was tough." |

---

## COMPLETE PRIORITIZED IMPLEMENTATION PLAN

### IMMEDIATE (Next Build — Biggest Impact)

1. **Vowel Recognition Training** — the single biggest gap vs Angel Sound
2. **Consonant Recognition Training** — paired with vowels, covers all phonemes  
3. **Confusion Matrix in reports** — shows exactly where errors happen
4. **Live mini-chart during sessions** — confirms progress visually
5. **Audio playing animation** — solves "did it play?" UX confusion
6. **Correct answer always revealed** — critical for learning
7. **Encouragement messages** — retention/engagement
8. **Stimulus preview mode** — familiarization before test

### SHORT-TERM (Phase 5)

9. Talker discrimination (gender + individual)
10. Multi-SNR fixed training mode
11. Multiple speaker voices (generate 2M + 2F with edge-tts)
12. Phoneme Score Report (vowel% + consonant% breakdown)
13. Level progress indicator (game chapter map)
14. Session comparison view
15. Response time feedback
16. Per-trial response log export

### MEDIUM-TERM (Phase 6)

17. Children's ABC module
18. Category vocabulary builder (with images)
19. Pitch ranking exercise
20. Real multitalker babble noise
21. Phone-bandwidth simulation for all tests
22. Background music masker option
23. Contextual help tooltips per test
24. Adaptive track visualization (staircase graph)

---

## SUMMARY: What Angel Sound Has That We DON'T

| Angel Sound Feature | Stimuli Count | Our Gap |
|--------------------:|:-------------|:--------|
| Vowel training (5 levels, 16 steps each) | 4,652 words | ❌ MISSING |
| Consonant training (5 levels, 16 steps each) | 5,132 words | ❌ MISSING |
| 4 different speakers on everything | 4 speakers | ❌ We have 1 |
| Preview all stimuli before test | N/A | ❌ MISSING |
| Live performance curve | N/A | ❌ MISSING |
| Scene-based children's learning (6 groups) | ~400 items | ⚠️ Partial |
| Confusion matrix report | N/A | ❌ MISSING |
| Multi-environment (quiet/phone/10dB/0dB) on everything | N/A | ⚠️ Partial |

**Our advantages over Angel Sound:**
- Dark modern UI (theirs is 2010s style)
- Clinical diagnostic tests (DPT/FPT/MLD/RGDT/DDT) — Angel Sound is training-only
- Adaptive staircase with normative interpretation
- Gamification (points/streaks/badges)
- Age-stratified norms with citations
- CAPD profile classification (Buffalo/Bellis-Ferre)
- Session trends with regression
- Difficulty level selector
- Keyboard shortcuts
- Bottom navigation
- Onboarding flow

---

*This gap analysis is based on full reading of all 9 Angel Sound module documentation pages, the AAA/ASHA CAPD guidelines, the Indian CAPD survey (2023), StatPearls CAPD chapter, LACE literature, and SCAN-3 test specifications.*
