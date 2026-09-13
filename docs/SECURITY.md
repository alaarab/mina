# Security

Mina is a newborn log for two phones. There is no Mina server, no account and no
analytics. This page says where the data actually lives, who can read it, and
what an attacker gets in the three cases worth worrying about.

## What is stored, and where

| Data | Where it lives |
| --- | --- |
| Entries, baby name and birthday | `Mina.sqlite` / `Mina-shared.sqlite` in the App Group container `group.com.alaarab.mina`, and in the user's own iCloud (CloudKit container `iCloud.com.alaarab.mina`) |
| Settings: units, your name, partner alerts on/off, device id, last bottle | `UserDefaults` in the same App Group |
| Nanit sign-in token, if a camera is connected | Keychain, service `com.alaarab.mina.nanit` |
| Nanit password | Nowhere. It is held in memory on the link sheet only for the two calls the login needs, then cleared |

The App Group is what lets the widgets read and write the same log as the app.
It is also why the store is not inside the app's own sandbox directory.

## Who can read it

- **Both parents**, through CloudKit sharing. The owner creates a `CKShare` on
  the baby record; the share sheet offers read-write and private-only
  (`availablePermissions = [.allowReadWrite, .allowPrivate]`), so there is no
  public "anyone with the link" mode and the invitee must be a specific Apple
  Account. Either parent can see the other's entries, names and notes. That is
  the point of the app.
- **Apple**, to the extent that iCloud holds the records. Mina uses the private
  and shared CloudKit databases, not the public one.
- **Nanit**, for the account the user connects, and only the camera event list
  Mina reads back.
- **Nobody else.** Nothing is sent to the developer or to any third party.

Settings shows a participant's email or phone number only when iCloud has no
name for them yet, only on the owner's phone, and only the address the owner
typed into the share sheet in the first place. The invitee never sees it.

## Threats

**Someone has the unlocked phone.** They have the log, the same as if they had
the app. Mina has no passcode of its own, and adding one would be theatre next
to the phone's own.

**Someone has the phone, locked.** The store files and the App Group directory
are `NSFileProtectionCompleteUntilFirstUserAuthentication`, so a phone that has
not been unlocked since it booted holds them encrypted with keys that are not in
memory. After the first unlock the files are readable to anything running as the
app, which is the price of CloudKit importing the partner's entries in the
background and widgets refreshing on the lock screen. The Nanit token is
`kSecAttrAccessibleAfterFirstUnlock` for the same reason, and
`kSecAttrSynchronizable = false` so it never rides iCloud Keychain to another
device. Lock-screen widgets mark their content `.privacySensitive()`, so feed
and sleep figures are redacted until the phone is unlocked, and partner
notifications obey the usual "show previews when unlocked" setting.

**Someone has the iCloud account.** They have everything: the records, and the
ability to add themselves to the share. iCloud is the trust boundary; Mina
cannot be stronger than the Apple Account behind it. Two-factor authentication
on that account is the real control here.

**Someone is on the network.** CloudKit traffic is Apple's, over TLS. The only
other traffic is Nanit: HTTPS to `api.nanit.com`, TLS 1.2 minimum, App Transport
Security left at its defaults with no exception domains, and no custom trust
evaluation anywhere in the app. The Nanit session is an ephemeral `URLSession`
with no cookie jar, no credential store and no on-disk cache, so nothing about
the session is written outside the Keychain. Requests time out at 20 seconds.

## Decisions worth knowing

- Errors from Nanit are scrubbed before they reach the UI: any value under a key
  that looks secret, and any bare 20-character token-shaped run, becomes `***`.
  The raw reply body is never interpolated into an error message.
- Nanit's API is undocumented and unofficial. Every reply decodes leniently: a
  record that does not parse is skipped rather than failing the whole sync, and
  a shape Mina does not recognise is a soft error, never a crash.
- Disconnecting Nanit deletes the Keychain token (both the synchronisable and
  non-synchronisable forms, for items written by older builds), the camera, the
  processed message ids, the seen type list and the scheduled background
  refresh.
- Partner notifications carry the baby's name and the entry, by design: that is
  the feature. They use `interruptionLevel = .active`, so they never break
  through a Focus, and free note text is cut to 120 characters so a long private
  note cannot spill onto a lock screen in full.
- Both bundles ship a `PrivacyInfo.xcprivacy` declaring no tracking, no
  collected data types, and `UserDefaults` as the only required-reason API, with
  reasons `1C8F.1` (App Group) and `CA92.1` (this target's own defaults, read
  once to migrate pre-App-Group settings).

## Out of scope

- A jailbroken or malware-carrying phone. Mina relies on iOS sandboxing.
- A compromised Apple Account, as above.
- Anything Nanit does with the account on their side.
- Hiding the log from the other parent. Sharing is symmetric on purpose.
- Erasing data from a partner's phone after unsharing. Revoking the share cuts
  iCloud access; a local copy already on their device stays theirs to delete.

## Reporting

Mina is open source at <https://github.com/alaarab/mina>. Open an issue. There
is no server to take down and no user data for a maintainer to leak, so please
report through the repository rather than privately.
