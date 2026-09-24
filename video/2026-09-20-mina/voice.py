#!/usr/bin/env python3
"""Generate the owner-selected Sarah narration; preserve generated takes."""
import json
from pathlib import Path
import urllib.request

root = Path(__file__).resolve().parent
config = json.loads((Path.home() / ".config/mina-trailer.json").read_text())
voice = "EXAVITQu4vr4xnSDxMaL"
lines = [
    "Those first weeks are a blur. Mina helps you remember the little things.",
    "Log a bottle in a few taps. Diapers, nursing, and sleep live in the same simple log.",
    "Look back at any day. Search for a feed, a note, or the detail you meant to remember.",
    "See feeding and sleep patterns at a glance, with a guide that grows with your baby.",
    "Share your log through iCloud, so both parents can pick up where the other left off. Mina. One less thing to keep in your head.",
]
for index, line in enumerate(lines):
    destination = root / "raw" / f"sarah-{index + 1}.mp3"
    if destination.exists():
        print("Using", destination.name)
        continue
    payload = json.dumps({"text": line, "model_id": "eleven_multilingual_v2",
        "voice_settings": {"stability": 0.55, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": True},
    }).encode()
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128",
        data=payload, headers={"xi-api-key": config["elevenlabs_api_key"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        audio = response.read()
    destination.write_bytes(audio)
    print("Created", destination.name, len(audio), "bytes", flush=True)
