"""Generate demonstration word assets — now in ALL FOUR study voices (K1/K2).

Uses edge-tts (network required) to synthesize every closed-set word in the
four voices the speaker-ID task ships (2 female + 2 male), then decodes each
MP3 to 16-bit PCM WAV via miniaudio so the Flutter client can decode + mix.

Outputs:
  apps/flutter_app/assets/stimuli/speech/            (v1 voice — unchanged
      filenames, so existing tasks keep working)
  apps/flutter_app/assets/stimuli/speech_multi/<voice_id>/word_<w>.wav
      + manifest.json                                 (all four voices)

These are DEMONSTRATION voices (`demo_only`), not validated clinical
stimuli. Recorded, validated speech remains the K1 content gap.

    pip install edge-tts miniaudio
    python tools/generate_speech_words.py
"""
from __future__ import annotations

import asyncio
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_LEGACY = ROOT / "apps/flutter_app/assets/stimuli/speech"
OUT_MULTI = ROOT / "apps/flutter_app/assets/stimuli/speech_multi"

# The four study voices — ids match assets/stimuli/speaker/manifest.json and
# the proxy-variant labels in lib/core/audio/voice_variants.dart.
VOICES = {
    "v1": "en-IN-NeerjaNeural",   # female (the legacy single voice)
    "v2": "en-IN-PrabhatNeural",  # male
    "v3": "en-US-JennyNeural",    # female
    "v4": "en-GB-RyanNeural",     # male
}

# The full closed-set word bank (lib/core/content_pools.dart `_words`).
WORDS = ["bell", "ball", "bat", "bag", "pen", "pin", "cup", "cap",
         "dog", "cat", "book", "key", "ship", "chip", "boat", "coat"]


async def synth(word: str, voice: str, wav_path: Path) -> int:
    import edge_tts  # noqa: WPS433 (optional network dependency)
    import miniaudio  # noqa: WPS433

    mp3 = wav_path.with_suffix(".mp3")
    await edge_tts.Communicate(word, voice).save(str(mp3))
    decoded = miniaudio.mp3_read_file_s16(str(mp3))
    miniaudio.wav_write_file(str(wav_path), decoded)
    mp3.unlink()
    return decoded.sample_rate


async def main() -> None:
    manifest = []
    for vid, voice in VOICES.items():
        out_dir = OUT_MULTI / vid
        out_dir.mkdir(parents=True, exist_ok=True)
        for word in WORDS:
            wav = out_dir / f"word_{word}.wav"
            rate = await synth(word, voice, wav)
            manifest.append({
                "id": f"{vid}_word_{word}",
                "kind": "generated_speech",
                "text": word,
                "voice": voice,
                "voice_id": vid,
                "file": f"{vid}/{wav.name}",
                "sample_rate": rate,
                "validation_status": "demo_only",
            })
            # Keep the legacy single-voice folder in sync for v1.
            if vid == "v1":
                OUT_LEGACY.mkdir(parents=True, exist_ok=True)
                (OUT_LEGACY / wav.name).write_bytes(wav.read_bytes())
    (OUT_MULTI / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"generated {len(manifest)} demo word files "
          f"({len(VOICES)} voices x {len(WORDS)} words) in {OUT_MULTI}")
    print("Remember: add 'assets/stimuli/speech_multi/' (and each voice "
          "subfolder) to pubspec.yaml before shipping.")


if __name__ == "__main__":
    asyncio.run(main())
