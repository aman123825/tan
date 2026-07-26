"""Generate all Indian-English demonstration speech corpora as WAV assets.

Uses edge-tts (network) + miniaudio (MP3 -> 16-bit PCM WAV) to produce the
closed-set / open-set / matrix / colors corpora consumed by the Flutter client.
Every asset is DEMONSTRATION material (`demo_only`), not validated clinical
stimuli.

    pip install edge-tts miniaudio
    python tools/generate_demo_assets.py

Output: apps/flutter_app/assets/stimuli/<corpus>/<file>.wav plus a per-corpus
manifest.json recording id/text/voice/validation_status.
"""
from __future__ import annotations

import asyncio
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "apps/flutter_app/assets/stimuli"
VOICE = "en-IN-NeerjaNeural"

# corpus -> list of (file_stem, spoken_text)
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven",
          "eight", "nine"]
LETTERS = [chr(c) for c in range(ord("a"), ord("z") + 1)]
PHONEMES = ["ba", "pa", "da", "ta", "ga", "ka", "ma", "na", "sa", "sha",
            "fa", "va"]
WORDS = ["bell", "ball", "bat", "bag", "pen", "pin", "cup", "cap", "dog",
         "cat", "book", "key", "ship", "chip", "boat", "coat"]
SENTENCES = [
    ("s1", "the boy runs home"),
    ("s2", "she reads a book"),
    ("s3", "the dog is black"),
    ("s4", "we eat rice today"),
    ("s5", "open the red door"),
    ("s6", "birds fly very high"),
    ("s7", "he drinks cold water"),
    ("s8", "the sun is bright"),
    ("s9", "put the cup down"),
    ("s10", "they walk to school"),
]
COLORS = ["red", "green", "blue", "yellow", "orange", "purple", "black",
          "white"]
FOOD = ["apple", "banana", "grapes", "pizza", "bread", "egg"]
ANIMALS = ["dog", "cat", "elephant", "fish", "bird", "cow"]
# Speaker/talker identification: the same word spoken by four distinct voices.
SPEAKER_VOICES = [
    "en-IN-NeerjaNeural",
    "en-IN-PrabhatNeural",
    "en-US-JennyNeural",
    "en-GB-RyanNeural",
]
SPEAKER_WORD = "hello"
# Classic-style matrix: 5 slots x 10 alternatives.
MATRIX = {
    "name": ["peter", "thomas", "lucy", "alan", "nina", "rachel", "david",
             "sara", "john", "emma"],
    "verb": ["has", "wants", "gives", "buys", "sees", "keeps", "sells",
             "holds", "brings", "takes"],
    "number": ["two", "three", "four", "five", "six", "seven", "eight",
               "nine", "ten", "twelve"],
    "adjective": ["red", "green", "blue", "big", "small", "old", "new",
                  "dark", "pink", "white"],
    "object": ["toys", "pens", "books", "cups", "rings", "chairs", "desks",
               "shoes", "bags", "cards"],
}


async def _render(text: str, out_wav: Path, voice: str = VOICE) -> int:
    import edge_tts
    import miniaudio

    mp3 = out_wav.with_suffix(".mp3")
    await edge_tts.Communicate(text, voice).save(str(mp3))
    decoded = miniaudio.mp3_read_file_s16(str(mp3))
    miniaudio.wav_write_file(str(out_wav), decoded)
    mp3.unlink()
    return decoded.sample_rate


async def _corpus(name: str, items: list[tuple[str, str]]) -> None:
    out = BASE / name
    out.mkdir(parents=True, exist_ok=True)
    manifest = []
    for stem, text in items:
        wav = out / f"{stem}.wav"
        rate = await _render(text, wav)
        manifest.append({
            "id": stem,
            "text": text,
            "voice": VOICE,
            "file": wav.name,
            "sample_rate": rate,
            "validation_status": "demo_only",
        })
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"  {name}: {len(manifest)} files")


async def _speaker_corpus() -> None:
    out = BASE / "speaker"
    out.mkdir(parents=True, exist_ok=True)
    manifest = []
    for i, voice in enumerate(SPEAKER_VOICES):
        wav = out / f"speaker_v{i + 1}.wav"
        rate = await _render(SPEAKER_WORD, wav, voice)
        manifest.append({
            "id": f"v{i + 1}",
            "text": SPEAKER_WORD,
            "voice": voice,
            "file": wav.name,
            "sample_rate": rate,
            "validation_status": "demo_only",
        })
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))
    print(f"  speaker: {len(manifest)} files")


async def main() -> None:
    import sys

    only = set(sys.argv[1:])

    def want(name: str) -> bool:
        return not only or name in only

    print("generating demo corpora (en-IN, demo_only)...")
    if want("digits"):
        await _corpus("digits", [(f"digit_{i}", w) for i, w in enumerate(DIGITS)])
    if want("letters"):
        await _corpus("letters", [(f"letter_{c}", c) for c in LETTERS])
    if want("phonemes"):
        await _corpus("phonemes", [(f"syl_{s}", s) for s in PHONEMES])
    if want("words"):
        await _corpus("words", [(f"word_{w}", w) for w in WORDS])
    if want("sentences"):
        await _corpus("sentences", [(sid, txt) for sid, txt in SENTENCES])
    if want("colors"):
        await _corpus("colors", [(f"color_{c}", c) for c in COLORS])
    if want("food"):
        await _corpus("food", [(f"food_{w}", w) for w in FOOD])
    if want("animals"):
        await _corpus("animals", [(f"animal_{w}", w) for w in ANIMALS])
    if want("speaker"):
        await _speaker_corpus()
    if want("matrix"):
        matrix_items = [
            (f"matrix_{slot}_{w}", w)
            for slot, words in MATRIX.items()
            for w in words
        ]
        await _corpus("matrix", matrix_items)
    print("done.")


if __name__ == "__main__":
    asyncio.run(main())
