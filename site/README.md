# HiBoss public site

This static site serves the product home page, iOS privacy policy, and support page for `hiboss.org`. It is separate from the authenticated admin console in `web/`.

## Preview

Run the server from `site/` and open `http://localhost:8080/`:

```sh
cd site
python3 -m http.server 8080
```

## Hosting

The directory has no build step or runtime dependencies. Serve `site/` as the static root for `hiboss.org`. The privacy policy and support pages are available at `/privacy/` and `/support/`.
