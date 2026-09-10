# Moondiff playground

[English](README.md) | 简体中文

## 本地开发

安装 Node.js 22 和 MoonBit 工具链。

在仓库根目录执行：

```sh
moon update
cd playground
npm ci
```

后续命令均在 `playground/` 目录中执行。

### 运行时配置

创建 `.env` 文件，写入以下内容。填写
[GitHub App 配置](#github-app-配置)，并使用下方命令生成需要持久保存的密钥，
替换密钥占位值。

```sh
# 启动前需将这些变量导出到环境中。服务端不会自动加载 .env。
# 除标记为“必填”的变量外，下方给出的值均为默认值。
# 相对路径以进程工作目录为基准（npm start 和 npm run dev 使用 playground/）；
# 也可以使用绝对路径。

# 后端 HTTP 服务监听的 IP 地址和 TCP 端口，不包含 URL 协议前缀。
# 127.0.0.1 仅接受本机回环连接。Docker 中默认为 0.0.0.0:4173
# （所有 IPv4 接口），以便通过发布的端口访问服务。
MOONDIFF_LISTEN=127.0.0.1:4173

# 浏览器访问服务时使用的源地址（协议、主机名和可选端口），用于校验登录、
# 退出登录和写操作请求的 Origin，并决定是否启用 Cookie 的 Secure 属性。
# 必须与浏览器的源地址完全一致，包括非默认端口；
# localhost 与 127.0.0.1 属于不同的源。不能包含子路径、查询参数或片段。
# 生产环境必须使用 HTTPS；仅 localhost、127.0.0.1 和 [::1] 可以使用 HTTP。
# 代理请求头不会覆盖此配置。
# 例如：https://diff.example.com 可以通过反向代理处理 HTTPS，
# 再将 HTTP 请求转发到 MOONDIFF_LISTEN=127.0.0.1:4173。
MOONDIFF_PUBLIC_URL=http://localhost:4173

# 后端提供的前端 HTML、JavaScript 等构建产物所在目录。
# 由 npm run build 创建，启动前必须存在。Docker 中默认为 /app/static。
MOONDIFF_STATIC_DIR=dist/static

# SQLite 文件，保存会话、加密的 GitHub 凭据和待完成的设备登录状态。
# 文件不存在时会自动创建；需提前创建父目录，并确保运行服务的用户有写入权限。
# 使用持久存储保存该文件，每个数据库只能由一个服务进程使用。
# Docker 中默认为 /var/lib/moondiff/moondiff.sqlite3。
MOONDIFF_DATABASE=moondiff.sqlite3

# 必填，本地开发也需要：对恰好 64 个随机字节进行 Base64 编码得到的密钥。
# 用于加密已保存的 GitHub 令牌和设备凭据，并校验其完整性。
# 只需生成一次：openssl rand -base64 64 | tr -d '\n'
# 妥善保密，单独备份，并始终为同一数据库使用相同的密钥。
# 使用不同密钥打开已有数据库会导致启动失败。密钥丢失或更换后，
# 需要使用全新的数据库，用户也需要重新登录。
MOONDIFF_TOKEN_KEY=replace-with-base64-encoded-64-random-bytes

# 必填，本地开发也需要：GitHub App 设置中的 Client ID。
# 用于发起和轮询设备授权，以及刷新用户访问令牌。
# 复制 Client ID 字段；数字形式的 App ID 是另一个标识符。
MOONDIFF_GITHUB_CLIENT_ID=replace-with-github-app-client-id

# 必填，本地开发也需要：与上述 Client ID 对应的同一个 App 的安装链接。
# playground 会展示此链接，方便用户授予 App 访问仓库的权限。
# 必须以 https://github.com/apps/ 开头。
MOONDIFF_GITHUB_INSTALL_URL=https://github.com/apps/your-app/installations/new
```

数据库备份与恢复方法见[会话与备份](#会话与备份)。

导出环境变量并启动服务：

```sh
# 开启自动导出，使后续新建或修改的 Shell 变量能被子进程继承。
set -a

# 在当前 Shell 中读取并执行 .env，将其中的配置导出为环境变量。
. ./.env

# 关闭自动导出；已导出的配置仍会传给随后启动的服务。
set +a

# 使用上述环境变量构建一次并启动服务，不监听文件变化。
npm run dev
```

打开 `http://localhost:4173`，或配置的 `MOONDIFF_PUBLIC_URL` 地址。该配置必须与浏览器的源地址一致。
`npm run dev` 会构建一次并启动服务，不会监听文件变化。
使用 `npm run build` 重新构建，使用 `npm start` 运行已有构建产物。

导出配置后，如需从源码运行后端，在仓库根目录执行
`moon -C playground/backend run main`。如需使用 Native 目标，
添加 `--target native --release`。

## GitHub App 配置

在 GitHub App 设置中启用 **Device Flow**（设备授权流程）。后端使用 Client ID
获取和刷新用户访问令牌，无需客户端密钥或网页授权回调。协议详情见 GitHub 的
[设备授权协议](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app#using-the-device-flow-to-generate-a-user-access-token-for-a-github-app)
和[令牌刷新协议](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/refreshing-user-access-tokens#refreshing-a-user-access-token-with-a-refresh-token)。

配置仓库权限：Contents 读写、Pull requests 读写，以及 GitHub 要求的 Metadata 权限。
Contents 写权限用于[删除提交评论](https://docs.github.com/en/rest/commits/comments#delete-a-commit-comment)；
Pull requests 写权限也用于
[PR 讨论区评论](https://docs.github.com/en/rest/issues/comments#create-an-issue-comment)。
App 权限发生变化后，已有安装需要接受新的权限。将 App 安装到用户需要审阅的仓库。
访问私有仓库和执行写操作还需要登录用户自身具有相应权限。
此流程不使用 App 私钥或安装访问令牌。

公开仓库支持匿名读取，但仍受 GitHub 请求频率限制。

登录时，playground 页面会显示验证码。复制验证码并打开 GitHub，
在新窗口中完成设备授权；playground 会自动更新登录状态。
刷新页面后会恢复尚未过期的验证码。开始新一轮登录前，先取消当前登录。

## 构建与部署

在仓库根目录构建发布产物：

```sh
moon update
npm --prefix playground ci
npm run build
```

`playground/dist/` 包含 `moondiff-server.wasm` 和 `static/`。
将两者复制到发布目录，并安装兼容的 `moonrun` 和受信任的 CA 证书。
导出[运行时配置](#运行时配置)中的环境变量后，在发布目录执行：

```sh
MOONDIFF_STATIC_DIR=/absolute/release/static moonrun ./moondiff-server.wasm
```

使用独立的域名或端口，将应用部署在 `/`；不支持部署到子路径。
`MOONDIFF_PUBLIC_URL` 必须与浏览器的源地址一致，后端不会从代理请求头推断该值。
后端监听器使用 HTTP，生产环境的 HTTPS 需由反向代理处理，可参考随附的
[Nginx 示例](deploy/nginx.conf.example)。使用专用的操作系统账户和私有的持久数据目录，
仅允许反向代理访问后端监听器。每个 SQLite 数据库只能由一个进程使用，升级期间也不例外。

## Docker

在仓库根目录构建，以便镜像能够访问所有 `moon.work` 成员：

```sh
docker build -f playground/Dockerfile -t moondiff-playground:local .
```

构建阶段会安装 Node.js 22 和最新的 MoonBit 工具链，与现有 CI 配置保持一致。
如需指定 MoonBit 版本，传入 `--build-arg MOONBIT_VERSION=<version>`，
版本值需使用 MoonBit 官方安装器支持的格式。运行时镜像包含 `moonrun`、受信任的 CA 证书、
Wasm 后端和静态资源，并以 UID/GID `10001:10001` 运行。

按照[运行时配置](#运行时配置)创建 `playground/.env`，填写 GitHub App 配置和持久保存的密钥，
然后在仓库根目录执行：

```sh
docker run --detach --name moondiff-playground \
  --restart unless-stopped \
  --publish 127.0.0.1:4173:4173 \
  --env-file playground/.env \
  --env MOONDIFF_LISTEN=0.0.0.0:4173 \
  --env MOONDIFF_STATIC_DIR=/app/static \
  --env MOONDIFF_DATABASE=/var/lib/moondiff/moondiff.sqlite3 \
  --mount type=volume,source=moondiff-data,target=/var/lib/moondiff \
  moondiff-playground:local
```

命令中显式指定的路径和监听地址会覆盖 `.env` 中用于本地开发的值。
Docker 会将该文件中的配置作为环境变量传入；该文件与本地数据库、依赖和构建产物一起被排除在构建上下文之外。
打开 `http://localhost:4173`。生产环境中，将 `MOONDIFF_PUBLIC_URL` 设置为对外提供服务的 HTTPS 源地址，
并按照[部署说明](#构建与部署)配置反向代理。

命名卷会在替换容器时保留 SQLite 数据。每个数据库只能供一个容器使用，
重启后也需保持 `MOONDIFF_TOKEN_KEY` 不变。如果改用绑定挂载，
请确保 UID/GID 为 `10001:10001` 的用户对挂载目录有写入权限。
镜像的健康检查会在配置的监听端口上请求 `/healthz`。

`playground-image` GitHub Actions 工作流会在每次拉取请求和推送到 `main` 时
构建 `linux/amd64` 镜像，并检查容器健康状态、静态资源、变更详情直达链接和认证状态接口。
在 `main` 上通过这些检查后，工作流使用具有 `packages: write` 权限的 `GITHUB_TOKEN`，
发布 `ghcr.io/<owner>/<repository>-playground:latest` 和 `:sha-<full-commit-sha>` 镜像。
也可以手动运行工作流；只有在 `main` 上运行时才会发布镜像。
如需使用已发布的镜像，将运行命令中的 `moondiff-playground:local` 替换为对应的 GHCR 镜像标签。

## 会话与备份

会话在 30 天后过期。退出登录会结束当前 playground 会话，
不会卸载 GitHub App，也不会撤销其他 GitHub 会话。

备份时需**同时保存数据库和原始加密密钥**，并将密钥单独存放在受保护的密钥存储中。
仅复制运行中的主数据库文件并不安全，尤其是已有的 WAL 数据库。
使用 SQLite 的在线备份命令，并将数据库路径调整为 `MOONDIFF_DATABASE` 配置的值：

```sh
sqlite3 /var/lib/moondiff/moondiff.sqlite3 '.backup /secure-backups/moondiff.sqlite3'
```

也可以先停止服务，执行
`sqlite3 /var/lib/moondiff/moondiff.sqlite3 'PRAGMA wal_checkpoint(TRUNCATE);'`
完成 WAL 检查点操作，再复制数据库并重启服务。恢复时，先停止服务，
恢复数据库及其对应的密钥，设置文件所有者和权限，再启动一个实例并检查 `/healthz`。
旧备份中的刷新令牌可能已被 GitHub 轮换，因此用户可能需要重新登录。
密钥丢失或主动更换后，需要使用全新的数据库并让用户重新登录；
当前版本不提供原地轮换密钥的命令。

## HTTP 接口约定

| 方法 / 路径 | 响应 / 用途 |
| --- | --- |
| `GET /api/auth/status` | `{$tag:"Success",value:{authenticated,user_id?,login?,install_url?,csrf_token,device_flow?}}`；建立匿名会话并恢复待完成的登录 |
| `POST /api/auth/device/start` | `{attempt_id}` 创建或复用会话中正在进行的授权；返回 `{request_id,status}` |
| `POST /api/auth/device/poll` | `{authorization_id}` 在到达轮询时间后推进授权；返回 `{request_id,status}` |
| `POST /api/auth/device/cancel` | `{authorization_id}` 取消授权并返回当前会话状态；返回 `{request_id,status}` |
| `POST /api/auth/logout` | 使会话失效并返回 `Success(value=null)`；要求提供 Origin 和 X-CSRF-Token |
| `POST /api/rpc` | `{v:2,request:GitHubRequest}` → `{$tag:"Success",value:RpcValue}` 或 `{$tag:"Failure",error:{status,code,message}}` |
| `GET /healthz` | 服务就绪时返回 `ok` |

三个设备授权 POST 接口都要求会话 Cookie、与配置一致的 Origin、
`X-CSRF-Token` 和 `Content-Type: application/json`；请求包含额外字段时会被拒绝。
发起登录时使用的标识符由浏览器生成，长度为 16–128 个字符，
可包含字母、数字、`-` 或 `_`，例如随机 UUID。
start、poll 和 cancel 都返回 `{$tag:"Success",value:{request_id,status}}`，其中 `request_id` 回传请求标识符。退出登录返回空成功值，客户端随后重新查询状态。

`device_flow` 包含 `id`、`phase`、`user_code`、`verification_uri`、
`expires_at`、`retry_after` 和 `message`。过期时间是以秒为单位的数字形式 Unix 时间戳，
重试延迟也是秒数。阶段包括 `Starting`、`Pending`、`Verifying`、`Completed`、
`Cancelled`、`Expired`、`Denied` 和 `Failed`。客户端使用服务端返回的实际授权 `id` 进行轮询；
复用已有授权时，它可能与新登录请求的 attempt ID 不同。
取消接口也接受最初的 attempt ID，因此在发起登录的响应尚未返回时也能取消。

浏览器只会收到用户验证码和允许列表中的验证 URL，设备凭据和 GitHub 令牌始终加密保存在服务端。
用户自行打开验证页面，playground 页面通过轮询获取结果，无需登录回调。
服务端的计时状态在页面刷新和服务重启后仍然保留，遵守 GitHub 的最小轮询间隔，
并在每次 `slow_down` 后至少增加 5 秒间隔。
临时网络故障、服务端错误或频率限制会保留当前授权，并按退避策略重试。
验证码被拒绝、无效或过期后需要重新发起登录。每次登录尝试最多持续 15 分钟。
旧的 `/auth/login` 和 `/auth/callback` 路径返回 404。

RPC 请求和返回类型统一定义在 [共享协议模块](protocol/README.md)，由前后端通过 `@protocol` 引用。
13 种请求由 `GitHubRequest` 枚举表达，成功结果由 `RpcValue` 枚举表达。
认证阶段、评论目标和评论侧别也采用显式标签枚举，例如 `{"$tag":"Pending"}`。
源码响应包含 `{base64,size,content_type}`；评论 ID 使用十进制字符串，确保 64 位精度不丢失。
请求先解码，再与重新编码的 JSON 比较，拒绝额外字段、小数截断和越界值，随后检查参数约束。
后端只发送已建模字段；无效上游数据返回 `invalid_github_response`，客户端收到错误结果种类时返回 `invalid_server_response`。
前后端须同步升级至 v2；不提供 v1 兼容层，SQLite 数据格式保持不变。

源码响应每侧最多 1 MiB，上游 JSON 响应最多 8 MiB，RPC 请求体最多 128 KiB，
评论最多读取 100 页，每页 100 条。
错误码会区分 `authentication_required`、`permission_denied`、`rate_limit`、
`not_found_or_not_installed`、`invalid_comment_anchor`、`source_too_large` 和 `pagination_limit`。
未知操作和额外参数会被拒绝。用户只能删除自己的评论。
写操作要求 Origin 与配置一致，并在 `X-CSRF-Token` 中携带会话 CSRF 令牌。

`GET`/`HEAD` 提供静态资源，并在 `/`、`/owner/repo/commit/sha`、
`/owner/repo/pull/number` 和 `/owner/repo/pull/number/commits/sha` 提供应用入口。
未知路径返回 404。旧的 `/#/…` 路由会在应用中显示链接无效错误，不会自动转换。

## 迁移与验证

1. 部署 Wasm 模块、兼容的 `moonrun`、静态目录、持久化数据库路径、密钥和 App 配置。
   验证 HTTPS、`/healthz` 和变更详情直达链接。
2. 构建轻量的跳转扩展，将 `MOONDIFF_PLAYGROUND_URL` 设置为该服务的源地址；
   详见[扩展说明](../extension/README.md)。
3. 扩展升级时会清除已有凭据。每个用户都需要重新登录，
   不会导入浏览器中的令牌或旧审阅页面状态。
4. Pages 发布工作流已移除。切换部署时，在 Settings → Pages 中关闭仓库旧的 GitHub Pages 站点，
   如有自定义域名配置，也需删除。仓库中的这项变更不会自动下线已部署的 Pages 站点。
   替换旧的 hash 分享链接。

切换前运行[检查与测试](#检查与测试)。生产环境的授权和安装流程还需使用实际 App 进行冒烟测试。

## 检查与测试

在 `playground/` 目录执行以下命令，从模块根目录检查并测试所有前端包
（包括 `internal/`），并运行后端检查：

```sh
moon -C frontend check --target js --deny-warn
moon -C frontend test --target js
moon -C backend check --deny-warn

# 测试辅助代码会设置 MOONDIFF_TEST_MODE=1，启用上游地址覆盖（默认关闭）。
# MOONDIFF_TEST_GITHUB_URL 替换 GitHub API 请求使用的 https://api.github.com。
# MOONDIFF_TEST_OAUTH_URL 替换设备授权和令牌请求使用的 https://github.com。
# 测试模式下必须提供这两个 URL，且它们和 MOONDIFF_PUBLIC_URL 都必须使用回环主机地址。
# 仅当 MOONDIFF_TEST_MODE=1 时才会使用这些上游地址覆盖配置。
# 常规开发和生产环境中，请勿设置上述三个测试变量。
npm run test:server
```

`test:server` 会运行 MoonBit 测试、后端集成测试和浏览器 HTTP 传输测试。
修改 MoonBit 代码后，运行 `moon fmt` 和 `moon info --target all`，
并检查生成的接口文件是否发生变化。

运行浏览器测试：

```sh
npx playwright install chromium
npm run test:e2e
```

如果缺少系统库，使用 `npx playwright install --with-deps chromium` 安装；
使用 `npm run test:e2e:ui` 启动交互式测试界面。测试会自行在 4173 端口启动 Wasm 服务，
因此请先停止本地开发服务。测试使用临时 SQLite 数据库和本地 GitHub/OAuth 模拟服务，
无需真实的 GitHub 凭据。前端回归测试会模拟同源 API。

验证跳转扩展和发布产物：

```sh
npm run test:extension
npm run build
npm --prefix .. run test:artifacts
```

也可以在仓库根目录依次运行 `npm run test:server`、`npm run test:playground`、
`npm run test:extension` 和 `npm run build && npm run test:artifacts`，执行上述测试套件和产物检查。
实现层面的测试用例见[回归测试覆盖范围](backend/INTERNAL_CN.md#回归测试)。

## 开发参考

- [前端包](frontend/)
- [后端认证、加密、存储和请求处理实现](backend/INTERNAL_CN.md)
- [跳转扩展开发](../extension/README.md)
