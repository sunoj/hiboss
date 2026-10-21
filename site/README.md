# HiBoss public site

This static site serves `hiboss.org`: the home page, download page, self-host and agent guides, changelog, privacy policy and support page, with Chinese versions of home, download and the self-host guide under `/zh/`. It is plain HTML and one stylesheet, with no scripts, cookies or external resources. It is separate from the authenticated admin console in `web/`.

## Editing

- Every page repeats the same header and footer; change all pages together.
- The App Store link is a single marked line in `download/index.html` and `zh/download/index.html` (`APP STORE SWITCH`).
- Screenshots in `assets/shots/` come from the iOS app's demo mode on an iPhone simulator, at 600 px wide, in light and dark variants. Keep every image under 400 KB.
- A new file must also be added to the list in `build.sh`.
- `404.html` at the root is what Cloudflare Pages serves, with status 404, for an unknown path.
- `updates/macos/appcast.xml` is the Mac app's Sparkle feed; `macos/scripts/release.sh` rewrites it for each release (`macos/RELEASE.md`).

## Preview

Run the server from `site/` and open `http://localhost:8080/`:

```sh
cd site
python3 -m http.server 8080
```

## Build

Run `site/build.sh /absolute/new/output-directory` from the repository root. The script copies an explicit list of public files into a new directory. It has no runtime dependencies.

## Hosting

Deploy that output directory to Cloudflare Pages with `hiboss.org` as the custom domain.

For a Direct Upload project, deploy the output directory with Wrangler:

```sh
npx wrangler pages deploy /absolute/output-directory --project-name YOUR_PAGES_PROJECT --branch main
```

Provide Cloudflare credentials through the deploy environment. Keep them outside the output directory and repository.
