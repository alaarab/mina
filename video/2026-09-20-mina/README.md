# Mina — Sarah trailer

Final exports (local, ignored by git):

- `final/mina-trailer-sarah.mp4`: 37 seconds, 1080×1920, 30 fps.
- `final/mina-preview-6.9-sarah.mp4`: exactly 30 seconds / 900 frames, 886×1920.

Both use H.264/yuv420p and stereo AAC/48 kHz. Measured audio is about −16 LUFS
with peaks below −2.9 dBTP. Frame contact sheets were reviewed, including both
endpoints, and full-file decoding found no black gaps. The App Store preview
processed to COMPLETE and is first in the existing en-US `IPHONE_67` preview set;
the earlier preview remains available as the second asset.

The owner selected Sarah and delegated the remaining edit choices. Shot B is
the actual bottle sheet and saved result, not generated footage. The sequence
is Today → bottle/diaper → calendar/search → trends/guide → sharing → Today.
Sharing is shown in its real unconfigured simulator state, not a simulated
successful two-phone sync. The physical sync checks remain outstanding.

## Sources and reproduction

`raw/tour.mp4` is a genuine simulator recording from the passing `TrailerTour`
UI test (one test, zero failures). `capture-ending.py` records fresh Settings and
Today holds. It targets the dedicated iPhone 17 Pro simulator used for this job;
update its device ID if recreating the simulator. All raw footage is preserved.

`voice.py` generated five ElevenLabs Sarah takes from the checked-in script,
using the existing private `~/.config/mina-trailer.json` credentials. It reuses
existing takes to avoid duplicate generation. No credentials are in this folder.

`python3 render.py` normalizes the variable-rate simulator footage before making
frame-accurate cuts, mixes Sarah's takes, normalizes audio, and checks export
duration, dimensions, frame rate and frame count. It does not publish anything.

The recovered `raw/existing-app-store-preview.mp4` is only a low-resolution Apple
delivery proxy and is not used in either new export.
