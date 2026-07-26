# Safety and Clinical Boundary

This source is for research development. It does not diagnose, treat or measure absolute hearing thresholds.

## Required invariants
- `auto_volume` is always false.
- Wrong answers never increase master volume.
- Home audio never reports dB HL.
- Wired, Bluetooth and speaker sessions are not pooled for temporal thresholds.
- Temporal/dichotic research tasks recommend wired headphones.
- Separate-ear presentation requires explicit clinician approval in the profile.
- Training may stop at any time; fatigue is not failure.
- High fatigue triggers easier/shorter recommendations.
- Assessment algorithms and token pools are immutable within a released version.
- AI outputs include a human-readable reason and confidence.
- Clinicians can override AI recommendations.

## ANSD-oriented precautions
Speech understanding may not track pure-tone sensitivity and may not improve with increased level. Adapt SNR, rate, temporal complexity and response choices rather than master volume. Do not infer neural status from software performance.

## Data
Minimize identifiers, encrypt local records, require consent for research export, and exclude identifiable clinical documents from model training.
