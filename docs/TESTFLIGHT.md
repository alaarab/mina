# Shipping to TestFlight

`scripts/release.py` archives the app, exports it for App Store Connect, and
uploads it. Successful uploads advance the build counter; export-only runs do
not. Mina uploads require explicit confirmation that the CloudKit Production
schema is deployed. It needs one file:

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

The version (`MARKETING_VERSION` in `project.yml`: 1.0.0, 1.0.1, ...) is the
release people see; bump it by hand with a new `CHANGELOG.md` section.
`release.py` sets only the build number, from its counter, on every upload
(`--marketing-version` overrides). TestFlight ranks builds by version first,
so a version must never go backwards. App Store Connect rejects a build number
it has already seen.

## Changelog

`CHANGELOG.md` at the repo root is the single source: the app bundles it (a
pre-build step copies it into Resources) and shows the newest section once
after an update and the whole thing under Settings → What's new; `asc-fill.py`
pushes the newest section as the App Store "What's New". A test fails if the
newest heading doesn't match the app version, so add a `## 0.0.N` section
before each upload.

## Each release

```sh
# Safe preparation while CloudKit deployment is outstanding:
scripts/release.py --export-only

# Only after Production schema deployment and sync have been verified:
scripts/release.py --schema-deployed
```

Processing typically takes 10–30 minutes, then assigned testers get the update.
Builds expire after 90 days.

The project includes a Watch companion. Install the watchOS simulator platform
with `xcodebuild -downloadPlatform watchOS` before running the iOS test scheme.
If XCTest never starts on an existing simulator, retry on a fresh simulator and
fresh derived-data directory before changing application code. Override the
release test destination with `--test-destination 'platform=iOS Simulator,id=…'`.

## When the data model changes

Adding a field to `MinaModel.swift` means CloudKit's Production schema needs it
before any TestFlight phone can sync that field. `release.py` prints a warning
when the model file changed since the last upload. The historic helper path is to build the app
with the bundle id suffix `.recovery` (it calls `initializeCloudKitSchema` on
launch and writes `Documents/schema.txt`), run it once on a phone signed in to
the developer's iCloud, then Deploy Schema Changes in the CloudKit console.
Symptom if skipped: "Export failed · CKErrorDomain 2" in Settings → Sharing.

The owner currently requires **TestFlight-only phone installs**. Do not install
the `.recovery` helper or any development build on either phone. Instead, inspect
the Development schema in CloudKit Console. If the photo fields are already
present, deploy them there. If absent, initialize Development from an authorized
development environment or use an authenticated CloudKit management workflow;
TestFlight itself cannot initialize Development. This Mac currently has no
CloudKit management token, and an App Store Connect key cannot substitute for it.

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
captures (`-seed-demo`) at 1320×2868 with a caption band, plus a matching iPad set
(display type `APP_IPAD_PRO_3GEN_129`, 2064×2752 from the iPad Pro 13-inch
simulator); the preview is cut from the tour recording at 886×1920.

`scripts/asc-audit.py` reads the current metadata and assets.
`scripts/asc-prepare.py --contact-phone '+country-code number' --public-distribution`
fills review contact details, initializes a Free price schedule, and enables
public territory availability without submitting. Keep personal contact numbers
out of checked-in files. Existing pricing/availability is retained, not reset.
`scripts/asc-stage-review.py` creates a draft review submission and attempts to
attach the version; it exposes Apple's missing-field checks but **never submits**.

The 2026-09-20 preflight, after saving Content Rights, still requires the regulated
medical device declaration and published App Privacy answers. App Privacy and medical
device status must be completed in App Store Connect; the public API used here
does not expose those questionnaires. Do not submit until the declarations,
Production schema, and two-phone sync checks are complete.

`scripts/asc-preview.py path/to/preview.mp4` uploads the reviewed en-US portrait
preview, retaining existing assets. Run it again after Apple's processing is
COMPLETE to put the new preview first. This changes listing assets, not submission
state. Never use unreviewed output or footage that misrepresents the submitted build.

The Nanit integration remains disabled in App Store builds (`FeatureFlags.nanit`).
Do not ask public-build testers for its hidden Events seen screen or enable the
private integration in a public release merely to finish a diagnostic task.
