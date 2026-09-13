# Mina

A newborn log for two phones. Feeds, diapers, sleep and notes, logged by tap or
by telling Siri, shared through iCloud so both parents see the same thing, with
a calendar to look back and an age-based guide for what to expect.

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
  the last feed or how long she's been asleep.
- **Partner alerts**: when the other phone's entry syncs in, this phone shows
  "Mom fed Mina: 4 oz bottle at 2:15 PM". They arrive while the app is in the
  background; a force-quit app catches up on next launch. Toggle in Settings.

Widgets read and write the store through the App Group; the app exports widget
entries to iCloud the next time it runs, so a widget-logged feed reaches the
partner a little later than one logged in the app or by Siri.

## What you can log

Bottle, nursing (side + minutes), diaper (wet/dirty/both), sleep (running
timer), notes, and under **More**: pumping, growth (weight, length, head),
medicine (name + dose, defaults to vitamin D), tummy time, bath, temperature
(with a fever warning under 3 months). Growth and temperature follow the bottle
unit: ounces means lb/oz, inches and °F; milliliters means kg, cm and °C.

## Predictions, trends, milestones

- **Next feed**: median gap of her last feeds (age norm until there are enough), shown on
  Today and, if you turn it on in Settings, a reminder at that time.
- **Nap window**: last wake plus the wake window for her age (50 min at 0–4 weeks, up to
  105 min after 3 months).
- **Trends** tab: 14-day charts for bottle volume and feed count, sleep with the longest
  stretch, and wet/dirty diapers; 7-day averages; growth entries; **Share report** makes a
  one-page PDF for the pediatrician.
- **Milestones**: in the Guide, tap a milestone when she does it; it's logged with the date
  and shows up on the timeline and in the report.

## Nanit

Settings → Connect Nanit: email and password, the code Nanit emails, then pick the
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

The app's name is the trigger, so phrases are natural:

- "Hey Siri, Mina ate 4 ounces" (also 120 milliliters, and half-ounce steps 1–10)
- "Mina nursed on the left"
- "Mina just peed" / "Mina just pooped" / "Mina peed and pooped" (or "Mina had a wet diaper")
- "Mina is asleep" / "Mina woke up"
- "Mina weighs 7 pounds 4 ounces" (any ounce from 5 lb to 15 lb 15 oz)
- "When did Mina last eat?" / "When did Mina last poop?"

Phrases live in `Mina/Intents/Intents.swift`. Spoken amounts are an enum so
Siri can match them without launching the app.

## Releasing

See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md). `scripts/release.py` archives and uploads to TestFlight with an App Store Connect API key.

## Layout

- `Mina/Data` — Core Data model (built in code), the CloudKit-mirrored stack,
  `Logbook` (every write), `DaySummary`, sharing and sync monitors.
- `Mina/Intents` — App Intents and the App Shortcuts phrases.
- `Mina/Features` — Today, Calendar, Settings, Onboarding.
- `Mina/Guide` — stage-by-stage expectations (`Guidance.swift`) and the Guide tab.
- `scripts/make-appicon.py` — regenerates the icon.
