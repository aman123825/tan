"""Generate a speech-derived multi-talker babble masker (K3).

Overlaps many randomly-offset, randomly-gained copies of the SHIPPED word
recordings (all four proxy-voice transpositions of them) into a loopable
babble buffer — real speech energy rather than modulated noise, with no
network or extra dependencies (stdlib wave/array only).

Deterministic (fixed seed). Output:
    apps/flutter_app/assets/stimuli/noise_babble_speech.wav  (mono, 24 kHz)

    python tools/generate_babble.py
"""
from __future__ import annotations

import array
import random
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / 'apps/flutter_app/assets/stimuli/words',
           ROOT / 'apps/flutter_app/assets/stimuli/speech']
OUT = ROOT / 'apps/flutter_app/assets/stimuli/noise_babble_speech.wav'

SECONDS = 6.0
TALKER_STREAMS = 8          # simultaneous voices
SEED = 20260727
# The four proxy-voice transposition ratios (matches voice_variants.dart).
VOICE_RATIOS = [1.0, 0.84, 1.12, 0.92]


def read_wav(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), 'rb') as w:
        rate = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)
        samples = array.array('h')
        samples.frombytes(raw)
        step = w.getnchannels()
        return [samples[i] / 32768.0 for i in range(0, len(samples), step)], rate


def resample(samples: list[float], ratio: float) -> list[float]:
    """Naive linear-interpolation transposition (> 1 = higher/shorter)."""
    if ratio == 1.0:
        return samples
    out_len = int(len(samples) / ratio)
    out = []
    for i in range(out_len):
        src = i * ratio
        i0 = int(src)
        frac = src - i0
        a = samples[i0] if i0 < len(samples) else 0.0
        b = samples[i0 + 1] if i0 + 1 < len(samples) else 0.0
        out.append(a + (b - a) * frac)
    return out


def main() -> None:
    rng = random.Random(SEED)
    words: list[list[float]] = []
    rate = 24000
    for src in SOURCES:
        for p in sorted(src.glob('word_*.wav')):
            samples, rate = read_wav(p)
            words.append(samples)
    if not words:
        raise SystemExit('no word_*.wav sources found')

    n = int(SECONDS * rate)
    mix = [0.0] * n
    # Each stream drops words end-to-end (random voice, gain, small pauses),
    # wrapping around so the buffer loops cleanly.
    for _stream in range(TALKER_STREAMS):
        pos = rng.randrange(n)
        # Enough words to cover the buffer at least twice.
        budget = n * 2
        while budget > 0:
            word = resample(rng.choice(words), rng.choice(VOICE_RATIOS))
            gain = 0.4 + rng.random() * 0.6
            for i, v in enumerate(word):
                mix[(pos + i) % n] += v * gain
            pause = int(rate * (0.05 + rng.random() * 0.2))
            pos = (pos + len(word) + pause) % n
            budget -= len(word) + pause

    peak = max(abs(v) for v in mix) or 1.0
    k = 0.6 / peak  # comfortable headroom; mixing pages re-scale by SNR
    frames = array.array(
        'h', (int(max(-1.0, min(1.0, v * k)) * 32767) for v in mix))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(frames.tobytes())
    print(f'wrote {OUT} ({SECONDS:.0f}s @ {rate} Hz, '
          f'{TALKER_STREAMS} streams, {len(words)} source words)')


if __name__ == '__main__':
    main()
