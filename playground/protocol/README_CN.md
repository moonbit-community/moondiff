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
| `ViewerPullsGet` | `kind`、可选 `cursor`；无需 `owner`、`repo` | `ViewerPulls(ApiViewerPulls)` |
| `PullCommitsGet` | `number`、可选 `cursor` | `PullCommits(ApiPullCommits)` |
| `PullViewedGet` | `number` | `PullViewed(ApiPullViewed)` |
| `PullFileViewedSet` | `number`, `path`, `viewed`, `base_sha`, `head_sha` | `FileViewed(ApiFileViewedResult)` |
| `PullMergeStatusGet` | `number`、`expected_base_sha`、`expected_head_sha` | `PullMergeStatus(ApiPullMergeStatus)` |
| `PullRebaseMerge` | `number`、`expected_base_sha`、`expected_head_sha` | `PullMergeResult(ApiPullMergeResult)` |
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

## 登录后首页

`ViewerPullsGet` 接收 `kind: {"$tag":"ReviewRequested"}` 或
`kind: {"$tag":"Authored"}`，以及可选 `cursor`，不接收仓库、用户名或搜索表达式。
后端使用当前会话，固定搜索 `is:pr is:open`，分别附加
`user-review-requested:@me` 或 `author:@me`，按更新时间倒序，每页最多 50 条。
范围为 GitHub App 授权可读取的仓库；仅团队请求 Review 不包含在内，本人草稿包含在内。

`ApiViewerPulls` 包含 `items`、`total_count`、可选 `next_cursor` 和 `incomplete`。
PR 摘要为 `owner`、`repo`、`number`、`title`、`author`、`updated_at`、`draft`。
原始搜索窗口首次返回完整响应（`incomplete_results=false`）前，总数为暂定值，
重试该窗口时可以更新。首次完整响应确认本次遍历的初始总数，后续页和拆分后的子窗口
均沿用该总数，即使分页期间 GitHub 搜索索引发生变化。超过 1,000 条时拆分互不重叠的
更新时间窗口，保留边界秒内的全部结果。同一秒超过限制、上游返回不完整结果，或当前请求
达到窗口探索次数上限时，以 `incomplete` 明确提示，并提供继续或重试该窗口的游标。
游标经过认证并绑定会话、认证代次与操作；刷新从头查询，已加载行在分页失败时保留。
缺少总数确认标志的旧 PR 搜索游标返回 `invalid_cursor`（400），触发下文的列表恢复逻辑。

`PullCommitsGet(owner, repo, number, cursor?)` 在提交数不超过 250 条时使用 PR 的
GraphQL `commits` connection；超过时从第一页开始使用分页的
[REST compare](https://docs.github.com/en/rest/commits/commits#compare-two-commits)，
在 PR 所属的 base 仓库中按快照的完整 base/head SHA 查询，支持 fork PR。
整个分页过程使用同一种数据源，每页 100 条，保持该来源的 GitHub 顺序。
`ApiPullCommits` 包含 `items`、
`total_count`、可选 `next_cursor`、`base_sha`、`head_sha`；commit 摘要仅包含
`sha`、`message`（消息首行）、`author`（登录名或姓名）、`committed_at`（提交者时间），
不含文件 diff。游标绑定仓库、PR、快照、数据源和分页位置；旧提交游标格式返回
`invalid_cursor`（400）。每页读取前后核对 base/head 和提交总数；compare 总数、页长度或
累计数量不一致时拒绝响应，沿用现有上游超时和响应大小限制。base/head 或总数
变化返回 `pull_commits_changed`（409），前端从第一页重新获取该提交列表；刷新期间
保留旧提交，直到替换内容准备就绪。反复变化时保留手动重试。GraphQL 部分成功响应也
视为失败。两个新操作均要求登录且为只读。

任一 PR 列表或提交列表的带游标请求收到 `invalid_cursor` 时，从第一页重新获取该列表。
刷新期间只重置暂存页，旧条目和总数继续显示；普通分页则清空受影响列表的条目、总数和
游标。提交列表同时清除旧快照和重启计数，保留展开状态；折叠中的
列表等待再次展开后加载。其他列表与缓存保持可用。第一页本身仍返回 `invalid_cursor` 时，
显示错误和 **Retry**，不自动循环；Retry 从第一页开始。这也适用于在另一标签页退出并
重登同一账号后失效的游标。身份、导航和请求代次校验继续丢弃迟到响应。

首页各组和各 PR 的加载、错误状态独立。内存缓存支持历史导航和页面恢复。刷新时两组
从第一页分别重新获取，达到原先已展示的深度后才替换旧条目；展开的提交列表也会重新校验。
刷新失败时保留可用内容并允许重试。退出、切换账号或会话过期时立即清空缓存。无数据库迁移，
使用现有合并构建同步部署前后端。
## 合并状态与 rebase 合并

`PullMergeStatusGet` 要求当前会话已登录，读取 PR 当前状态，并要求 base/head SHA 与页面展示的快照一致。
返回值包含 open、draft、merged、GitHub 的可选 `mergeable` 与 `rebaseable`、
`mergeable_state`，以及固定 head commit 的 CI 详情。快照不一致时返回
`pull_snapshot_changed`（409）。

CI 会聚合分页的 Check Runs 与 combined Commit Statuses。每项包含名称、归一化状态
（`Success`、`Pending`、`Failure` 或 `Neutral`）、描述、可选的 HTTP(S) 详情链接和来源。
汇总优先级依次为 Failure、Pending、Success、Neutral；没有检查时不返回汇总状态。
两个来源独立容错：一个来源读取失败时仍返回另一来源的数据，并在 `ci_warnings` 中明确提示。
每个来源最多读取 100 页，每页 100 项。

`PullRebaseMerge` 是要求登录的写操作，复用其他 mutation 的 Origin/CSRF 校验。
后端重新读取 PR，拒绝快照变化、已关闭、已合并、草稿，以及未知或为假的可合并状态；
随后以预期 head SHA 和 `merge_method: "rebase"` 调用 GitHub 合并接口。
类型化结果包含 `merged`、可选合并 commit `sha` 和 `message`。稳定错误码会区分
身份过期、权限不足、仓库规则阻止、冲突、快照变化、合并被拒、限流及上游故障。
前端绝不会自动提交合并；仅在状态未定时按 2、4、8、16、30、30 秒轮询，并在页面恢复时刷新。

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
`authenticated`，以及可选的 `csrf_token`、`login`、`user_id`、`install_url` 和 `device_flow`。
无有效会话时只返回匿名状态，不包含 `csrf_token`，也不创建会话或设置 Cookie。
开始登录时，浏览器以空 JSON 对象 `{}` 和与配置精确匹配的 Origin 请求
`POST /api/auth/session`。该接口创建或复用登录会话，并返回状态和 CSRF 令牌。
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
客户端随后重新查询状态以确认匿名状态；该读取不会创建会话或 CSRF 令牌。

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
