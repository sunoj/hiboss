# App Privacy answers (App Store Connect)

These answers match `ios/App/PrivacyInfo.xcprivacy`, `ios/Widgets/PrivacyInfo.xcprivacy` and
`ios/HiBossShare/PrivacyInfo.xcprivacy`: `NSPrivacyTracking` is false, there are no tracking
domains and no collected data types.

## Data collection

**Do you or your third-party partners collect data from this app?** No.

Resulting label: **Data Not Collected**.

## Why

- Messages, decisions, session content, panels, Box items, media, device labels and push
  tokens go only to the HiBoss server the user connects to. The user or their server's
  operator runs that server; the developer has no access to it.
- The app contains no advertising, analytics, crash-reporting or third-party SDK, and has no
  developer account system.
- The demo ("Explore the demo") uses built-in sample data and makes no network requests.
- Pairing-code camera frames are processed on the device and never uploaded.
- The push relay (`push.hiboss.org`, contract in `docs/push-relay.md`) is used only when the
  user's server has no APNs key. It stores the APNs device token, its environment, digests of
  the relay handle and device secret, and registration timestamps, solely to deliver the
  notifications the user's server requests. It never receives notification content, which is
  encrypted with a key that exists only on the device and the user's server. It keeps no IP
  addresses and no logs of tokens or payloads, and deletes registrations unused for 90 days.
  The relay links no data to a user identity and uses none for tracking or advertising.

## Tracking

**Does this app use data for tracking?** No. No data is linked to the user's identity or
shared with data brokers, and the app does not use the App Tracking Transparency prompt.

## Required-reason APIs (declared in the manifests)

| Target | User defaults | System boot time |
|---|---|---|
| App | `CA92.1`, `1C8F.1` | `35F9.1` |
| Widgets | `CA92.1` | `35F9.1` |
| Share extension | `CA92.1`, `1C8F.1` | `35F9.1` |
