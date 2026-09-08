# 为什么插件可以将评论同步到 GitHub，而静态 playground 当前做不到

核心原因是：插件提供了“授权、保存凭证、带凭证调用 GitHub”的后台能力，而当前静态 playground 明确只实现匿名只读模式。静态网页并非天然不能发评论。

## 1. 插件里的“同步”，实际是直接调用 GitHub 评论 API

调用链如下：

```text
评论界面
  → __MOONDIFF_EXTENSION_HOST__.request(...)
  → chrome.runtime.sendMessage(...)
  → 扩展 Service Worker
  → 带 Authorization: Bearer token 的 GitHub API 请求
```

[review-bootstrap.js](extension/src/review-bootstrap.js) 注入通信桥接；[service-worker.js](extension/src/service-worker.js) 自动添加 token，并实际执行评论的 `POST` 请求，包括 PR 普通评论、行级评论、commit 评论和回复。

因此评论直接存到了 GitHub，并不是两套评论数据库之间的同步。

## 2. 插件可以独立完成授权流程

当前采用 GitHub App Device Flow：获取设备码 → 用户到 GitHub 授权 → 后台轮询取得 token。这条流程无需在插件中放置 client secret。access token 存在扩展的 session storage，refresh token 存在扩展的 local storage，由后台管理。

插件还在 [manifest 生成代码](extension/scripts/build.mjs) 中声明了 GitHub API 和 OAuth 地址的 `host_permissions`。Chrome 允许具有相应权限的扩展后台发起跨域请求，普通网页没有这项扩展权限。参见 [Chrome 官方说明](https://developer.chrome.com/docs/extensions/develop/concepts/network-requests)。

## 3. 静态版在代码中直接关闭了评论能力

[comments.mbt](playground/internal/comments/comments.mbt) 的 `initial_review_state` 明确区分运行环境：

| 运行环境 | 初始认证状态 | 初始评论状态 |
|---|---|---|
| 有扩展 host | `AuthChecking` | `CommentsLoading` |
| 普通网页 | `WebReadOnly` | `CommentsDisabled` |

而且评论请求只有扩展 RPC 实现，没有普通浏览器请求的备用路径。缺少 host 时，[extension_rpc.mbt](playground/internal/github_client/extension_rpc.mbt) 直接返回：

> Commenting is only available in the Moondiff extension.

静态版现有的 [GitHub 请求](playground/internal/github_client/github_client.mbt) 则只是匿名 `GET`，没有 token 输入、登录或评论写入路径。因此单纯开放评论按钮也无法工作。

## 4. 真正需要区分的是“获取 token”和“使用 token 发评论”

GitHub REST API 支持跨域请求，明确允许 `Authorization` 请求头和 `POST` 等方法。如果静态网页已经拿到具有对应权限的 token，技术上可以直接发评论。不能笼统地说“因为 CORS，静态页面无法写 GitHub”。参见 [GitHub CORS 文档](https://docs.github.com/en/rest/using-the-rest-api/using-cors-and-jsonp-to-make-cross-origin-requests)。

授权是另一层：OAuth 登录端点不能直接套用 REST API 的 CORS 支持；当前扩展有跨域权限，而普通网页不能原样照搬这条后台流程。对于当前使用的 GitHub App，官方网页授权流程的 code 换 token 步骤还要求 `client_secret`，它不能放入公开的静态资源。参见 [GitHub 授权文档](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)。

## 5. 为什么网页授权需要服务端，而 Cookie 不能替代它

纯静态网页可以通过持久 Cookie 或 localStorage 保存状态，下次打开时也可以读取已经保存的 token。因此，“持久登录必须有自己的后端”并不准确。当前 GitHub App 网页流程需要服务端的关键，是授权兑换时必须使用应用密钥，而不是浏览器缺少持久化能力。

### 5.1 点击登录与用户授权：静态页面可以完成

用户点击“使用 GitHub 登录”后，页面跳转到 GitHub 授权地址，携带公开的应用标识 `client_id`、回调地址 `redirect_uri` 和用于核对本次请求的随机值 `state`。

GitHub 使用自己的登录 Cookie 识别用户，再由用户决定是否授权 Moondiff。“已经登录 GitHub”只说明 GitHub 知道用户是谁，不代表 Moondiff 已获准代表用户操作。Moondiff 页面也不能读取 GitHub 域的登录 Cookie，或把自己设置的 Cookie 当成 GitHub API 凭证。

用户同意后，GitHub 将浏览器重定向到回调地址，例如：

```text
https://moondiff.example/auth/callback?code=ABC&state=XYZ
```

接收方核对 `state`，确认回调对应之前发起的登录。静态页面可以接收回调并读取参数，但得到的 `code` 是用于兑换凭证的授权码，还不是能发表评论的 `access_token`。

### 5.2 授权码换取 token：应用密钥需要留在服务端

当前 GitHub App 网页流程要求向下面的端点提交兑换请求，核心参数如下：

```text
POST https://github.com/login/oauth/access_token

client_id     = 应用标识
client_secret = 应用密钥
code          = 回调收到的授权码
```

这些值的作用不同：

| 值 | 作用 | 保密要求 |
|---|---|---|
| `client_id` | 标识 Moondiff 应用 | 可以公开 |
| `client_secret` | 在兑换请求中验证应用身份 | 应用级秘密，不能分发给浏览器 |
| `code` | 对应本次用户授权，用来兑换 token | 需要保护 |
| `access_token` | 代表用户调用 GitHub API | 用户授权凭证，需要保护 |

GitHub 官方文档将这里的 `client_secret` 列为必填；当前即使使用 PKCE，也没有取消这项要求。参见 [GitHub 网页授权与兑换参数](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app)。

如果让静态页面直接完成兑换，就必须把应用密钥交给浏览器。无论密钥写在 JavaScript 中、构建时从环境变量注入，还是放进 Cookie 或 localStorage，用户都可以检查最终产物或浏览器中的数据。加密后交给前端解密也无法解决，因为前端必须具备解密能力。HTTPS 能保护传输过程，不能向接收代码的用户隐藏密钥。

因此，授权服务端将 `client_secret` 留在自己的运行环境中，接收授权码后向 GitHub 兑换 token，浏览器不接触应用密钥。即使暂不考虑 OAuth 端点的跨域限制，这项保密要求也足以说明当前网页流程为什么需要服务端。

### 5.3 为什么不能把 client_secret 存进用户 Cookie

`client_secret` 是 Moondiff 的应用级密钥，不是某个用户独有的登录凭证。把它放入每个用户的 Cookie，相当于把整个应用的秘密分发给所有访问者。

**任何用户都能提取密钥。** 用户可以通过浏览器开发者工具或本地调试工具检查自己的 Cookie，不需要攻击网站。Cookie 的安全属性也无法向浏览器所有者隐藏内容：

| 属性 | 能保护什么 | 不能保护什么 |
|---|---|---|
| `Secure` | 限制 Cookie 通过 HTTPS 发送 | 无法向浏览器所有者隐藏内容 |
| `HttpOnly` | 阻止网页 JavaScript 读取 Cookie | 无法阻止浏览器所有者检查 Cookie |
| `SameSite` | 限制部分跨站请求携带 Cookie | 无法让应用密钥在用户设备上保密 |

如果目标是让静态页面的 JavaScript 读取密钥并兑换 token，设置 `HttpOnly` 后，这段 JavaScript 自己也读不到它。

**提取出的密钥可以在其他程序中使用。** 攻击者可以将密钥复制到自己的脚本或服务器，在需要应用密钥的请求中以 Moondiff 应用的身份进行认证。密钥本身不会绑定在原来的 Cookie 或浏览器上。

这不意味着仅凭 `client_secret` 就能立刻获得所有用户的 GitHub 权限。兑换用户 token 仍需要有效的授权码，刷新仍需要对应的 refresh token，并受其他协议校验约束。参见 [GitHub 兑换参数](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app) 和 [刷新参数](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)。

泄漏的实际后果是：原本只有 Moondiff 服务端才能提供的应用密钥，现在任何人都能提供。如果其他用户的授权码或 refresh token 又因其他漏洞泄漏，应用密钥就不能再提供这层保护。

**泄漏的处理范围是整个应用。** 用户 token 泄漏通常涉及该用户及其授权范围；应用密钥泄漏则需要撤销该密钥、部署新密钥，并更新所有依赖它的授权兑换和刷新流程。若继续把新密钥放入用户 Cookie，新密钥仍然会被提取。也不能把撤销应用密钥当作自动撤销全部既有用户 token 的替代措施。

浏览器可以保存用户自己的会话凭证，例如随机的 `session_id`，由服务端将其关联到该用户的 GitHub 凭证；应用级 `client_secret` 则只保存在服务端。用户能够查看自己的会话标识，是这套设计预期的一部分；用户能够查看整个应用的密钥，则破坏了应用密钥应有的保密边界。会话凭证本身也需要防止泄漏给其他人。

### 5.4 兑换完成后，Cookie 才负责维持会话

一种可采用的设计是由服务端保管 GitHub 凭证，浏览器只保存会话标识：

```text
服务端保存：会话 S → 用户身份、GitHub token、过期时间
浏览器保存：持久 Cookie，session_id=S
```

用户再次访问时，浏览器向服务端发送会话 Cookie，服务端找到对应的用户和凭证，前端便可以恢复登录状态。发表评论时，服务端再携带 GitHub token 调用 API。

这里 Cookie 保存的是已经完成授权之后的会话凭证，不能代替之前的授权兑换。单独保存 `logged_in=true` 只能改变界面显示，不能让 GitHub 接受请求。

这是一种实现选择，并非要求所有请求都经过服务端。授权服务也可以把 access token 交给前端，由前端直接调用 GitHub REST API；具体选择取决于凭证保管方式。若用户手动提供 token，纯静态页面也可以保存并复用它，只要 token 仍然有效且具有所需权限。

### 5.5 持续登录还涉及 token 刷新

如果 GitHub App 启用了 token 过期机制，access token 在 8 小时后过期，refresh token 的有效期为 6 个月。刷新会生成新的 access token 和 refresh token，旧凭证随之失效。对于网页授权流程获得的 token，刷新请求仍然要求 `client_secret`，所以也需要服务端处理。如果 refresh token 已过期，则需要重新授权。参见 [GitHub 刷新凭证文档](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)。

Cookie 的保存期限与 GitHub 凭证的有效期彼此独立。把 Cookie 设置成一年后过期，并不能让其中的 token 使用一年。持久保存、凭证刷新和授权失效后的重新登录是不同环节。

### 5.6 为什么插件可以不依赖自建授权服务

插件采用另一条路线：Device Flow 通过设备码让用户授权，再轮询取得 token，不要求应用密钥。通过 Device Flow 获得的 token 在刷新时也免于提供 `client_secret`。参见 [GitHub Device Flow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app) 和 [刷新规则中的例外](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens)。

结合第 2 节提到的扩展后台跨域权限，插件可以自行完成这条授权路径。普通静态网页不具备这些扩展权限，不能直接照搬实现。

因此，需要服务端的结论应限定在当前 GitHub App 的网页授权流程。这个服务端可以只是一个小型 serverless 授权服务，不要求将整个 playground 改成动态网站。

## 6. 让 playground 支持评论的实际方向

- **保持纯静态**：让用户提供自己的 token，补上浏览器端评论 API 实现；代价是用户需要手动管理凭证。
- **提供完整 GitHub 登录体验**：增加一个小型后端或 serverless 授权服务，负责授权交换和凭证管理，前端仍然可以静态部署。

现有评论 UI、行号定位和请求参数构造基本可以复用，主要缺的是网页环境下的认证与请求适配层。
