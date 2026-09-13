# Shipping to TestFlight

`scripts/release.py` archives the app, exports it for App Store Connect, and
uploads it. Each run auto-increments the build number. It needs one file:

```json
// ~/.config/ios-release.json
{
  "team": "ABCDE12345",
  "key_id": "ABC123DEFG",
  "issuer_id": "00000000-0000-0000-0000-000000000000",
  "key_path": "~/.private_keys/AuthKey_ABC123DEFG.p8"
}
```

## Once per Apple account

1. App Store Connect → Users and Access → Integrations → App Store Connect API →
   Generate API Key, role **App Manager**. Download the `.p8` once (it can't be
   downloaded again), put it in `~/.private_keys/`, and note the Key ID and Issuer ID.
2. Accept any pending agreements under Agreements, Tax, and Banking. Uploads
   fail quietly until you do.

## Once per app

1. App Store Connect → Apps → **+** → New App: platform iOS, the bundle ID, a SKU
   (the bundle ID is fine), primary language.
2. App Information → privacy policy URL (any page that says what the app does with
   data; a GitHub README section works).
3. TestFlight → Test Information: beta description, feedback email.
4. Testers: **Internal** testers are people on your App Store Connect team and get
   builds instantly. **External** testers join by a public link, but the first build
   goes through Beta App Review (usually under a day).

## Version numbers

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` feed both the
app and the widget Info.plists. `release.py` sets the build number from its
counter on every upload; bump the marketing version in `project.yml` (or pass
`--marketing-version`) when the App Store version changes. App Store Connect
rejects a build number it has already seen.

## Each release

```sh
scripts/release.py            # tests, archives, uploads, bumps the build number
scripts/release.py --skip-tests --marketing-version 0.2.0
```

Processing takes 10–30 minutes, then testers get the update automatically.
Builds expire after 90 days.

## When the data model changes

Adding a field to `MinaModel.swift` means CloudKit's Production schema needs it
before any TestFlight phone can sync that field. `release.py` prints a warning
when the model file changed since the last upload. The steps: build the app
with the bundle id suffix `.recovery` (it calls `initializeCloudKitSchema` on
launch and writes `Documents/schema.txt`), run it once on a phone signed in to
the developer's iCloud, then Deploy Schema Changes in the CloudKit console.
Symptom if skipped: "Export failed · CKErrorDomain 2" in Settings → Sharing.

## Mina-specific: CloudKit production

TestFlight builds use the **production** CloudKit environment. Before the first
upload, open the [CloudKit Console](https://icloud.developer.apple.com/), pick
the `iCloud.com.alaarab.mina` container, and **Deploy Schema Changes** from
Development to Production. Do this again after any change to the Core Data model.

Data logged in a development (Xcode) build lives in the development
environment and will not appear in a TestFlight build. Move everyone to
TestFlight at the same time, then share the log again from the TestFlight app.

## App Store

The listing copy lives in `docs/store/listing.md`; `scripts/asc-fill.py` pushes it
(description, keywords, promo text, URLs, subtitle, categories, copyright) to the
current App Store version through the API. Screenshots are composed from simulator
captures (`-seed-demo`) at 1320×2868 with a caption band; the preview is cut from
the tour recording at 886×1920. Things the API won't set: the review contact phone,
the App Privacy questionnaire ("Data Not Collected"), pricing, and the Submit button.
