# Playground protocol v2

English | [简体中文](README_CN.md)

`moonbit-community/moondiff-playground-protocol` is a standalone workspace module
shared by the frontend and backend as `@protocol`. It supports JS, Wasm, Wasm GC
and Native and contains only data types, JSON codecs and pure validation helpers.
The frontend and backend must be upgraded together. There is no v1 compatibility
layer, and this change does not change the SQLite storage format.

## Wire format

All API responses use `Response[T]`:

```json
{"$tag":"Success","value":...}
{"$tag":"Failure","error":{"status":403,"code":"permission_denied","message":"No access"}}
```

All enums explicitly derive `FromJson(style="legacy")` and
`ToJson(style="legacy")`. Positional payloads use the `"0"` field; named enum
arguments keep their labels. Optional record fields are omitted when absent.
Comment IDs are positive `Int64` values encoded as decimal strings, including
values above JavaScript's safe integer limit.

RPC requests use `{"v":2,"request":GitHubRequest}`. For example:

```json
{"v":2,"request":{"$tag":"CommitGet","0":{"owner":"alice","repo":"repo","sha":"123abcd","page":1}}}
```

A successful response to that request has a typed `RpcValue` payload:

```json
{"$tag":"Success","value":{"$tag":"Commit","0":{"sha":"123abcd","html_url":"https://github.com/alice/repo/commit/123abcd","commit":{"message":"Example"},"parents":[],"stats":{"additions":0,"deletions":0,"total":0},"files":[]}}}
```

| Request | Parameters beyond `owner`, `repo` | Result variant / data |
| --- | --- | --- |
| `CommitGet` | `sha`, `page` | `Commit(ApiCommit)` |
| `PullGet` | `number` | `Pull(ApiPull)` |
| `PullViewedGet` | `number` | `PullViewed(ApiPullViewed)` |
| `PullFileViewedSet` | `number`, `path`, `viewed`, `base_sha`, `head_sha` | `FileViewed(ApiFileViewedResult)` |
| `CompareGet` | `base`, `head` | `Compare(ApiCompare)` |
| `PullFiles` | `number`, `page` | `Files(Array[ApiFile])` |
| `ContentGet` | `path`, `revision` | `Content(ApiSource)` |
| `CommentsList` | `target` | `Comments(ApiCommentBundle)` |
| `IssueCommentCreate` | `number`, `body` | `IssueComment(ApiIssueComment)` |
| `ReviewCommentCreate` | `number`, `commit_id`, `path`, `line`, `side`, `body` | `ReviewComment(ApiReviewComment)` |
| `CommitCommentCreate` | `sha`, `path`, `position`, `body` | `CommitComment(ApiCommitComment)` |
| `ReviewReplyCreate` | `number`, `comment_id`, `body` | `ReviewComment(ApiReviewComment)` |
| `IssueCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |
| `ReviewCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |
| `CommitCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |

Comment targets are `Commit(sha~)`, `Pull(number~)` or
`PullCommit(number~, sha~)`. Sides are `Left` or `Right`, encoded as
`{"$tag":"Left"}` or `{"$tag":"Right"}`. `ApiSource` contains
`base64`, `size` and `content_type`; `ApiSource::decode` validates the Base64 and
checks its decoded byte length.

## Viewed synchronization

Both Viewed operations require a signed-in user. `PullFileViewedSet` is a write
and uses the existing Origin/CSRF checks. PR numbers remain decimal strings on
the wire and must fit a positive GraphQL `Int` (1–2,147,483,647).

`ApiPullViewed` contains `{base_sha, head_sha, files}`; each file is
`{path, state}`, where state is `{"$tag":"Viewed"}`, `{"$tag":"Unviewed"}` or
`{"$tag":"Dismissed"}`. Dismissed means the file changed since it was viewed.
`ApiFileViewedResult` contains `{base_sha, head_sha, file}`. Writes use the
current path, including a renamed file's new path, and a Boolean `viewed` target.
Snapshot SHAs refer to the PR base/head, not the diff's merge base.

The backend owns fixed GraphQL queries and mutations and resolves the PR node ID.
It reads 100 files per page, limits results to 3,000 files, rejects repeated
cursors, duplicate paths and incomplete pages, and verifies the snapshot across
pages and at the end. Writes compare the snapshot before the mutation and in
its returned PR. A mismatch returns `pull_snapshot_changed` (409). GitHub's
[Viewed mutation](https://docs.github.com/en/graphql/reference/pulls#markfileasviewed)
has no conditional SHA parameter, so a concurrent push cannot be prevented
atomically; a detected change blocks further marking until the diff is reloaded.
HTTP 200 GraphQL errors also fail the operation, including partial responses.

GitHub persists the state. In the single backend process, Viewed reads and writes
run in FIFO order per GitHub user ID, repository (case insensitive), and PR number,
including requests from different sessions. Other scopes run independently.
A write holds its place through snapshot preflight, mutation and result validation,
even after the browser disconnects. Upstream timeouts still apply; a failed queue
wait returns an error without executing the operation. Idle coordinators are removed.

The frontend isolates responses and retry timers by page, account, snapshot and
request sequence. Before sending a mutation it saves an operation ID, GitHub user
ID, repository, PR number, verbatim current path, target state and base/head SHAs
in `sessionStorage`. Storage failure prevents the write. Credentials, source code,
comments and expansion choices are never stored in these records. Confirmation or
an explicit rejection removes only the matching operation ID, so a late callback
cannot remove a newer operation.

A timeout, network interruption or interrupted request enters pending confirmation.
Only a read matching the saved target unlocks the file. Old values and failed reads
keep **Waiting for GitHub confirmation**, the optimistic state, expansion choices
and drafts; they do not prove the mutation was rejected. Explicit failures still
roll back the Viewed state and restore expansion unless a later interaction changed
it. Pending files cannot use **Retry Viewed** to resend a mutation; other files
remain operable. Recovery never automatically replays a mutation.

Confirmation reads run immediately, then after 2, 4, 8, 16, 30 and 30 seconds, with
one read in flight. Exhaustion retains the record and offers **Recheck Viewed**.
Rate limits, invalid authentication and changed snapshots pause automatic checking.
Manual checks and page reactivation start a new round; a changed snapshot first
requires **Load latest**. Login and reload recovery wait for the identity and PR
file list, then match records by user/repository/PR/path, never by file index.
Switching accounts isolates records. Loading a new snapshot retains unresolved
operations without restoring old expansion choices. No backend state, database
migration or RPC field is added for confirmation.

Records have no time-based expiry. The current tab's session storage covers reloads
and login recovery; closing the tab or clearing storage can lose them. There is no
cross-browser or cross-device coordination. Without a remote completion receipt an
uncertain operation can remain pending indefinitely. Reading the target means the
current state satisfies the request, not that operations across clients are ordered.

## Authentication endpoints

`GET /api/auth/status` returns `Response[ApiAuthStatus]`. The status contains
`authenticated`, `csrf_token`, and optional `login`, `user_id`, `install_url`,
`device_flow`. A flow contains `id`, `phase`, `user_code`, `verification_uri`,
`expires_at` (Unix seconds), `retry_after` (seconds) and `message`. Its phase is
one of `Starting`, `Pending`, `Verifying`, `Completed`, `Cancelled`, `Expired`,
`Denied` and `Failed`, using the same tagged enum format.

`POST /api/auth/device/start` accepts `DeviceStart` (`{attempt_id}`). The poll
and cancel endpoints accept `DeviceAuthorization` (`{authorization_id}`). All
three return `Response[DeviceResponse]`, whose value is `{request_id,status}`.
`request_id` echoes the submitted identifier; `status.device_flow.id` carries the
canonical authorization ID, which can differ after a start reuses an existing
attempt. Poll responses must match both identifiers.

`POST /api/auth/logout` returns `Response[Unit]` with `value:null`. The client then
queries status to establish the anonymous session and obtain a fresh CSRF token.

## Validation and scheduling

`decode_request` decodes the request and compares its re-encoded JSON to the
input before checking semantic constraints. This rejects extra fields, missing
required fields, unrecognized tags, fractional integer values and overflow.
Repository names, SHAs and relative paths are constrained; pages range from
1 to 10,000, line/position values are positive `Int`, and identifiers are positive
signed 64-bit values. Comments must contain 1–65,536 UTF-8 bytes after rejecting
whitespace-only text. Device IDs contain 16–128 letters, digits, `_` or `-`.

`valid_repository_path` validates source reads, PR/commit inline comments, Viewed
writes and paths returned by GitHub's Viewed listing. It rejects empty paths, NUL,
leading/trailing slashes, empty components, `.` and `..` components, and strings
longer than 4,096 (the existing `String.length()` limit). Backslashes, newlines,
tabs, DEL, Unicode, spaces and `%?#` remain literal filename characters. Paths are
never trimmed or normalized: source URLs percent-encode UTF-8 separately for each
slash-delimited component, while comments and GraphQL use the original JSON string.
Support covers filenames that JSON strings can represent losslessly. `valid_path`
retains its stricter static/local path rules, alongside static realpath, directory
boundary and symlink escape checks. The wire format remains RPC v2.

The backend removes upstream null fields, preserves decimal identifiers before
numeric conversion, decodes only modeled fields and rejects malformed modeled
values with `invalid_github_response`. The client rejects malformed responses or
unexpected result variants with `invalid_server_response`.

The frontend `internal/github_client` owns CSRF, request generations, auth
versions, session read sequencing, pending starts, cancellation and one shared
poll task. Poll delays and start retries are client scheduling parameters; they
are not sent as RPC arguments. Browser FFI only performs fetch/text reads,
AbortController cancellation and timers. The application calls cleanup on
`pagehide` and subscription unload, then restores status on reactivation.

## Verification

From the repository root:

```sh
moon check playground/protocol --target all --deny-warn
moon test playground/protocol --target all
moon test playground/frontend/internal/github_client --target js
moon -C playground/frontend test --target js
npm run test:server
npm run test:playground
npm run build
npm run test:artifacts
```
