# First installation on an empty self-hosted server

1. Deploy the Worker with `BOOTSTRAP_SECRET` set using
   `npx wrangler secret put BOOTSTRAP_SECRET`.
2. Run `hiboss setup --server <url> --bootstrap-secret <secret>` on the first
   machine. `HIBOSS_BOOTSTRAP_SECRET` may supply the secret instead. Never echo it.
   Use `--boss-name <name>` to select the first boss's name. Otherwise use the
   local user's full name or login, prompting when standard input is a terminal.
   If no boss exists, call `POST /api/bootstrap/boss` and display the
   `hiboss://pair?server=<url>&code=<code>` link, its terminal QR code, the pairing
   code, expiry, and this instruction:
   "Scan with the HiBoss iPhone app, or open HiBoss on the Mac and choose Pair with code."
   A 409 means a boss already exists; continue enrollment. Enroll this machine
   through the existing join flow and wait for boss approval. Rerunning setup
   resumes a pending request.
3. Profiles requested while the server has no agents, with a valid bootstrap
   secret, receive `api_keys.is_admin = 1` at approval. Other enrollments receive
   zero. Store bootstrap eligibility on the join request using an additive
   migration; approval uses that stored state.
4. An admin boss can PATCH the existing boss-side agent management route with
   `{ "admin": boolean }` to grant or remove agent admin capability. Reject
   managers and viewers with 403 or 404. Audit every change. Add a CLI interface
   only if a boss-authenticated agent command already exists.
5. Reject role changes and hard deletion that would leave no live, non-archived
   admin bosses with 409. Preserve the archive route's last-admin protection.
6. Guided Discord command registration sends normal agent authentication.
   A non-success response fails setup with a nonzero exit status.

Bootstrap secrets use the existing constant-time comparison and are never
logged, printed, or stored. Bootstrap does not issue a bearer token. Agent
bootstrap stops once an agent exists; boss bootstrap stops once a boss exists.
Credentials require the secret or an approved enrollment.

HTTP server regression tests cover rules 3–5. CLI mock-server tests cover
pairing output, secret omission, and authenticated Discord registration errors.
