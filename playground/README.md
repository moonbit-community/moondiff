# Moondiff playground

English | [简体中文](README_CN.md)

## Local development

Install Node.js 22 and a MoonBit toolchain.

From the repository root:

```sh
moon update
cd playground
npm ci
```

Run the remaining commands from `playground/`.

### Runtime configuration

Create `.env` with the following content. Fill in the
[GitHub App settings](#github-app-setup) and replace the token key
placeholder with a persistent key generated using the command below.

```sh
# Export these variables before starting. The server does not load .env.
# Values shown below are defaults unless marked Required.
# Relative paths use the process working directory (playground/ for npm start
# and npm run dev); absolute paths are also accepted.

# HTTP listener IP and TCP port, without a URL scheme.
# 127.0.0.1 accepts only loopback connections.
MOONDIFF_LISTEN=127.0.0.1:4173

# Browser-facing root origin (scheme, hostname and optional port), used to
# check request Origin for login, logout and writes, and to select secure cookies.
# Match the browser origin exactly, including any non-default port;
# localhost and 127.0.0.1 are different origins. No subpath, query or fragment.
# Production requires HTTPS; HTTP is accepted only for localhost, 127.0.0.1
# and [::1]. Proxy headers do not override this setting.
# Example: https://diff.example.com can use a reverse proxy that terminates
# HTTPS and forwards HTTP to MOONDIFF_LISTEN=127.0.0.1:4173.
MOONDIFF_PUBLIC_URL=http://localhost:4173

# Built frontend HTML, JavaScript and other assets served by the backend.
# Created by npm run build; must exist before startup.
MOONDIFF_STATIC_DIR=dist/static

# SQLite file for sessions, encrypted GitHub credentials and pending device sign-ins.
# Created if missing; create its parent directory first and make it writable by
# the server user. Keep it on persistent storage; run one server per database.
MOONDIFF_DATABASE=moondiff.sqlite3

# Required, including locally: Base64 encoding of exactly 64 random bytes.
# Encrypts and authenticates stored GitHub tokens and device credentials.
# Generate once with: openssl rand -base64 64 | tr -d '\n'
# Keep it private, back it up separately and reuse it with the same database.
# A different key makes startup fail against an existing database. Losing or
# replacing the key requires a fresh database and users signing in again.
MOONDIFF_TOKEN_KEY=replace-with-base64-encoded-64-random-bytes

# Required, including locally: Client ID from your GitHub App settings.
# Used to start/poll device authorization and refresh user access tokens.
# Copy the Client ID field; the numeric App ID is a separate identifier.
MOONDIFF_GITHUB_CLIENT_ID=replace-with-github-app-client-id

# Required, including locally: installation link for the same App as the client ID.
# Shown in the playground so users can grant the App access to repositories.
# Must begin with https://github.com/apps/.
MOONDIFF_GITHUB_INSTALL_URL=https://github.com/apps/your-app/installations/new
```

See [Sessions and backup](#sessions-and-backup) for database
backup and restore instructions.

Export the variables and start the server:

```sh
# Automatically export subsequent new or modified shell variables to child processes.
set -a

# Read and execute .env in the current shell, exporting its configuration as environment variables.
. ./.env

# Disable automatic export; already exported variables remain available to the server.
set +a

# Build once and start the server using these environment variables, without watching for changes.
npm run dev
```

Open `http://localhost:4173`, or the configured `MOONDIFF_PUBLIC_URL`. This value
must match the browser origin. `npm run dev` rebuilds once and starts the server;
it does not watch for changes. Use `npm run build` to rebuild and `npm start` to
run existing artifacts.

To run the backend from source after exporting the configuration, use
`moon -C playground/backend run main` from the repository root. To select Native,
add `--target native --release`.

## GitHub App setup

Enable **Device Flow** in the GitHub App settings. The backend obtains and
refreshes user access tokens using the client ID, without a client secret or web
authorization callback. See GitHub's [Device Flow protocol](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token-for-a-github-app)
and [refresh protocol](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens#refreshing-a-user-access-token-with-a-refresh-token).

Configure repository permissions: Contents read/write and Pull requests
read/write, plus GitHub's required Metadata permission. Contents write is needed
for [commit comment deletion](https://docs.github.com/en/rest/commits/comments#delete-a-commit-comment);
Pull requests write also covers
[PR discussion comments](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment).
Existing installations must accept any changed App permissions. Install the app
on repositories that users need to review. Private access and writing also
require the signed-in user's own permissions. An App private key or installation
access token is not used.

Public repositories can be read anonymously. GitHub rate limits still apply.

Sign-in displays a verification code on the playground page. Copy it, open
GitHub, and authorize the device in the new window; the playground updates
automatically. A page reload restores an unexpired code. Cancel sign-in before
starting a new attempt.

## Build and deploy

Build a release from the repository root:

```sh
moon update
npm --prefix playground ci
npm run build
```

`playground/dist/` contains `moondiff-server.wasm` and `static/`. Copy both into
the release directory and install a compatible `moonrun` with trusted CA
certificates. Export the [runtime configuration](#runtime-configuration), then
run from the release directory:

```sh
MOONDIFF_STATIC_DIR=/absolute/release/static moonrun ./moondiff-server.wasm
```

Use an independent domain or port at `/`; deployment under a subpath is not
supported. `MOONDIFF_PUBLIC_URL` must equal the browser's origin and is not inferred
from proxy headers. The backend listener speaks HTTP; terminate production HTTPS
at a reverse proxy such as the supplied [Nginx example](deploy/nginx.conf.example).
Use a dedicated OS account and a private persistent data directory. Restrict the
upstream listener to the proxy. Run exactly one process per SQLite database,
including during upgrades.

## Sessions and backup

Sessions expire after 30 days. Logout ends the current playground session without
uninstalling the GitHub App or revoking other GitHub sessions.

Back up **both the database and the original encryption key**, with the key in a
separate protected secret store. Copying a live main DB file alone is unsafe,
especially for existing WAL databases. Use SQLite's online backup command,
adjusting the database path to match `MOONDIFF_DATABASE`:

```sh
sqlite3 /var/lib/moondiff/moondiff.sqlite3 '.backup /secure-backups/moondiff.sqlite3'
```

Alternatively, stop the service, checkpoint the WAL with
`sqlite3 /var/lib/moondiff/moondiff.sqlite3 'PRAGMA wal_checkpoint(TRUNCATE);'`, then
copy the DB before restarting. On restore, stop the service, restore the database
and matching key, set file ownership/mode, then start one instance and check
`/healthz`. Old database backups may contain refresh tokens GitHub has since
rotated, requiring a new sign-in. Losing or intentionally replacing the key
requires a fresh database and users signing in again; this version has no
in-place key rotation command.

## HTTP contract

| Method / path | Response / purpose |
| --- | --- |
| `GET /api/auth/status` | `{$tag:"Success",value:{authenticated,user_id?,login?,install_url?,csrf_token,device_flow?}}`; establishes an anonymous session and restores pending login |
| `POST /api/auth/device/start` | `{attempt_id}` creates or reuses the session's active authorization; returns `{request_id,status}` |
| `POST /api/auth/device/poll` | `{authorization_id}` advances that authorization when due; returns `{request_id,status}` |
| `POST /api/auth/device/cancel` | `{authorization_id}` cancels that authorization and returns current session status; returns `{request_id,status}` |
| `POST /api/auth/logout` | Invalidates the session and returns `Success(value=null)`; requires Origin and X-CSRF-Token |
| `POST /api/rpc` | `{v:2,request:GitHubRequest}` → `{$tag:"Success",value:RpcValue}` or `{$tag:"Failure",error:{status,code,message}}` |
| `GET /healthz` | `ok` when the service is ready |

All three device POSTs require the session cookie, configured Origin,
`X-CSRF-Token` and `Content-Type: application/json`; extra fields are rejected.
Start identifiers are generated by the browser (16–128 letters, digits, `-` or
`_`, e.g. a random UUID). Each start/poll/cancel returns the session status in the
`{$tag:"Success",value:{request_id,status}}` envelope. Logout returns a null success value; the client then queries status again.

`device_flow` contains `id`, `phase`, `user_code`, `verification_uri`,
`expires_at`, `retry_after` and `message`. Expiration is a numeric Unix timestamp
in seconds; retry delay is a number of seconds. Phases are `Starting`, `Pending`,
`Verifying`, `Completed`, `Cancelled`, `Expired`, `Denied` or `Failed`. The client
polls the returned canonical `id`, which may differ from a new start's attempt ID
when an existing authorization is reused. Cancellation also accepts the initial
attempt ID so it works before the start response arrives.

The browser only receives the user code and an allowlisted verification URL;
device credentials and GitHub tokens remain encrypted on the server. Users open
the verification page themselves, and this page polls without a login callback.
Server timing survives refresh and restart, enforces GitHub's minimum interval,
and adds at least five seconds after each `slow_down`. Temporary network, server
and rate-limit failures preserve the authorization with retry backoff. Rejected,
invalid or expired codes require a new attempt. Attempts last at most 15 minutes.
The former `/auth/login` and `/auth/callback` paths return 404.

RPC requests and responses are defined in the [shared protocol module](protocol/README.md),
imported by both applications as `@protocol`. `GitHubRequest` covers all 13
operations and `RpcValue` identifies the successful result type. Authentication
phases, comment targets and sides also use explicit tags, e.g. `{"$tag":"Pending"}`.
Source responses contain `{base64,size,content_type}`; comment IDs use decimal
strings to preserve 64-bit precision. Strict decoding compares re-encoded JSON
before validating parameter constraints, rejecting extra fields, fractional
integer values and overflow. The backend sends only modeled fields and reports
invalid upstream data as `invalid_github_response`; unexpected client result
kinds produce `invalid_server_response`. Upgrade both applications together:
there is no v1 compatibility layer, and the SQLite data format is unchanged.

Source responses are bounded to 1 MiB per side, upstream JSON responses to 8 MiB,
RPC bodies to 128 KiB and comments to 100 pages of 100.
`authentication_required`, `permission_denied`, `rate_limit`,
`not_found_or_not_installed`, `invalid_comment_anchor`, `source_too_large` and
`pagination_limit` remain distinguishable. Unknown operations and extra arguments
are rejected. Users can only delete their own comments. Write requests require
the configured Origin and a session CSRF token in `X-CSRF-Token`.

`GET`/`HEAD` serve assets and the app entry at `/`, `/owner/repo/commit/sha`,
`/owner/repo/pull/number` and `/owner/repo/pull/number/commits/sha`. Unknown paths
are 404. Old `/#/…` routes show an invalid-link error in the app, without conversion.

## Migration and verification

1. Deploy the Wasm module, compatible `moonrun`, static directory, persistent
   database location, key and App settings. Verify HTTPS, `/healthz`, and direct
   change links.
2. Build the small redirect extension with `MOONDIFF_PLAYGROUND_URL` set to this
   origin; see [extension instructions](../extension/README.md).
3. Existing extension credentials are removed on upgrade. Every user signs in
   again; no browser token or old review-page state is imported.
4. The Pages publishing workflow has been removed. At release cutover, disable
   the repository's old GitHub Pages site in Settings → Pages and remove its old
   custom-domain configuration if applicable. This repository change does not
   unpublish an already deployed Pages site. Replace old hash share links.

Run the [checks and tests](#checks-and-tests) before cutover. Production
authorization and installation must also be smoke-tested with your actual App.

## Checks and tests

From `playground/`, check and test all frontend packages from the module root,
including `internal/`, and run the backend checks:

```sh
moon -C frontend check --target js --deny-warn
moon -C frontend test --target js
moon -C backend check --deny-warn

# Test fixtures set MOONDIFF_TEST_MODE=1 to enable upstream overrides (off by default).
# MOONDIFF_TEST_GITHUB_URL replaces https://api.github.com for GitHub API requests.
# MOONDIFF_TEST_OAUTH_URL replaces https://github.com for device/token requests.
# Both URLs are required in test mode and must use loopback hosts, as must
# MOONDIFF_PUBLIC_URL. Overrides are ignored unless MOONDIFF_TEST_MODE=1.
# Leave all three test variables unset for normal development and production.
npm run test:server
```

`test:server` runs MoonBit tests, backend integration tests and browser HTTP
transport tests. After MoonBit changes, run `moon fmt` and
`moon info --target all` and review any generated interface changes.

For browser tests:

```sh
npx playwright install chromium
npm run test:e2e
```

Use `npx playwright install --with-deps chromium` if system libraries are missing,
and `npm run test:e2e:ui` for the interactive runner. Tests start their own Wasm
server on port 4173, so stop the local development server first. They use temporary
SQLite databases and a local GitHub/OAuth stub; no real GitHub credentials are
required. Frontend regression tests mock the same-origin API.

To verify the redirect extension and release artifacts:

```sh
npm run test:extension
npm run build
npm --prefix .. run test:artifacts
```

These test suites and artifact checks can also be run from the repository root
with `npm run test:server`, `npm run test:playground`, `npm run test:extension`,
then `npm run build && npm run test:artifacts`. See
[regression coverage](backend/INTERNAL.md#regression-tests) for the implementation
cases.

## Development references

- [Frontend packages](frontend/)
- [Backend authentication, encryption, storage and request handling internals](backend/INTERNAL.md)
- [Redirect extension development](../extension/README.md)
