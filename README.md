# Mina

A newborn log for two phones. Feeds, diapers, sleep and more, logged by tap, by
widget, or by telling Siri; shared through iCloud so every caregiver sees the
same log; a feed alarm and a "who's on" handoff for the nights; a calendar and
searchable history to look back; an age-based guide for what to expect; and an
on-device Ask that answers questions about her log without anything leaving the
phone. Free, open source, no accounts, no servers. Mina runs on iPad too, in any orientation.

Website and privacy policy: https://alaarab.github.io/mina/ · App Store listing copy: [docs/store/listing.md](docs/store/listing.md)

## Build

Needs Xcode 16+, [XcodeGen](https://github.com/yonaslabs/XcodeGen) and a paid
Apple Developer team (CloudKit needs one). Put your team in `Local.xcconfig`:

```sh
cp Local.xcconfig.example Local.xcconfig   # then edit DEVELOPMENT_TEAM
xcodegen generate
open Mina.xcodeproj
```

Or from the terminal, onto a plugged-in iPhone:

```sh
xcodegen generate
xcodebuild -project Mina.xcodeproj -scheme Mina -destination 'generic/platform=iOS' -allowProvisioningUpdates build
```

`~/Projects/deploy-ios-apps.sh Mina` builds and installs it alongside the other apps.

Tests: `xcodebuild -project Mina.xcodeproj -scheme Mina -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`.

## First run on two phones

1. One parent opens the app, enters the name and birthday, and taps **Start**.
2. Settings → **Share with your partner** → send by Messages.
3. The other parent installs the app, then opens the link. The app opens with
   the shared log. Don't create a second baby on that phone.

Both phones need iCloud signed in. CloudKit pushes changes within seconds while
the app is open; in the background it catches up on next launch.

The CloudKit schema is created automatically the first time a record is saved
while running a development build. A TestFlight or App Store build would need
the schema deployed to Production in the CloudKit Console first.

## Widgets and partner alerts

- **Quick log** (medium Home Screen widget): last feed, today's counts, and one-tap
  buttons for the last bottle amount, pee, poop, and sleep/awake.
- **Last feed** (small, plus lock-screen circular/rectangular/inline): time since
  the last feed or how long she's been asleep. Redacted until the phone is unlocked.
- **Partner alerts**: "Mom fed Mina: 4 oz bottle at 2:15 PM" on the other phone,
  while the app is in the background. Several entries arriving together become
  one summary ("Kiley logged 3 things for Mina"), only entries from the last
  90 minutes alert, and never more than six alerts an hour. Only the phone
  that's on (see Who's on) gets them. Toggle in Settings.

Widgets read and write the store through the App Group; the app exports widget
entries to iCloud the next time it runs, so a widget-logged feed reaches the
partner a little later than one logged in the app or by Siri.

## What you can log

Bottle (typed or stepped, every millilitre), nursing (a live timer: pick the
side, switch sides, stop; or enter minutes after the fact), pumping (amount +
side), diaper (wet/dirty/both), sleep (running timer), notes, and under the
more menu: growth (weight, length, head), medicine (name + dose, defaults to
vitamin D), tummy time, bath, temperature (with a fever warning under
3 months). Weight, length and temperature have their own unit setting (pounds and ounces,
inches and °F by default; or kg, cm and °C), separate from bottle amounts.

Every entry can be opened from any list to fix the amount, the time (with
±5/15/30 minute nudges), the side, or delete it.

**Photos.** A note or a milestone can carry one picture, from the camera or the
photo library: a keepsake, or the rash and the diaper you want to show the
doctor. The thumbnail sits on the row on Today, the calendar and History; tap it
to see the picture full screen, pinch to zoom, and share the JPEG. Pictures are
downscaled to 1600 px and stripped of every bit of camera metadata (location,
time, device) before they are saved, then sync through iCloud with the rest of
the log. Widgets never show them.

## Feed alarm and partner pushes

Settings → Notifications → **Feed alarm** turns on a real alarm (iOS 26's Alarm
framework): it rings through silent mode and Focus and moves itself to last
feed + your chosen gap (or her predicted next feed) every time a feed is
logged. Stopping the alarm only means you're up; when you open the app it asks
"Did she eat?" with a one-tap Log, so nothing is recorded that didn't happen.
Snooze is 10 minutes. Older iOS keeps the plain notification reminder.

## Who's on

Tap **I'm on** on Today and only your phone rings the alarm and gets partner
alerts; **Hand off** gives it back. Settings → Who's on → Shifts sets a nightly
schedule (blocks can cross midnight) that both phones follow. With nothing set,
both phones get everything. Any number of caregivers can be on the share.

Keep Mina in the background rather than swiping it away: a feed your partner
logs reaches your phone through a silent push, and that is what moves your
alarm. A force-quit app gets no pushes until it is opened again.

## Quiet

The bell on Today pauses this phone: no feed alarm, no feed reminder, no
partner alerts, for an hour, three hours, until 7 AM, or until you turn it
back on. Settings → Quiet adds a nightly window (10 PM to 7 AM by default).
Each phone has its own quiet setting; the alarm re-arms itself when quiet ends.

## Today's goals and the Sunday digest

Today shows goals for her age: feeds, milk by bottle (about 2½ oz per pound a
day from her latest logged weight), wet and dirty diapers, sleep, and the gap
since the last feed (the wake-to-feed limit in the first two weeks). The rings
know what time of day it is, so three wet diapers at noon is on track and three
at 10 PM is short, and the day's one worry, if any, is spelled out the way the
guide does. Targets follow the guide's ranges unless you set your own under
Settings → Goals (a pediatrician's plan). The lock-screen widget shows the same
numbers, and "how is my baby doing today" includes them.

Sunday at 7 PM, one notification: the week's feeds, bottle ounces a day, wet
and dirty diapers, sleep a day, longest stretch, and how it moved since last
week. Built on the phone from the log. Toggle in Settings → Notifications.

## Looking back

- **Calendar**: a month of colored dots; tap a day for its totals and entries.
  The month title is a menu that jumps to any of the last 24 months.
- **History** (magnifier on Calendar): every entry ever, newest first, grouped
  by day, with search (notes, medicine names, who logged it, "wet", "left"…)
  and filters for feeds, diapers, sleep, health and notes. Fetches in batches,
  so years of entries scroll fine.

## Ask

The sparkles button on Today and Trends opens a chat that answers questions
about her log ("is she eating enough for her age?", "how did she sleep this
week?") using Apple's on-device Foundation Models on iOS 26 with Apple
Intelligence. It sees her age, the stage guidance, two weeks of totals and the
latest entries; nothing leaves the phone. Follow-up questions keep context.
Tap the mic to dictate (on-device speech recognition only) and the speaker to
have answers read aloud; with the speaker on, a dictated question sends itself,
so it works hands-free.

## More than one baby

Settings → Baby → **Add another baby** (a second child, or twins). Each baby
has its own log and its own sharing; a picker appears when there's more than
one and everything on screen belongs to the selected baby. If you accept a
share after starting a log with the same name on your own phone, Mina offers to
merge your entries into the shared log so nothing is typed twice.

## Backup

Settings → Backup exports every entry as a JSON file (AirDrop it, keep it in
Files) and imports one back, adding only entries that aren't already there, so
importing twice or importing a partner's file never duplicates. Do this before
switching between a development build and a TestFlight build: they use
different iCloud environments and don't see each other's data. Photos go in the
file too, as base64 JPEGs, so a log with pictures makes a file of megabytes
rather than kilobytes; the file's `photoCount` and `photoBytes` say how much.

## Predictions, trends, milestones

- **Next feed**: median gap of her last feeds (age norm until there are enough), shown on
  Today and, if you turn it on in Settings, a reminder at that time.
- **Nap window**: last wake plus the wake window for her age (50 min at 0–4 weeks, up to
  105 min after 3 months).
- **Trends** tab: 14-day charts for bottle volume and feed count, sleep with the longest
  stretch, and wet/dirty diapers; 7-day averages; growth entries; **Share report** makes a
  one-page PDF for the pediatrician.
- **History** (Calendar → magnifier): every entry, searchable, filtered by feeds, diapers, sleep, health or notes, grouped by day; the month title jumps to any of the last 24 months.
- **Nursing timer**: tap Nurse, pick the side (it suggests the one she didn't finish on), switch sides or stop from Today; the split is saved on the entry.
- **Milestones**: in the Guide, tap a milestone when she does it; it's logged with the date
  and shows up on the timeline and in the report.

## Nanit (off in App Store builds)

Set `FeatureFlags.nanit = true` in `Mina/App/Preferences.swift` to show it. Settings → Connect Nanit: email and password, the code Nanit emails, then pick the
camera. Only the sign-in token is kept (Keychain). Sleep and wake events from the
camera's message feed become sleep entries logged as "Nanit", synced when the app
comes to the foreground and by background app refresh roughly every 30 minutes.

This uses Nanit's private API (the same one the Home Assistant community bridge
uses): `POST /login` with `nanit-api-version: 1`, `POST /tokens/refresh`,
`GET /babies`, `GET /babies/{uid}/messages`. Nanit's sleep/wake message types
aren't documented, so `NanitEventMapper` matches type names containing
sleep/wake, and Settings lists every type the account has actually sent. If
sleep entries don't appear after a nap, read that list and tighten the mapping
in `Mina/Nanit/NanitSync.swift`. It can stop working whenever Nanit changes their
backend.

## Siri

The app's name is the trigger, and "my baby", "the baby" and "our baby" work as
alternates, so it reads naturally whatever the child is called. Replies use the
baby's real name. With more than one baby, phrases log to the selected baby; say
"log a bottle for Olivia" to name one, or Siri asks "Which baby?"

Phrases:

- "Hey Siri, Mina ate 4 ounces" (also 120 milliliters, and half-ounce steps 1–10)
- "Mina nursed on the left"
- "Mina just peed" / "Mina just pooped" / "Mina had a wet and dirty diaper"
- "I pumped 4 ounces for Mina"
- "Mina is asleep" / "Mina woke up"
- "Mina weighs 7 pounds 4 ounces" (any ounce from 5 lb to 15 lb 15 oz)
- "When did Mina last eat?" / "When did Mina last poop?"

Phrases live in `Mina/Intents/Intents.swift`. Spoken amounts are an enum so
Siri can match them without launching the app.

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for the threat model and the decisions behind it: no server, iCloud private database with explicit sharing, data protection on the store, Nanit token in a non-syncing Keychain item, privacy manifests, redacted lock-screen widgets.

## Releasing

See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md). `scripts/release.py` archives and uploads to TestFlight with an App Store Connect API key.

## Layout

- `Mina/Data` — Core Data model (built in code), the CloudKit-mirrored stack,
  `Logbook` (every write), `DaySummary`, sharing and sync monitors.
- `Mina/Intents` — App Intents and the App Shortcuts phrases.
- `Mina/Features` — Today, Calendar, Settings, Onboarding.
- `Mina/Guide` — stage-by-stage expectations (`Guidance.swift`) and the Guide tab.
- `scripts/make-appicon.py` — regenerates the icon.
