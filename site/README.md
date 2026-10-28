# HiBoss public site

This static site serves `hiboss.org`: the home page, download page, self-host and agent guides, changelog, privacy policy and support page, with Chinese versions of home, download and the self-host guide under `/zh/`. It is plain HTML and one stylesheet, with no scripts, cookies or external resources. It is separate from the authenticated admin console in `web/`.

## Editing

- Pages include the shared header and footer in `partials/`, with separate English and Chinese
  fragments. `render.py` sets each page's current navigation link and language counterpart at build time.
- The App Store link is a single marked line in `download/index.html` and `zh/download/index.html` (`APP STORE SWITCH`).
- iPhone screenshots in `assets/shots/` come from the iOS app's demo mode, at 600 px wide,
  in light and dark variants. Decision captures enable `HIBOSS_DEMO_OPTION_MEDIA=1` so image
  previews, option descriptions and the default choice are visible together.
- `mac-island-*.jpg` captures the native Mac Island using
  `IslandAppearanceSnapshotTests/testReferenceDecisionInBothAppearances` with
  `HIBOSS_V4_SNAPSHOTS` set to the capture directory. The Island stays dark in both appearances.
  Keep every image under 400 KB.
- A new file must also be added to the list in `build.sh`.
- `404.html` at the root is what Cloudflare Pages serves, with status 404, for an unknown path.
- `updates/macos/appcast.xml` is the Mac app's Sparkle feed; `macos/scripts/release.sh` rewrites it for each release (`macos/RELEASE.md`).

## Preview

Build into a new directory, serve that output, and open `http://localhost:8080/`:

```sh
site/build.sh /absolute/new/preview-directory
python3 -m http.server 8080 --directory /absolute/new/preview-directory
```

## Build

Run `site/build.sh /absolute/new/output-directory` from the repository root. The script renders the listed HTML pages and copies an explicit list of public assets into a new directory.
Building requires Bash and Python 3.10 or later; the output has no runtime dependencies. Templates and build scripts
are excluded from the public output.

## Verification

Run `python3 -B site/test_build.py -v` from the repository root. The tests build into an isolated
output directory and check the public file set, navigation, resource links and output-directory guard.

## Hosting

Deploy that output directory to Cloudflare Pages with `hiboss.org` as the custom domain.

For a Direct Upload project, deploy the output directory with Wrangler:

```sh
npx wrangler pages deploy /absolute/output-directory --project-name YOUR_PAGES_PROJECT --branch main
```

Provide Cloudflare credentials through the deploy environment. Keep them outside the output directory and repository.
