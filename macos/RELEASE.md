# Releasing HiBoss Island (macOS)

In-app updates use [Sparkle](https://sparkle-project.org) with an EdDSA-signed
appcast at `https://hiboss.org/updates/macos/appcast.xml`, the default `SUFeedURL`.
The appcast is a static file of the public site (`site/updates/macos/appcast.xml`),
and each build is a zip attached to the GitHub Release `macos-v<version>`. Sparkle
verifies each build's signature before installing, so the artifacts are public.

## One-time setup

1. **Generate the EdDSA key pair** (private key is stored in your login Keychain;
   the public key is printed once):
   ```sh
   cd macos && swift build            # fetches Sparkle into .build/artifacts
   ./.build/artifacts/sparkle/Sparkle/bin/generate_keys
   ```
   Copy the printed public key — this is `HIBOSS_SPARKLE_PUBKEY`. It is **not**
   secret (it only verifies signatures) but is deployment-specific, so it is
   injected at build time rather than committed.

2. **Store notary credentials** (only needed to notarize; the profile name is
   what `NOTARY_PROFILE` refers to). The App Store Connect API key belongs to
   team `<APPLE_TEAM_ID>`:
   ```sh
   xcrun notarytool store-credentials hiboss-notary \
     --key ~/.asc/keys/AuthKey_<KEY_ID>.p8 \
     --key-id <KEY_ID> \
     --issuer <ASC_ISSUER_ID>
   ```
   The profile is stored in your login Keychain.

## Cut a release

From `macos/`:
```sh
HIBOSS_SPARKLE_PUBKEY=<public key from step 1> \
[HIBOSS_SIGNING_IDENTITY="Developer ID Application: … (JHH9GC8Y8C)"] \
[NOTARY_PROFILE=hiboss-notary] \
./scripts/release.sh 1.0.0 "What changed in this version."
```

`release.sh` builds the versioned, Sparkle-embedded `.app`, notarizes and staples
it when a notary profile is set, zips it to
`.build/release-artifacts/HiBoss-Island-<version>.zip` after `security-guard` scans the
signed bundle (when installed), EdDSA-signs the zip, and
writes a one-item appcast to `site/updates/macos/appcast.xml` whose enclosure
points at the GitHub Release asset. It uploads nothing, so every run is a dry run
until you publish:

1. Create the GitHub Release with the command the script prints
   (`gh release create macos-v<version> …/HiBoss-Island-<version>.zip …`).
2. Commit `site/updates/macos/appcast.xml` and deploy the site (`site/README.md`).

Publish in that order: an appcast that goes live before its zip exists offers an
update that fails to download. Running clients pick the update up within
`SUScheduledCheckInterval` (24 h) or via **Settings → About → Check for Updates…**.

`HIBOSS_SPARKLE_KEY_FILE` points `sign_update` at an exported private key instead
of the login Keychain. `HIBOSS_RELEASE_REPO` (default `sunoj/hiboss`) names the
repository whose release hosts the zip.

- Without `HIBOSS_SIGNING_IDENTITY`: ad-hoc signed — fine for personal installs,
  but Gatekeeper warns on first launch for other machines.
- With `HIBOSS_SIGNING_IDENTITY` + `NOTARY_PROFILE`: Developer-ID signed,
  notarized, and stapled (clears Gatekeeper offline).

`build-app.sh` signs with the hardened runtime and a secure timestamp — both
required by notarization — whenever the identity starts with `Developer ID`.
The local development identity keeps the fast, offline `--timestamp=none` path,
so ordinary builds do not need the network.

## Builds without an update key

Anything not built through `release.sh` (or `build-app.sh` with
`HIBOSS_SPARKLE_PUBKEY`) has no `SUPublicEDKey`, so the app runs with **no updater
at all** — it never checks and never alerts, even though the tracked
`Resources/Info.plist` carries the default `SUFeedURL`.
Do not put placeholder values in `Resources/Info.plist`: Sparkle treats an empty
`SUPublicEDKey` as *invalid* rather than absent and refuses to start, which
surfaces as a modal "Unable to Check For Updates" on every launch.

## Changing the signing identity

Sparkle only installs an update whose code signature matches the running app's.
Switching identity (e.g. Apple Development → Developer ID) breaks that match, so
that one build has to be installed by hand; updates resume from there.
