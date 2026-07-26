"""Research-only normative interpretation (Python mirror of norms.dart).

NOT a diagnosis. Reference bands come from published literature on validated
clinical procedures; HearBloom uses demonstration stimuli on uncalibrated audio,
so an interpretation is illustrative context only. Bands are cited inline and
kept identical to `apps/flutter_app/lib/core/norms.dart`.
"""
from __future__ import annotations
from dataclasses import dataclass

BETTER = "better_than_typical"
WITHIN = "within_typical"
SLIGHTLY_BELOW = "slightly_below_typical"
BELOW = "below_typical"
INSUFFICIENT = "insufficient"

FAVORABLE = {BETTER, WITHIN}


@dataclass(frozen=True)
class NormResult:
    band: str
    detail: str
    citation: str

    @property
    def is_insufficient(self) -> bool:
        return self.band == INSUFFICIENT

    @property
    def is_favorable(self) -> bool:
        return self.band in FAVORABLE


def _insufficient() -> NormResult:
    return NormResult(
        INSUFFICIENT,
        "Complete more trials (enough reversals) to estimate a threshold "
        "before it can be compared with reference data.",
        "",
    )


def gap_ms(ms: float | None) -> NormResult:
    """Temporal gap detection (ms); lower is finer. GIN normal ≤ 6 ms."""
    if ms is None:
        return _insufficient()
    cite = "GIN norms: Musiek et al., 2005; Int. J. Audiol. 2008"
    if ms <= 4:
        return NormResult(BETTER, "≤ 4 ms is at the fine end of adult GIN data.", cite)
    if ms <= 6:
        return NormResult(WITHIN, "≤ 6 ms is the normal adult GIN cut-off.", cite)
    if ms <= 10:
        return NormResult(SLIGHTLY_BELOW, "6–10 ms is just outside typical.", cite)
    return NormResult(BELOW, "> 10 ms is well outside typical adult resolution.", cite)


def frequency_semitones(st: float | None) -> NormResult:
    """Frequency/pitch discrimination (semitones); lower is finer."""
    if st is None:
        return _insufficient()
    cite = "Frequency DL: Wier, Jesteadt & Green, 1977 (task-relative)"
    if st <= 0.5:
        return NormResult(BETTER, "< ~0.5 semitone is a fine pitch difference.", cite)
    if st <= 1:
        return NormResult(WITHIN, "≈ 1 semitone is a solid result for this task.", cite)
    if st <= 2:
        return NormResult(SLIGHTLY_BELOW, "1–2 semitones is coarser.", cite)
    return NormResult(BELOW, "> 2 semitones is coarse pitch discrimination.", cite)


def am_depth_db(db: float | None) -> NormResult:
    """AM detection (dB re 20log10 m); more negative is better."""
    if db is None:
        return _insufficient()
    cite = "TMTF: Viemeister, 1979; Bacon & Viemeister, 1985 (task-relative)"
    if db <= -20:
        return NormResult(BETTER, "≤ −20 dB approaches published TMTF sensitivity.", cite)
    if db <= -12:
        return NormResult(WITHIN, "−12 to −20 dB is a good result for this task.", cite)
    if db <= -6:
        return NormResult(SLIGHTLY_BELOW, "−6 to −12 dB is shallower than best.", cite)
    return NormResult(BELOW, "> −6 dB (deep) modulation needed: reduced sensitivity.", cite)


def speech_snr_db(db: float | None) -> NormResult:
    """Speech-in-noise adaptive SNR (dB); lower is better."""
    if db is None:
        return _insufficient()
    cite = "cf. QuickSIN SNR-loss, Killion et al., 2004 (task-relative)"
    if db <= 0:
        return NormResult(BETTER, "≤ 0 dB SNR is strong speech-in-noise performance.", cite)
    if db <= 4:
        return NormResult(WITHIN, "0–4 dB SNR at threshold is typical for this task.", cite)
    if db <= 8:
        return NormResult(SLIGHTLY_BELOW, "4–8 dB SNR is more favourable than typical.", cite)
    return NormResult(BELOW, "> 8 dB SNR indicates difficulty with speech in noise.", cite)


def dichotic_percent(percent: float | None) -> NormResult:
    """Dichotic digits per ear (percent); higher is better. Normal ≈ ≥ 90%."""
    if percent is None:
        return _insufficient()
    cite = "DDT norms: Musiek, 1983 (adults ≈ ≥ 90%/ear)"
    if percent >= 95:
        return NormResult(BETTER, "≥ 95%/ear is top of the adult DDT range.", cite)
    if percent >= 90:
        return NormResult(WITHIN, "≥ 90%/ear is the normal adult cut-off.", cite)
    if percent >= 80:
        return NormResult(SLIGHTLY_BELOW, "80–90%/ear is just below cut-off.", cite)
    return NormResult(BELOW, "< 80%/ear is below the typical adult range.", cite)



def chance_corrected(observed: float, alternatives: int) -> float:
    """Guessing-corrected proportion for an nAFC task (Abbott's formula):
    removes the 1/n chance floor so a score reflects performance above
    guessing. Clamped to [0, 1]. Mirror of Norms.chanceCorrected in Dart."""
    if alternatives < 2:
        return max(0.0, min(1.0, observed))
    chance = 1 / alternatives
    c = (observed - chance) / (1 - chance)
    return 0.0 if c < 0 else (1.0 if c > 1 else c)
