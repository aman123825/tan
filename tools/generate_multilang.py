"""Generate non-English demonstration speech assets (Hindi/Tamil/Telugu/Kannada).

Reads a word-pool config (``tools/multilang_words.json`` by default: 10 common
words per language) and uses edge-tts (network) to synthesize each word in that
language's voice, decoding the MP3 to a 16-bit PCM WAV via miniaudio so the
Flutter client can decode + mix it. Output goes to
``apps/flutter_app/assets/stimuli/<lang>/`` (e.g. ``.../hi/word_paani.wav``),
matching the LanguageConfig ``speechAssetPrefix`` framework already in the app.

These are DEMONSTRATION voices (``demo_only``), NOT validated clinical stimuli.

    Run this script to generate non-English speech assets:
        pip install edge-tts miniaudio
        python tools/generate_multilang.py                 # all languages
        python tools/generate_multilang.py --langs hi ta   # a subset

After generating, add the new folders to ``apps/flutter_app/pubspec.yaml`` under
``flutter: assets:`` (e.g. ``- assets/stimuli/hi/``) so they are bundled.
"""
from __future__ import annotations

import argparse
import asyncio
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path(__file__).resolve().parent / "multilang_words.json"
OUT_ROOT = ROOT / "apps/flutter_app/assets/stimuli"


def load_config(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    return data["languages"]


async def generate_language(lang_code: str, spec: dict) -> int:
    """Synthesize every word for one language. Returns the count written."""
    import edge_tts  # noqa: WPS433 (optional dependency, import on use)
    import miniaudio  # noqa: WPS433

    voice = spec["voice"]
    words = spec["words"]
    out_dir = OUT_ROOT / lang_code
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = []
    for entry in words:
        roman = entry["roman"]
        native = entry["native"]
        mp3 = out_dir / f"{roman}.mp3"
        wav = out_dir / f"word_{roman}.wav"
        # Synthesize the native-script word in the language's voice.
        await edge_tts.Communicate(native, voice).save(str(mp3))
        decoded = miniaudio.mp3_read_file_s16(str(mp3))
        miniaudio.wav_write_file(str(wav), decoded)
        mp3.unlink()
        manifest.append(
            {
                "id": f"word_{roman}",
                "kind": "generated_speech",
                "native": native,
                "roman": roman,
                "english": entry.get("english", ""),
                "voice": voice,
                "file": wav.name,
                "sample_rate": decoded.sample_rate,
                "validation_status": "demo_only",
            }
        )
    (out_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"  [{lang_code}] generated {len(manifest)} demo words in {out_dir}")
    return len(manifest)


async def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config", type=Path, default=CONFIG, help="word-pool JSON config"
    )
    parser.add_argument(
        "--langs",
        nargs="*",
        default=None,
        help="subset of language codes to build (default: all in the config)",
    )
    args = parser.parse_args()

    languages = load_config(args.config)
    selected = args.langs or list(languages.keys())

    total = 0
    for code in selected:
        if code not in languages:
            print(f"  skipping unknown language '{code}'")
            continue
        total += await generate_language(code, languages[code])
    print(f"done: {total} demonstration words across {len(selected)} language(s)")
    print("Reminder: demo_only voices — not validated clinical stimuli.")


if __name__ == "__main__":
    asyncio.run(main())
