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
