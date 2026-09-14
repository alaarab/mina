# Changelog

Newest first. The version is the release (1.0.0, 1.0.1, ...); the build number counts uploads. The in-app "What's new" reads this file; keep entries short and about what a parent notices.

## 1.0.0

### New
- Quiet: the bell on Today pauses the feed alarm, reminders and partner alerts on this phone for an hour, three hours, until morning, or until you turn them back on. Quiet hours in Settings do it nightly.
- Today's goals: feeds, wet and dirty diapers, sleep and the gap since the last feed, with targets for her age and rings that know what time of day it is. Set your own targets in Settings if the pediatrician gave you numbers.
- Sunday evening digest: one notification with the week's feeds, diapers and sleep, and how it compares to last week.
- Siri's "how is my baby doing today" now includes the goals.
- Weight, length and temperature have their own unit setting (pounds and ounces by default), separate from bottle amounts.
- Say "my baby", "the baby" or "our baby" instead of "Mina" in any Siri phrase; replies use her real name.
- More than one baby: add a second child, pick one in Settings, and name one in a phrase ("log a bottle for Olivia").
- Who's on: tap "I'm on" so only your phone rings and gets alerts tonight; hand off with one tap, or set a nightly schedule.
- Feed alarm that rings through silent mode and re-arms itself after every feed. Stopping it never logs a feed; the app asks "Did she eat?"
- Ask can take questions by voice and read answers aloud, all on the phone.
- Backup: export every entry to a file and import it anywhere.
- History: search every entry, filter by feeds, diapers, sleep, health or notes. Tap the Feeds, Diapers or Sleep tiles to open it.
- Nursing timer with side switching and a "start on the left" suggestion; Pump has its own button.
- Every millilitre by voice or keyboard; edit any entry's amount and time with quick nudges.

### Fixed
- A sync catch-up could send dozens of partner alerts at once. Alerts are now one summary per sync, only for entries from the last 90 minutes, and at most six an hour.
- Faster Today screen and less battery: totals are computed once per refresh and Spotlight indexing is coalesced.
- Siri now says "15 minutes", not "15m".
- The feed alarm no longer comes back after you stop it, and it follows feeds from either phone.
- Partner's "I'm on" shows up without relaunching.
- Sharing screen shows each person's access and the real sync error when something is stuck.
