#!/usr/bin/env python3
"""Safe file-based wrapper for the edge-tts Python package."""

import argparse
import asyncio
import json
import re
from pathlib import Path

import edge_tts


ALLOWED_VOICES = {
    "hi-IN-SwaraNeural",
    "en-US-AriaNeural",
}
RATE_PATTERN = re.compile(r"^[+-]\d{1,3}%$")


async def synthesize(input_path: Path, output_path: Path) -> None:
    payload = json.loads(input_path.read_text(encoding="utf-8"))
    text = payload.get("text")
    voice = payload.get("voice")
    rate = payload.get("rate", "+0%")

    if not isinstance(text, str) or not text.strip():
        raise ValueError("text must be a non-empty string")
    if voice not in ALLOWED_VOICES:
        raise ValueError("voice is not allowed")
    if not isinstance(rate, str) or not RATE_PATTERN.fullmatch(rate):
        raise ValueError("rate must look like +10% or -10%")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    communicator = edge_tts.Communicate(text.strip(), voice, rate=rate)
    await communicator.save(str(output_path))

    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError("edge-tts did not create a non-empty output file")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    asyncio.run(synthesize(arguments.input, arguments.output))


if __name__ == "__main__":
    main()
