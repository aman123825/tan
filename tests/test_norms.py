"""Boundary tests for the normative interpretation (mirrors norms_harness.dart)."""
from packages.protocol_engine import norms as N


def test_insufficient_when_none():
    assert N.gap_ms(None).is_insufficient
    assert N.frequency_semitones(None).is_insufficient
    assert N.am_depth_db(None).is_insufficient
    assert N.speech_snr_db(None).is_insufficient
    assert N.dichotic_percent(None).is_insufficient


def test_gap_bands():
    assert N.gap_ms(3.5).band == N.BETTER
    assert N.gap_ms(5).band == N.WITHIN
    assert N.gap_ms(6).band == N.WITHIN
    assert N.gap_ms(8).band == N.SLIGHTLY_BELOW
    assert N.gap_ms(20).band == N.BELOW
    assert "GIN" in N.gap_ms(5).citation


def test_frequency_bands():
    assert N.frequency_semitones(0.3).band == N.BETTER
    assert N.frequency_semitones(1).band == N.WITHIN
    assert N.frequency_semitones(1.5).band == N.SLIGHTLY_BELOW
    assert N.frequency_semitones(4).band == N.BELOW


def test_am_bands():
    assert N.am_depth_db(-22).band == N.BETTER
    assert N.am_depth_db(-15).band == N.WITHIN
    assert N.am_depth_db(-8).band == N.SLIGHTLY_BELOW
    assert N.am_depth_db(-3).band == N.BELOW


def test_speech_snr_bands():
    assert N.speech_snr_db(-2).band == N.BETTER
    assert N.speech_snr_db(3).band == N.WITHIN
    assert N.speech_snr_db(6).band == N.SLIGHTLY_BELOW
    assert N.speech_snr_db(12).band == N.BELOW


def test_dichotic_bands():
    assert N.dichotic_percent(97).band == N.BETTER
    assert N.dichotic_percent(91).band == N.WITHIN
    assert N.dichotic_percent(85).band == N.SLIGHTLY_BELOW
    assert N.dichotic_percent(70).band == N.BELOW


def test_favorable_flag():
    assert N.gap_ms(5).is_favorable
    assert not N.gap_ms(20).is_favorable



def test_chance_corrected():
    assert abs(N.chance_corrected(0.6, 4) - 0.4666666666666667) < 1e-9
    assert N.chance_corrected(0.25, 4) == 0  # at chance
    assert N.chance_corrected(1.0, 3) == 1  # perfect
    assert N.chance_corrected(0.1, 4) == 0  # below chance clamps to 0
    assert N.chance_corrected(0.5, 1) == 0.5  # degenerate: passthrough
