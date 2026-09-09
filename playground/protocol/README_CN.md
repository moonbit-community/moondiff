# Playground 协议 v2

[English](README.md) | 简体中文

`moonbit-community/moondiff-playground-protocol` 是独立的 workspace 模块，
前后端统一通过 `@protocol` 引用。它支持 JS、Wasm、Wasm GC 和 Native，
仅包含数据类型、JSON 编解码和纯校验辅助方法。
前后端必须同步升级。此版本不提供 v1 兼容层，SQLite 存储格式保持不变。

## 传输格式

所有 API 响应均使用 `Response[T]`：

```json
{"$tag":"Success","value":...}
{"$tag":"Failure","error":{"status":403,"code":"permission_denied","message":"No access"}}
```

所有枚举均显式派生 `FromJson(style="legacy")` 和 `ToJson(style="legacy")`。
位置参数使用 `"0"` 字段，命名枚举参数保留其标签。可选记录字段在没有值时省略。
评论 ID 使用正 `Int64` 值，并编码为十进制字符串，以保留超出 JavaScript 安全整数范围的值。

RPC 请求使用 `{"v":2,"request":GitHubRequest}` 格式。例如：

```json
{"v":2,"request":{"$tag":"CommitGet","0":{"owner":"alice","repo":"repo","sha":"123abcd","page":1}}}
```

该请求的成功响应包含类型明确的 `RpcValue` 数据：

```json
{"$tag":"Success","value":{"$tag":"Commit","0":{"sha":"123abcd","html_url":"https://github.com/alice/repo/commit/123abcd","commit":{"message":"Example"},"parents":[],"stats":{"additions":0,"deletions":0,"total":0},"files":[]}}}
```

| 请求 | 除 `owner`、`repo` 外的参数 | 结果变体 / 数据 |
| --- | --- | --- |
| `CommitGet` | `sha`、`page` | `Commit(ApiCommit)` |
| `PullGet` | `number` | `Pull(ApiPull)` |
| `CompareGet` | `base`、`head` | `Compare(ApiCompare)` |
| `PullFiles` | `number`、`page` | `Files(Array[ApiFile])` |
| `ContentGet` | `path`、`revision` | `Content(ApiSource)` |
| `CommentsList` | `target` | `Comments(ApiCommentBundle)` |
| `IssueCommentCreate` | `number`、`body` | `IssueComment(ApiIssueComment)` |
| `ReviewCommentCreate` | `number`、`commit_id`、`path`、`line`、`side`、`body` | `ReviewComment(ApiReviewComment)` |
| `CommitCommentCreate` | `sha`、`path`、`position`、`body` | `CommitComment(ApiCommitComment)` |
| `ReviewReplyCreate` | `number`、`comment_id`、`body` | `ReviewComment(ApiReviewComment)` |
| `IssueCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |
| `ReviewCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |
| `CommitCommentDelete` | `comment_id` | `Deleted(DeleteResult)` |

评论目标为 `Commit(sha~)`、`Pull(number~)` 或 `PullCommit(number~, sha~)`。
评论侧别为 `Left` 或 `Right`，分别编码为 `{"$tag":"Left"}` 或 `{"$tag":"Right"}`。
`ApiSource` 包含 `base64`、`size` 和 `content_type`；
`ApiSource::decode` 校验 Base64 编码，并检查解码后的字节长度。

## 认证接口

`GET /api/auth/status` 返回 `Response[ApiAuthStatus]`。状态包含
`authenticated`、`csrf_token`，以及可选的 `login`、`user_id`、`install_url` 和 `device_flow`。
设备授权流程包含 `id`、`phase`、`user_code`、`verification_uri`、
`expires_at`（以秒为单位的 Unix 时间戳）、`retry_after`（秒）和 `message`。
阶段为 `Starting`、`Pending`、`Verifying`、`Completed`、`Cancelled`、`Expired`、
`Denied` 或 `Failed`，采用相同的带标签枚举格式。

`POST /api/auth/device/start` 接收 `DeviceStart`（`{attempt_id}`）。
poll 和 cancel 接口接收 `DeviceAuthorization`（`{authorization_id}`）。
三个接口均返回 `Response[DeviceResponse]`，其中的值为 `{request_id,status}`。
`request_id` 回传提交的标识符；`status.device_flow.id` 表示实际授权 ID。
当 start 复用已有登录尝试时，实际授权 ID 可能与提交的标识符不同。
poll 响应中的这两个标识符都必须与请求匹配。

`POST /api/auth/logout` 返回 `Response[Unit]`，其中 `value:null`。
客户端随后重新查询状态，以建立匿名会话并获取新的 CSRF 令牌。

## 校验与调度

`decode_request` 先解码请求，再将重新编码的 JSON 与输入比较，最后检查语义约束。
这一过程会拒绝额外字段、缺失的必填字段、未知标签、整数位置的小数值和数值溢出。
仓库名、SHA 和相对路径均有约束；页码范围为 1–10,000，行号和位置为正 `Int`，
标识符为有符号 64 位正整数。评论不得仅包含空白，且 UTF-8 编码后的长度必须为 1–65,536 字节。
设备 ID 长度为 16–128 个字符，可包含字母、数字、`_` 或 `-`。

后端移除上游值为 null 的字段，在数值转换前保留十进制标识符，并只解码已建模字段。
已建模字段的值无效时，返回 `invalid_github_response`。
客户端收到格式错误的响应或非预期的结果变体时，返回 `invalid_server_response`。

前端 `internal/github_client` 管理 CSRF、请求代次、认证版本、会话读取序号、
待完成的登录发起请求、取消操作，以及唯一的共享轮询任务。
轮询延迟和登录发起重试属于客户端调度参数，不作为 RPC 参数发送。
浏览器 FFI 仅负责 fetch、响应文本读取、AbortController 取消和定时器。
应用在 `pagehide` 和订阅卸载时执行清理，并在重新激活时恢复状态。

## 验证

在仓库根目录执行：

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
