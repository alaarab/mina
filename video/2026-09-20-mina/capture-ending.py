#!/usr/bin/env python3
import signal
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parent
device = "0B80A53E-252A-4917-9BC3-611AB2A8C5DA"
for tab in ("settings", "today"):
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", device,
                    "com.alaarab.mina", "-seed-demo", "-tab", tab], check=True)
    time.sleep(2)
    recording = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264", str(root / "raw" / f"{tab}.mp4")])
    time.sleep(9)
    recording.send_signal(signal.SIGINT)
    if recording.wait(timeout=30) != 0:
        raise SystemExit("Recording failed")
    print("Captured", tab, flush=True)
