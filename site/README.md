# HiBoss public site

This static site serves the product home page, iOS privacy policy, and support page for `hiboss.org`. It is separate from the authenticated admin console in `web/`.

## Preview

Run the server from `site/` and open `http://localhost:8080/`:

```sh
cd site
python3 -m http.server 8080
```

## Hosting

The directory has no build step or runtime dependencies. A Cloudflare Pages project can publish `site/` as its output directory with no build command, then attach the `hiboss.org` custom domain. The domain's DNS zone is on Cloudflare. Publish only after verifying the actual output with `security-guard artifact site --repo <repo>` and reviewing the privacy/support copy, DNS, and the public response from a remote host.

The contact address `hi@hiboss.org` was supplied for the privacy and support pages. Verify its mailbox independently before deploying.
