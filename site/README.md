# HiBoss public site

This static site serves the product home page, iOS privacy policy, and support page for `hiboss.org`. It is separate from the authenticated admin console in `web/`.

## Preview

Run the server from `site/` and open `http://localhost:8080/`:

```sh
cd site
python3 -m http.server 8080
```

## Build

Run `site/build.sh /absolute/new/output-directory` from the repository root. The script copies an explicit list of public files into a new directory. It has no runtime dependencies.

## Hosting

Deploy that output directory to Cloudflare Pages with `hiboss.org` as the custom domain. The privacy policy and support pages are available at `/privacy/` and `/support/`.
