# Releasing HiBoss Island (macOS)

In-app updates use [Sparkle](https://sparkle-project.org) with an EdDSA-signed
appcast served from the hiboss Worker (R2) under `/updates/macos/`. Sparkle
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

2. **Set the upload secret on the Worker** (any strong random string):
   ```sh
   cd ../server && npx wrangler secret put RELEASE_UPLOAD_SECRET
   ```
   Use this same value as `UPLOAD_SECRET` when running `release.sh`.

3. **Deploy the server** so `/updates/macos/*` is live:
   ```sh
   cd server && npx wrangler deploy
   ```

## Cut a release

From `macos/`:
```sh
UPLOAD_SECRET=<worker RELEASE_UPLOAD_SECRET> \
HIBOSS_UPDATES_BASE=https://<your-server>/updates/macos \
HIBOSS_SPARKLE_PUBKEY=<public key from step 1> \
[HIBOSS_SIGNING_IDENTITY="Developer ID Application: … (TEAMID)"] \
[NOTARY_PROFILE=hiboss-notary] \
./scripts/release.sh 0.2.0 "What changed in this version."
```

`release.sh` builds the versioned, Sparkle-embedded `.app`, zips it, EdDSA-signs
the zip, writes a one-item `appcast.xml`, and PUTs both to the Worker. Running
clients pick the update up within `SUScheduledCheckInterval` (24 h) or via
**Settings → About → Check for Updates…**.

Add `SKIP_PUBLISH=1` to build and sign everything without uploading — the zip
and `appcast.xml` land in `.build/release-artifacts/` for inspection before they
go public. `UPLOAD_SECRET` is not required in that mode.

- Without `HIBOSS_SIGNING_IDENTITY`: ad-hoc signed — fine for personal installs,
  but Gatekeeper warns on first launch for other machines.
- With `HIBOSS_SIGNING_IDENTITY` + `NOTARY_PROFILE`: Developer-ID signed,
  notarized, and stapled (clears Gatekeeper offline). Notarization also needs a
  hardened-runtime build, which `build-app.sh` does not yet produce.

## Builds without an update feed

Anything not built through `release.sh` has no `SUFeedURL`/`SUPublicEDKey`, so
the app runs with **no updater at all** — it never checks and never alerts.
Do not put placeholder values in `Resources/Info.plist`: Sparkle treats an empty
`SUPublicEDKey` as *invalid* rather than absent and refuses to start, which
surfaces as a modal "Unable to Check For Updates" on every launch.

## Changing the signing identity

Sparkle only installs an update whose code signature matches the running app's.
Switching identity (e.g. Apple Development → Developer ID) breaks that match, so
that one build has to be installed by hand; updates resume from there.
