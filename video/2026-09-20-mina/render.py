#!/usr/bin/env python3
"""Reproducible Sarah edits from actual simulator recordings, not stills.

Every cut is frame-accurate and re-encoded. Raw footage/takes are never changed.
The 30-second preview is full-screen UI; the trailer adds a quiet cream margin.
"""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
FINAL = ROOT / "final"
WORK = FINAL / "intermediates"
WORK.mkdir(parents=True, exist_ok=True)


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def normalize(source):
    destination = WORK / f"cfr-{source}"
    duration = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "format=duration", "-of", "default=nw=1:nk=1", str(RAW / source)]))
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", RAW / source,
        "-vf", f"fps=30,tpad=stop_mode=clone:stop_duration=2,trim=duration={duration},setpts=N/(30*TB)",
        "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "17", "-pix_fmt", "yuv420p", destination)
    return destination


SOURCES = {source: normalize(source) for source in ("tour.mp4", "today.mp4", "settings.mp4")}


def edit(name, width, height, scale_width, pace, scenes):
    assembled = []
    total = 0
    for beat, cuts in enumerate(scenes, 1):
        clips = []
        duration = sum(cut[2] for cut in cuts)
        for shot, (source, start, length) in enumerate(cuts, 1):
            clip = WORK / f"{name}-{beat}-{shot}.mp4"
            # Preserve the whole phone display, including tabs and controls.
            # Trim on the normalized source timeline, before resetting PTS.
            # Input-side seeking + PTS reset can retain a preceding keyframe.
            frame = (f"trim=start={start}:duration={length},setpts=PTS-STARTPTS,"
                     f"scale={scale_width}:-2,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0xFCF5EE,"
                     "setsar=1,fps=30")
            run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", SOURCES[source], "-t", length, "-vf", frame, "-an",
                "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p", clip)
            clips.append(clip)
        inputs = [item for clip in clips for item in ("-i", clip)]
        inputs += ["-i", RAW / f"sarah-{beat}.mp3"]
        labels = "".join(f"[{index}:v]" for index in range(len(clips)))
        filters = (f"{labels}concat=n={len(clips)}:v=1:a=0[v];"
                   f"[{len(clips)}:a]asetpts=PTS-STARTPTS,aresample=48000,atempo={pace},adelay=200:all=1,apad,atrim=duration={duration},"
                   "asetpts=PTS-STARTPTS[a]")
        scene = WORK / f"{name}-beat-{beat}.mp4"
        run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *inputs,
            "-filter_complex", filters, "-map", "[v]", "-map", "[a]", "-t", duration,
            "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", scene)
        assembled.append(scene)
        total += duration
        print(name, "beat", beat, "ready", flush=True)

    inputs = [item for scene in assembled for item in ("-i", scene)]
    labels = "".join(f"[{index}:v][{index}:a]" for index in range(len(assembled)))
    filters = (f"{labels}concat=n={len(assembled)}:v=1:a=1[v][mix];"
               f"[mix]loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json,apad,atrim=duration={total}[a]")
    output = FINAL / f"{name}.mp4"
    run("ffmpeg", "-hide_banner", "-loglevel", "info", "-y", *inputs,
        "-filter_complex", filters, "-map", "[v]", "-map", "[a]", "-t", total,
        "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2",
        "-movflags", "+faststart", output)
    probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams",
        "-show_format", "-of", "json", str(output)]))
    video = next(stream for stream in probe["streams"] if stream["codec_type"] == "video")
    assert (video["width"], video["height"]) == (width, height)
    assert abs(float(probe["format"]["duration"]) - total) < .05
    assert video["r_frame_rate"] == "30/1"
    assert int(video["nb_frames"]) == round(total * 30)
    print("Verified", output, "seconds", total, flush=True)


edit("mina-trailer-sarah", 1080, 1920, 824, .94, [
    [("today.mp4", 1, 6)],
    [("tour.mp4", 23.5, 6), ("tour.mp4", 34, 2)],
    [("tour.mp4", 59, 3), ("tour.mp4", 70, 4)],
    [("tour.mp4", 95, 3), ("tour.mp4", 102, 4)],
    [("settings.mp4", 1, 6), ("today.mp4", 1, 3)],
])

edit("mina-preview-6.9-sarah", 886, 1920, 882, 1, [
    [("today.mp4", 1, 5)],
    [("tour.mp4", 23.5, 6)],
    [("tour.mp4", 59, 3), ("tour.mp4", 70, 3)],
    [("tour.mp4", 95, 3), ("tour.mp4", 102, 3)],
    [("settings.mp4", 1, 4.5), ("today.mp4", 1, 2.5)],
])
