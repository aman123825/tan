# HearBloom — Comprehensive Research-Based Upgrade Plan
## Deep Research Edition (July 2026)

---

## SOURCES CONSULTED

1. **AAA Clinical Practice Guidelines** (2010) — Diagnosis, Treatment and Management of CAPD
2. **ASHA (2005)** — Technical Report on (Central) Auditory Processing Disorders
3. **Bellis & Beck (2000)** — "Central Auditory Processing in Clinical Practice" (full text reviewed)
4. **VA NCRAR CAPD Working Group** — Official test categorization and tools
5. **Indian CAPD Survey (Springer 2023, 83 clinics)** — Most-used screening/diagnostic tests in India
6. **Danish CAPD Battery** (2017, JASA) — Filtered Words + Dichotic Digits + Gap Detection + BMLD
7. **Musiek (1994)** — Frequency and Duration Pattern Tests normative data
8. **Musiek (2005)** — Gaps-in-Noise (GIN) test development and norms
9. **Killion et al. (2004)** — QuickSIN development and SNR-loss bands
10. **Wilson (2003)** — Words-in-Noise (WIN) test
11. **Angel Sound** (Emily Fu Foundation) — Full module list and training protocols
12. **LACE** (Sweetow & Sabes 2006) — Training modules: speech-in-noise, competing speakers, time-compressed, auditory memory
13. **SCAN-3** (Keith) — Commercial CAPD screening battery subtests
14. **Buffalo Model** (Katz 1991) — Decoding, Tolerance-Fading Memory, Integration, Organization
15. **Bellis/Ferre Model** (1992) — Auditory Decoding, Prosodic, Integration subtypes
16. **Interacoustics MLD protocol** — Clinical MLD implementation details
17. **Frontiers in Neurology (2021)** — Meta-analysis of DPT/FPT/GIN sensitivity/specificity

---

## PART 1: DIAGNOSTIC TESTS TO ADD

### Category A: Temporal Ordering (Highest Priority — 78% of Indian clinics use these)

#### 1. Duration Pattern Test (DPT)
- **What it measures:** Temporal ordering / sequencing — interhemispheric transfer
- **Stimulus:** Three tones at 1000 Hz, each either SHORT (250 ms) or LONG (500 ms)
- **ISI:** 300 ms between tones
- **Rise/fall time:** 10 ms
- **Presentation:** 30 sequences, monaural (test each ear separately)
- **Response:** Verbal labeling ("long-short-long") or humming the pattern
- **Scoring:** Percent correct per ear
- **Norms (Musiek 1994):**
  - Adults (18-50): ≥ 73% per ear
  - Children (7-11): ≥ 60% per ear (age-stratified needed)
- **Sensitivity:** 86% for confirmed brain pathology (Musiek, Baran & Pinheiro 1990)
- **Meta-analysis effect:** -21.93% difference (95% CI: -26.58 to -17.29) between CAPD and controls

#### 2. Frequency Pattern Test (FPT)
- **What it measures:** Temporal ordering / pitch pattern recognition
- **Stimulus:** Three tones, each either LOW (880 Hz) or HIGH (1122 Hz)
- **Duration:** 150-200 ms each tone
- **ISI:** 150 ms between tones
- **Rise/fall time:** 10 ms
- **Presentation:** 30 sequences, monaural (each ear)
- **Response:** Verbal labeling ("high-low-high") or humming
- **Scoring:** Percent correct per ear
- **Norms (Musiek 1994):**
  - Adults: ≥ 78% per ear
  - Children (7-11): ≥ 65% per ear
- **Sensitivity:** 83% for confirmed brain pathology
- **Meta-analysis effect:** -31.37% difference (95% CI: -40.55 to -22.19)
- **Note:** FPT is MORE sensitive than DPT for detecting CAPD (larger effect size)

#### 3. Implementation in HearBloom:
- Synthesize 1000 Hz tones at two durations (DPT) or 880/1122 Hz at fixed duration (FPT)
- Present 3-tone sequence, user taps pattern from 6 options (LLL, LLS, LSL, SLL, SLS, SSL, LSS, SSS → actually 8 permutations but only 6 are used clinically: LLS, LSL, SLL, SLS, LSS, SSL)
- Score per ear, compare to age-stratified norms
- **HearBloom advantage:** can present choices as TAP response (more accessible than verbal for remote testing)

---

### Category B: Temporal Resolution (Already Partially Implemented)

#### 4. Gaps-in-Noise (GIN) — ALREADY IN HEARBLOOM ✓
- Current: 3AFC adaptive gap detection
- **Enhancement needed:** Add the CLINICAL version:
  - 6-second broadband noise segments with 0-3 embedded gaps
  - Gap durations: 2, 3, 4, 5, 6, 8, 10, 12, 15, 20 ms
  - Listener presses button when they hear a gap (detection, not AFC)
  - Score: Approximate threshold (shortest gap detected ≥ 4/6 times) + % correct
  - This is different from our current adaptive 3AFC — both should coexist

#### 5. Random Gap Detection Test (RGDT)
- **What it measures:** Temporal resolution across frequencies
- **Stimulus:** Paired tones (click-gap-click) at 500, 1000, 2000, 4000 Hz
- **Gap durations:** 0, 2, 5, 10, 15, 20, 25, 30, 40 ms
- **Response:** "One sound" or "two sounds"
- **Scoring:** Threshold at each frequency (smallest gap with ≥ 2/3 correct detections)
- **Norm:** Combined threshold ≤ 20 ms (children 7+); adults < 10 ms
- **vs GIN:** RGDT tests across frequencies; GIN uses broadband noise. Both valid.

---

### Category C: Binaural Interaction (Most-Used Test in India)

#### 6. Masking Level Difference (MLD)
- **What it measures:** Binaural processing / brainstem integration
- **Procedure (from Interacoustics clinical protocol):**
  1. Present 500 Hz pulsed tone + narrowband noise at 60-65 dB to BOTH ears
  2. **Condition 1 (S₀N₀):** Signal and noise same phase in both ears → find threshold
  3. **Condition 2 (SπN₀):** Signal phase-inverted in one ear, noise same → find threshold
  4. **MLD = threshold(S₀N₀) - threshold(SπN₀)**
- **Scoring:** The MLD value in dB
- **Norms:**
  - Adults: MLD ≥ 10-12 dB at 500 Hz (normal binaural processing)
  - Abnormal: MLD < 6 dB suggests brainstem-level dysfunction
  - Children (7+): MLD ≥ 9 dB
- **Clinical significance:** Most commonly abnormal test in brainstem lesions
- **Implementation:** Requires precise phase control (stereo headphones mandatory); adaptive threshold tracking in each condition

#### 7. Binaural Fusion Test
- **What it measures:** Integration of information across ears
- **Stimulus:** A word is split — low-pass filtered to one ear, high-pass filtered to the other
- **Cutoff:** Typically 500-700 Hz crossover (or 1000 Hz)
- **Response:** Identify the word (requires integrating both ears' input)
- **Scoring:** Percent correct
- **Norm:** ≥ 70% correct
- **Relevance to ANSD:** Directly tests the neural integration that ANSD disrupts



---

### Category D: Dichotic Listening (Tests Binaural Separation/Integration)

#### 8. Dichotic Digits Test (DDT) — ALREADY IN HEARBLOOM ✓
- Current implementation: different digit each ear, report cued ear
- **Enhancement needed:**
  - Add FREE RECALL mode (report BOTH digits — tests divided attention)
  - Add DIRECTED attention mode (report LEFT only, then RIGHT only — tests selective attention)
  - Compute: Right Ear Advantage (REA), Left Ear score, Inter-ear difference
  - Age-stratified norms: adults ≥ 90%/ear; children vary by age (85% at age 7, 90% at age 10)

#### 9. Competing Sentences Test (CST)
- **What it measures:** Binaural separation with linguistic material
- **Stimulus:** Target sentence in one ear at 35 dB SL, competing sentence in other ear at 50 dB SL
- **Response:** Repeat the target sentence
- **Scoring:** Percent of sentences correct per ear
- **Norms:** ≥ 90% correct in the target ear
- **Advantage over digits:** More ecologically valid (real-world competing speech)
- **Implementation:** Need sentence pairs — can use generated TTS with different voices/timing

#### 10. Dichotic Sentence Identification (DSI)
- **Stimulus:** Two different sentences simultaneously, one per ear, at 50 dB SL
- **Response (free recall):** Identify both sentences from a closed set of 6-10 options
- **Response (directed):** Identify only the sentence in the cued ear
- **Scoring:** % correct per ear, per attention condition
- **Clinical value:** Area Under Curve = 0.83 for detecting CAPD (JAMA Otolaryngology)
- **Better than DDT for:** Older adults, mild CAPD (more challenging material)

#### 11. Competing Words Test
- **Stimulus:** Different single word to each ear simultaneously
- **Modes:** Free recall (report both) or Directed (report one ear only)
- **Child-friendly:** Simpler than sentences, can use picture pointing
- **Scoring:** % correct per ear in each condition
- **Norms:** Free recall ≥ 80%/ear; directed ≥ 90%/ear (adults)

#### 12. Staggered Spondaic Word Test (SSW)
- **The classic CAPD test** (Katz 1962, most widely used worldwide)
- **Stimulus:** Two spondaic words (e.g., "upstairs/downtown"), overlapping in time
  - Non-competing portions (first syllable of word 1, last syllable of word 2) in one ear
  - Competing portions (overlap) presented to both ears
- **40 items**, alternating which ear starts
- **Complex scoring:** Right Competing, Left Competing, Right Non-competing, Left Non-competing
- **Categories (Buffalo Model):**
  - High RC errors → Auditory Decoding deficit (left temporal)
  - High LC errors → Integration/Organization deficit (right temporal or corpus callosum)
- **Implementation complexity:** HIGH — needs precise timing control for overlapping spondees
- **Priority:** Phase 2 (after simpler dichotic tests)

---

### Category E: Monaural Low-Redundancy Speech (Tests Auditory Closure)

#### 13. Filtered Speech Test
- **What it measures:** Ability to understand speech when frequency information is removed
- **Stimulus:** Monosyllabic words, low-pass filtered at 1000 Hz or 1500 Hz
- **Removes:** All high-frequency consonant cues (fricatives, plosives)
- **Presentation:** 50 words per ear, monaural, at 50 dB SL
- **Scoring:** Percent correct per ear
- **Norms:** ≥ 70% per ear (adults); age-stratified for children
- **What it reveals:** Auditory closure ability — filling in missing information
- **Part of:** SCAN-3 battery ("Filtered Words" subtest), Danish CAPD battery
- **Implementation:** Apply low-pass FIR filter to speech WAVs before playback

#### 14. Time-Compressed Speech Test
- **What it measures:** Ability to understand rapid speech (temporal compression)
- **Stimulus:** Monosyllabic words compressed to 60% or 65% of original duration
- **Optional addition:** Compression + 0.3s reverberation (much harder)
- **Presentation:** 50 words per ear, monaural
- **Scoring:** Percent correct at each compression level
- **Norms:**
  - 60% compression alone: ≥ 70% correct
  - 60% compression + reverberation: ≥ 50% correct
- **Clinical relevance:** Targets temporal processing speed — key ANSD deficit
- **LACE uses this:** Adaptive speed from 1.0x to 2.0x; we should match
- **Implementation:** Use WSOLA (Waveform Similarity Overlap-Add) time-stretch algorithm

#### 15. Speech-in-Noise (Sentence Level) — ENHANCEMENT OF EXISTING
- **Current HearBloom:** Single words in babble noise (4AFC)
- **Clinical gold standard:** Full sentences (QuickSIN / HINT style)
- **QuickSIN protocol:**
  - 6 sentences per list, each at a different SNR (25, 20, 15, 10, 5, 0 dB)
  - 5 key words per sentence; score correct keywords
  - SNR-loss = 25.5 - total words correct
  - Interpretation: 0-3 normal, 3-7 mild, 7-15 moderate, >15 severe
- **HINT protocol (adaptive):**
  - Sentences presented in speech-spectrum noise
  - SNR adapts: increase noise 2 dB after correct, decrease 2 dB after incorrect
  - Report SRT-50 (SNR at which 50% sentences are understood)
  - Norm: SRT ≈ -2.9 dB SNR (young adults with normal hearing)
- **WIN protocol:**
  - 35 Northwestern University Auditory Test No. 6 words
  - Presented at 7 SNRs (24, 20, 16, 12, 8, 4, 0 dB) — 5 words per SNR
  - Score: 50% correct point (interpolated)
- **Recommendation:** Implement HINT-style adaptive (matches our existing engine) + fixed-SNR scoring like QuickSIN for normative comparison



---

## PART 2: TRAINING MODULES TO ADD (from Angel Sound + LACE + Literature)

### From LACE (Listening and Communication Enhancement):
| # | Module | Protocol | Adaptive? |
|---|--------|----------|-----------|
| 16 | **Speech in babble** | Sentences in 4-talker babble; SNR adapts | Yes — 1 dB steps |
| 17 | **Competing speaker** | Target sentence + distractor sentence (different talker); identify target content | Yes — adjust level difference |
| 18 | **Time-compressed speech** | Sentences at 1.0x → 1.3x → 1.5x → 2.0x speed | Yes — speed adapts to accuracy |
| 19 | **Auditory memory (missing word)** | Sentence with a word replaced by noise; identify the missing word from context | Fixed difficulty; score % correct |
| 20 | **Auditory working memory** | Hear a list of items, recall them in reverse order | Adaptive span length |

### From Angel Sound:
| # | Module | Protocol | What It Trains |
|---|--------|----------|----------------|
| 21 | **Phonemic contrast pairs** | Minimal pairs (bat/pat, sin/shin, cap/cab) — 2AFC | Fine spectral discrimination |
| 22 | **Vowel recognition** | Isolated vowels in h_d context (heed/hid/head/had/hod/hawed/hoed/hood/who'd) | Formant perception |
| 23 | **Consonant recognition** | Initial or final consonant ID in CVC context | Place/manner/voicing |
| 24 | **Environmental sound-to-speech continuum** | Level 1: pure tones → Level 2: environmental → Level 3: words → Level 4: sentences → Level 5: sentences in noise | Progressive complexity |
| 25 | **Music perception** | Instrument ID → Melody ID → Pitch ranking → Rhythm discrimination | Non-speech auditory training |
| 26 | **Bilateral training** | Different stimuli to each ear; report from target ear | Binaural separation skill building |
| 27 | **Talker discrimination** | Same sentence spoken by different talkers; identify which talker said the target | Voice recognition |

### From FastForWord / HearBuilder:
| # | Module | Protocol | What It Trains |
|---|--------|----------|----------------|
| 28 | **Following directions** | "Put the red square above the blue circle" — multi-step auditory instructions | Auditory comprehension + memory |
| 29 | **Phonological awareness** | Sound blending, segmentation, rhyming — gamified | Reading readiness / phonemic awareness |
| 30 | **Auditory figure-ground** | Target word/sentence in progressively louder background noise | Selective attention |

---

## PART 3: ACCURACY & PRECISION IMPROVEMENTS

| # | Improvement | Current State | Target State | How |
|---|-------------|--------------|-------------|-----|
| 31 | **Age-stratified norms** | Single adult norm for each test | Norms for: 7-8, 9-10, 11-12, 13-17, 18-50, 51-65, 65+ | Store DOB at profile creation; lookup age-band norms |
| 32 | **Ear-specific results for ALL monaural tests** | Only dichotic reports per-ear | Every monaural test (GIN, DPT, FPT, filtered speech, compressed) reports L vs R separately | Add ear-selection to monaural test flow; present each ear independently |
| 33 | **Test-retest reliability** | Not tracked | Compute split-half or test-retest ICC when ≥ 2 sessions exist | Store all trials; on session 2+, compute ICC/Pearson between sessions |
| 34 | **95% Confidence intervals** | Show ± SD only | Show ± 1.96×SD/√n for clinical precision | Formula: CI = threshold ± z × (SD / √(n_reversals)) |
| 35 | **Practice effect detection** | Not tracked | Flag if session 2 is significantly better than session 1 (learning, not real improvement) | Compare session pairs with paired t-test; flag if p < 0.05 AND diff > 1 SD |
| 36 | **Response time analysis** | Record latency but don't analyze | Flag: <200ms = possible guessing; >5000ms = possible attention lapse; compute median RT | Add percentile bands to RT; exclude outlier trials from threshold calculation |
| 37 | **Catch trials** | None | Insert 10% "easy obvious" trials; if accuracy on catch < 90%, flag invalid test | Random easy items (e.g., 20ms gap in GIN) interspersed |
| 38 | **Multi-session trend analysis** | Single session only | Show threshold/accuracy over time with linear regression + p-value | Store session history (DONE); fit trend line; report slope + significance |
| 39 | **Fatigue correction** | Record fatigue but don't use it | If performance drops > 15% in final quarter vs first quarter, flag fatigue effect | Compare Q1 vs Q4 accuracy within session |
| 40 | **Cross-test profile** | Each test reported independently | Generate a CAPD profile: "temporal processing deficit" / "binaural integration deficit" / "auditory closure deficit" based on pattern of results across tests | Rule-based classification following Buffalo/Bellis-Ferre models |

---

## PART 4: CLINICAL WORKFLOW & USABILITY

| # | Feature | Description | Priority |
|---|---------|-------------|----------|
| 41 | **SCAP Screening Questionnaire** | 12-item parent/teacher questionnaire (Yathiraj & Mascarenhas 2004) — digital, auto-scored, cutoff ≥ 9 triggers referral | HIGH — used by 75% of Indian clinics |
| 42 | **Automated Battery Presets** | "CAPD Screening" = GIN + DDT + DPT (30 min); "CAPD Full" = adds FPT + MLD + SIN + Filtered (60 min); "ANSD Focus" = GIN + MLD + SIN + Compressed (45 min) | HIGH |
| 43 | **PDF Clinical Report** | One-page summary: patient info, battery results table, norm comparison, profile classification, recommendations | HIGH — clinicians need printable reports |
| 44 | **Clinician Dashboard** | Web view: all patients, session timeline, flagged results, batch export | MEDIUM |
| 45 | **Rest Breaks** | Mandatory 2-min rest after every 10-15 min of testing (AAA guideline) | HIGH — already partially implemented in battery runner |
| 46 | **Practice Trials** | 3-5 practice items before each test begins (with feedback) — standard clinical protocol | HIGH — ensures patient understands the task |
| 47 | **Multi-language stimuli** | Hindi, Tamil, Telugu, Kannada speech sets (India-focused) | MEDIUM — needs native speaker recordings |
| 48 | **Remote monitoring** | Clinician sets a home program; patient results sync to dashboard | MEDIUM |
| 49 | **Gamification** | Points, streaks, levels, badges, daily goals — keeps engagement | MEDIUM — for training modules only, never diagnostic |
| 50 | **Headphone verification** | Play a tone only in one ear; user confirms which ear heard it — proves headphones are on correctly | HIGH — critical for dichotic/monaural ear-specific tests |

---

## PART 5: COMPETITOR REVERSE-ENGINEERING SUMMARY

### Angel Sound (Emily Fu Foundation)
- **Unique strength:** Open platform for any language; animated audio-visual feedback
- **Modules we're missing:** Phonemic contrasts (vowels/consonants separately), bilateral training, remote data access for clinicians
- **What they do better:** Visual representation of the correct answer (shows frequency spectrum or pattern after response)
- **What we do better:** Deterministic adaptive engine with reversal-based thresholds; normative interpretation with citations; offline-first encrypted persistence

### LACE (Sweetow & Sabes)
- **Unique strength:** Competing speakers task (hardest real-world scenario); daily progress emails
- **Modules we're missing:** Competing speakers, time-compressed speech, "missing word" closure task
- **What they do better:** Validated across 10+ clinical trials; insurance-reimbursable
- **What we do better:** Full diagnostic battery (not just training); ANSD-specific safety (volume lock); dark glassmorphic UI

### SCAN-3 (Keith)
- **Unique strength:** Standardized normative data (large sample, age-stratified); validated for clinical diagnosis
- **Subtests:** Filtered Words, Auditory Figure-Ground (+8 dB SNR), Competing Words (directed/free), Competing Sentences, Gap Detection, Time-Compressed Sentences
- **What we're missing:** Filtered Words, Auditory Figure-Ground (word-in-noise at fixed SNR), standardized scoring with percentile ranks
- **What we do better:** Adaptive (not fixed difficulty); more tests; synthesized stimuli (no copyright dependency)

### FastForWord (Scientific Learning)
- **Unique strength:** Gamification + intensity (100 min/day × 30 days)
- **Evidence:** Meta-analysis found NO significant effect on reading/language outcomes (Strong et al. 2011) — controversial
- **What they do better:** Engagement/retention (game mechanics keep kids coming back)
- **What we should take:** Daily streak tracking, achievement badges, progress visualization — for TRAINING only

---

## PART 6: RECOMMENDED IMPLEMENTATION PHASES

### Phase 1 — Make It Clinically Diagnostic (4-6 weeks)
1. Duration Pattern Test (DPT) — synthesized, 30 trials per ear
2. Frequency Pattern Test (FPT) — synthesized, 30 trials per ear
3. Masking Level Difference (MLD) — adaptive threshold, binaural
4. Digit Span backward — extend existing forward-only to include backward
5. Clinical GIN mode (detection in continuous noise, not just 3AFC)
6. Age-stratified norms for ALL tests (store DOB)
7. Headphone verification check
8. Practice trials before each test
9. SCAP screening questionnaire (digital)
10. Automated CAPD battery presets (screening / full / ANSD-focus)
11. Cross-test CAPD profile classification

### Phase 2 — Expand the Battery (4-6 weeks)
12. Competing Sentences Test
13. Filtered Speech Test (low-pass 1000 Hz)
14. Time-Compressed Speech (60% + optional reverberation)
15. Binaural Fusion Test
16. Dichotic Digits: add free-recall + directed attention modes
17. HINT-style adaptive sentence-in-noise (full sentences)
18. Random Gap Detection Test (RGDT) across frequencies
19. PDF clinical report generation
20. Multi-session trend analysis with graphs

### Phase 3 — Training Effectiveness (4-6 weeks)
21. Competing speakers training (from LACE)
22. Time-compressed speech training (adaptive speed)
23. Phonemic contrast training (minimal pairs)
24. Auditory closure training (filtered/degraded speech)
25. Environmental sound-to-speech continuum (progressive)
26. Auditory working memory (forward + backward spans, adaptive)
27. Following directions (multi-step auditory instructions)
28. Gamification layer (points, streaks, badges — training only)
29. Daily progress tracking with trend charts

### Phase 4 — Clinical Workflow & Scale (ongoing)
30. Clinician dashboard (web)
31. Remote monitoring / home program assignment
32. Multi-language stimuli (Hindi, Tamil, Telugu, Kannada)
33. Insurance/billing code documentation (CPT 92506, 92620, 92621)
34. Validation study protocol (compare HearBloom results to gold-standard clinical battery)

---

## KEY NORMATIVE REFERENCE TABLE

| Test | Measure | Normal (Adults 18-50) | Normal (Children 7-11) | Abnormal Cut-off | Citation |
|------|---------|----------------------|----------------------|-----------------|----------|
| GIN | Gap threshold | ≤ 6 ms | ≤ 8 ms | > 8 ms | Musiek et al., 2005 |
| DPT | % correct/ear | ≥ 73% | ≥ 60% | < 60% | Musiek, 1994 |
| FPT | % correct/ear | ≥ 78% | ≥ 65% | < 65% | Musiek, 1994 |
| MLD (500 Hz) | dB difference | ≥ 10-12 dB | ≥ 9 dB | < 6 dB | Wilson et al., 2003 |
| DDT | % correct/ear | ≥ 90% | ≥ 85% (age 7), ≥ 90% (age 10) | < 80% | Musiek, 1983 |
| QuickSIN | SNR-loss | 0-3 dB | N/A | > 3 dB (mild); > 7 (moderate) | Killion et al., 2004 |
| HINT | SRT-50 | -2.9 dB SNR | N/A | > 0 dB | Nilsson et al., 1994 |
| Filtered Speech | % correct/ear | ≥ 70% | ≥ 60% | < 50% | Willeford, 1977 |
| Compressed (60%) | % correct | ≥ 70% | ≥ 60% | < 50% | Bornstein et al., 1994 |
| Compressed + reverb | % correct | ≥ 50% | N/A | < 35% | Wilson et al., 1994 |
| Binaural Fusion | % correct | ≥ 70% | ≥ 60% | < 50% | Matzker, 1959 |
| Digit Span Forward | Max span | 7 ± 2 | 5 ± 1 (age 7), 6 ± 1 (age 10) | < 5 | Wechsler, 1997 |
| Digit Span Backward | Max span | 5 ± 2 | 3 ± 1 (age 7), 4 ± 1 (age 10) | < 3 | Wechsler, 1997 |
| RGDT | Combined threshold | < 10 ms | ≤ 20 ms | > 20 ms | Keith, 2000 |
| CST | % correct/ear | ≥ 90% | ≥ 80% | < 70% | Willeford, 1977 |

---

## CAPD SUBTYPE CLASSIFICATION (Buffalo Model + Bellis/Ferre)

After running the full battery, classify the pattern:

| Profile | Key Deficits | Failed Tests | Remediation Focus |
|---------|-------------|-------------|-------------------|
| **Auditory Decoding** | Phonemic discrimination, auditory closure | Filtered speech, compressed speech, SIN | Phonemic training, auditory closure exercises |
| **Tolerance-Fading Memory** | Speech-in-noise, working memory | SIN, digit span, competing sentences | Speech-in-noise training, memory exercises |
| **Integration** | Interhemispheric transfer, binaural processing | DPT/FPT (labeling mode), DDT (left ear), MLD | Bilateral training, pattern sequencing |
| **Organization** | Sequencing, planning, output | DPT/FPT (sequencing errors), digit span backward | Following directions, sequence training |
| **Prosodic** | Rhythm, stress, intonation perception | DPT/FPT (humming OK but labeling poor), rhythm tests | Prosody training, music perception |

---

*This transforms HearBloom from a training tool into a clinical-grade CAPD assessment + rehabilitation platform that can compete with SCAN-3 + LACE + Angel Sound combined.*
