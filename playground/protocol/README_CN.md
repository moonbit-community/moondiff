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
| `PullViewedGet` | `number` | `PullViewed(ApiPullViewed)` |
| `PullFileViewedSet` | `number`, `path`, `viewed`, `base_sha`, `head_sha` | `FileViewed(ApiFileViewedResult)` |
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

## Viewed 同步

两个 Viewed 操作均要求登录。`PullFileViewedSet` 属于写操作，复用 Origin/CSRF 校验。
PR 编号在协议中仍为十进制字符串，但必须落在 GraphQL 正 `Int` 范围内（1–2,147,483,647）。

`ApiPullViewed` 包含 `{base_sha, head_sha, files}`，每个文件为 `{path, state}`。
状态为 `{"$tag":"Viewed"}`、`{"$tag":"Unviewed"}` 或 `{"$tag":"Dismissed"}`；
Dismissed 表示查看后出现新修改。`ApiFileViewedResult` 包含 `{base_sha, head_sha, file}`。
写入使用当前文件路径（重命名时使用新路径）、布尔目标 `viewed` 和 PR 的 base/head SHA；
这里的 base SHA 不是 diff 使用的 merge base。

后端持有固定的 GraphQL 查询和 mutation，并自行解析 PR node ID。
每页读取 100 个文件，上限 3,000；重复游标、重复路径或不完整分页均报错。
读取期间逐页和结束后核对快照，写入前及 mutation 返回的 PR 中也核对快照，
变化时返回 `pull_snapshot_changed`（409）。GitHub 的
[Viewed mutation](https://docs.github.com/en/graphql/reference/pulls#markfileasviewed)
不支持条件 SHA，因此不能原子阻止并发 push；检测到变化后，页面停止标记，直到加载最新 diff。
HTTP 200 中的 GraphQL errors（包括部分成功响应）同样视为失败。

GitHub 持久化 Viewed 状态。单进程后端按 GitHub 用户 ID、仓库（不区分大小写）和 PR 编号，
将 Viewed 读写按 FIFO 顺序执行，包括来自不同会话的请求；不同范围独立运行。
写操作从快照预检、mutation 到结果校验始终占有队列位置，浏览器断开也不会提前释放。
上游超时仍然生效；排队等待失败时返回错误，不执行操作。空闲协调器会被清理。

前端按页面、账号、快照和请求序号隔离响应与重查定时器。发出 mutation 前，先将操作 ID、
GitHub 用户 ID、仓库、PR 编号、原始当前路径、目标状态及 base/head SHA 保存到 `sessionStorage`。
存储失败时不发送写入。记录不包含凭据、源码、评论或展开选择。确认完成或明确拒绝后，
只删除操作 ID 匹配的记录，防止迟到回调删除新操作。

超时、网络中断或请求被中断时进入待确认状态，只有读取到保存的目标状态才解除该文件的禁用。
旧值及读取失败均不代表写入被拒绝：页面继续显示 **Waiting for GitHub confirmation（等待 GitHub 确认）**，
保留乐观状态、展开选择和草稿。明确失败仍回滚 Viewed 状态；没有后续交互时也恢复原始展开状态。
待确认文件不能通过 **Retry Viewed** 重发 mutation，其他文件继续可操作；恢复过程从不自动重发写入。

立即确认读取后，按 2、4、8、16、30、30 秒自动重查，每轮最多一个读取在途。
次数耗尽后保留记录，提供 **Recheck Viewed（重新检查 Viewed）**。限流、身份失效及快照变化时暂停。
手动重查或页面恢复开启新一轮；快照变化须先 **Load latest**。登录及刷新恢复在身份和 PR 文件列表
就绪后按用户、仓库、PR、路径匹配记录，不依赖索引；切账号隔离记录。加载新快照仍保留未决操作，
但不恢复旧展开信息。此确认机制不新增后端状态、数据库迁移或 RPC 字段。

未决记录不因等待时间自动过期。当前标签页的会话存储覆盖页面刷新和登录恢复，但关闭标签页或
清除存储后可能丢失；不保证跨浏览器或设备协调。现有协议没有远端操作完成凭据，不确定操作
可能长期无法确认。读到目标值仅表示当前状态满足请求，不构成跨客户端操作顺序的保证。

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

`valid_repository_path` 用于源码读取、PR/commit 行内评论、Viewed 写入及 GitHub Viewed
列表返回的路径。它拒绝空路径、NUL、开头或结尾的斜杠、空组件、`.`、`..` 组件，以及超过
4,096 的字符串（沿用 `String.length()` 上限）。反斜杠、换行、制表符、DEL、Unicode、空格及
`%?#` 均作为文件名字符保留。路径不裁剪、不归一化：源码 URL 对每个以 `/` 分隔的组件分别
按 UTF-8 百分号编码，评论和 GraphQL 使用原始 JSON 字符串。支持范围为 JSON 字符串能够无损
表达的文件名。`valid_path` 保留较严格的静态/本地路径规则，静态资源的 realpath、目录边界及
符号链接逃逸检查保持不变。RPC 协议仍为 v2。

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
