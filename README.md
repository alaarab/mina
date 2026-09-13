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

Bottle (typed or stepped, every millilitre), nursing (a live timer: pick the
side, switch sides, stop; or enter minutes after the fact), pumping (amount +
side), diaper (wet/dirty/both), sleep (running timer), notes, and under the
more menu: growth (weight, length, head), medicine (name + dose, defaults to
vitamin D), tummy time, bath, temperature (with a fever warning under
3 months). Growth and temperature follow the bottle unit: ounces means lb/oz,
inches and °F; milliliters means kg, cm and °C.

Every entry can be opened from any list to fix the amount, the time (with
±5/15/30 minute nudges), the side, or delete it.

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

Partner alerts on the log owner's phone use a CloudKit subscription, so they
arrive even when Mina has been force-quit. The partner's phone gets them
through the silent push while the app is in the background.

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

Settings → Baby → Add another baby. Each baby has its own log and its own
sharing; a picker appears when there's more than one. If you accept a share
after starting a log with the same name on your own phone, Mina offers to
merge your entries into the shared log.

## Backup

Settings → Backup exports every entry as a JSON file (share it anywhere) and
imports one back, adding only entries that aren't already there.

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

The app's name is the trigger, so phrases are natural:

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
