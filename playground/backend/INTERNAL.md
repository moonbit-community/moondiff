# Playground backend design

English | [简体中文](INTERNAL_CN.md)

## Authentication and session lifecycle

The backend validates cookies and CSRF tokens, and authorizes users through the
[GitHub App Device Flow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token-for-a-github-app).
GitHub's device code request uses the client ID; token polling uses the same ID,
the device code and the device grant type. No browser callback or client secret
is used. Token refreshes require only the client ID, refresh token and refresh
grant type. Shared refresh requests persist their rotated token pair in a
transaction.

The backend reserves an authorization before its first network operation.
SQLite stores its session, authorization identifier, state version, phase,
encrypted credentials, public code, verification URL, expiry, interval, next
deadline and retry backoff. A partial unique index permits one active
authorization per session. Overlapping starts reuse it through alias records.
Cancelled attempts are retained until expiry, including attempts cancelled
before their start arrives.
Late requests cannot recreate a cancelled attempt. Each attempt is limited to
15 minutes; GitHub can shorten that deadline. The current pending authorization
data format does not support old tokens or provide migration.

Pending operations share an async task per authorization. Deadlines are persisted
in milliseconds and browser wait values round up to seconds, so subsecond
rounding cannot violate GitHub's interval. Each response requesting slower
polling increases the interval by at least five seconds. Transient network
failures, 5xx errors and rate limits trigger retries with backoff, respecting
retry delays expressed in seconds in response headers. Rate-limit and transient
failure state survives a restart. Denial, expiry, invalid device codes and
configuration errors end the attempt and clear its encrypted credentials.

After the device code is exchanged for tokens, the encrypted token response and
its issue time are saved, and authorization enters the identity verification
phase before querying the user's identity. A transient identity lookup failure
can be retried after restart without redeeming the code again or extending the
token's lifetime. Session tokens are saved only after identity verification.
Saving the tokens and completing authorization share a transaction and advance
the session state version, so an old refresh cannot overwrite the new login.
Cancelling and logging out also
invalidate operations that are already in flight. Device authorization tasks,
like refresh tasks, continue even if an individual HTTP request waiting for the
result is cancelled.

The browser renders the code and opens GitHub's verification page only after a
user click. Production accepts only GitHub's official device verification page;
test mode accepts only the device verification page at its configured loopback
OAuth origin. The frontend MoonBit `github_client` owns CSRF, request generations, auth versions and status sequences, and schedules at most one poll, checks both request
identifiers and its authentication state version, and clears timers and requests
on cancellation, logout and page unload.
Normal change navigation keeps authentication progress. Initialization and page
reactivation restore the server session, including an unexpired pending code.

The account ID is retained when credentials fail or expire, so signing back into
the same account preserves drafts. Switching accounts clears the previous account's
data and draft. Sessions expire after 30 days. The only browser credential is a
random HttpOnly, SameSite=Lax cookie; HTTPS uses a Secure cookie restricted to the
current host. SQLite stores its SHA-256 digest, the GitHub user ID, CSRF token and
encrypted GitHub token pair. Writes require the request origin to match the
configured public URL and include a session CSRF token. Logout deletes the
session and pending authorizations; late device requests and refreshes cannot
recreate it. The origin is never inferred from proxy headers.

## Token encryption and comparison

Token envelopes use AES-256-CBC with PKCS#7 padding and a new 16-byte IV for every
encryption. The 64-byte key splits into independent
32-byte encryption and HMAC keys. HMAC-SHA256 authenticates the envelope version,
session digest, GitHub user ID, IV and ciphertext. Pending device authorization
envelopes use an authorization identifier marked as a device authorization
instead of the user ID, binding credentials to both the session and
authorization. A constant-time comparison verifies the HMAC before any
decryption or padding removal. A stored key check rejects startup with a
different key.

HMAC and CSRF use the same constant-time comparison method. For equal lengths,
it visits every byte and combines the differences before deciding whether the
values are equal. Length mismatches return immediately because these lengths
are public. Recheck the comparison's actual timing behavior when changing the
compiler or execution target: the design and functional tests alone do not
guarantee constant-time behavior at runtime.

## SQLite and process ownership

SQLite persists sessions and pending authorizations. The Wasm SQLite host
interface does not support database parameter tuning. New databases use SQLite's
default journal mode; existing WAL databases retain their mode. Triggers enforce
authorization/session ownership and cascading deletion independently of the
connection's foreign key enforcement setting. Native explicitly enables WAL,
foreign keys and a 5-second busy timeout.

The backend creates the database with read and write access restricted to its
owner and holds a database lock to prevent overlapping instances, including
during upgrades. The single-process lock applies to both targets. Operational
requirements and backup procedures are in
[Sessions and backup](../README.md#sessions-and-backup).

## GitHub requests and static assets

The backend restricts GitHub operations and arguments. Unknown operations and
extra arguments are rejected; deletion checks the comment author's GitHub user
ID. The server does not accept arbitrary upstream URLs or follow redirects when
sending requests. Response, request and pagination limits are listed in the
[HTTP contract](../README.md#http-contract).

The backend serves static resources and the app entry for valid change routes.
It rejects path traversal and symlinks outside the static root.
The health check endpoint becomes available after the database and listener have
initialized.

## Regression tests

- Encryption tests: token envelopes, padding and comparison.
- Shared protocol tests: all request/response roundtrips, strict validation, large IDs and source decoding on JS, Wasm, Wasm GC and Native.
- Backend integration tests: run in a Wasm runtime with a temporary SQLite
  database and local GitHub/OAuth mock services. They cover existing WAL
  databases, login and refresh without a client secret, shared polling, slow-down
  intervals, cancellation/expiry/denial, transient recovery and restart.
- Browser authentication tests: real Wasm device login in Chromium, code copying,
  explicit verification, reload, cancellation
  and delayed responses. The other frontend browser tests cover review regressions
  with same-origin RPC mock data.
- MoonBit transport tests with controlled network and timers: state versions, identifiers, concurrent polls, cancellation, late success/failure, lost start responses, canonical ID recovery and page unload.

See [verification commands](../README.md#checks-and-tests) to run these tests.
