# Playground PR 合并状态区

## 摘要

- 在 PR 主页面的评论区域正下方增加独立状态卡片，样式参考 [GitHub PR #11](https://github.com/moonbit-community/liquid-moonbit/pull/11)：边框卡片、状态图标、CI 汇总与明细、绿色主操作按钮，并适配暗色和窄屏。
- 展示当前 PR 与 base 的冲突状态；存在冲突时，DOM 中完全不渲染 `Rebase and merge` 按钮。
- 合并采用用户选定的单击即执行模式，不增加二次确认。

## 实现改动

### 协议与后端

- 在现有 RPC v2 中添加：
  - `PullMergeStatusGet(owner, repo, number, expected_base_sha, expected_head_sha)`
  - `PullRebaseMerge(owner, repo, number, expected_base_sha, expected_head_sha)`，标记为写请求并沿用 Origin/CSRF 校验。
  - `ApiPullMergeStatus`：当前 base/head、open/draft/merged 状态、可空的 `mergeable`/`rebaseable`、GitHub merge state、CI 汇总、标准化 CI 明细及来源警告。
  - `ApiPullMergeResult`：`merged`、提交 SHA 和提示信息。
- 状态查询要求用户已登录，先确认 PR 快照仍与页面一致，再针对该 head 聚合 [Check Runs](https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#list-check-runs-for-a-git-reference) 和 [Commit Statuses](https://docs.github.com/en/rest/commits/statuses?apiVersion=2022-11-28#get-the-combined-status-for-a-specific-reference)。统一为成功、进行中、失败、中性四类；汇总优先级为失败 > 进行中 > 成功，空结果显示“未报告 CI 检查”。
- 两类 CI 来源独立处理：任一来源不可读取时保留另一来源并明确提示“不完整”，不得静默显示为全部通过。
- 合并前重新校验 PR 未关闭、未合并、非 draft、base/head 未变化且不存在冲突；随后调用 GitHub [Merge a pull request](https://docs.github.com/en/rest/pulls/pulls?apiVersion=2022-11-28#merge-a-pull-request)，固定发送 `merge_method: "rebase"` 和预期 head SHA。
- 为合并操作单独映射快照过期、冲突、保护规则阻止、权限不足、限流及上游失败，避免沿用现有评论接口的 422 错误语义。
- 更新 Playground 的 GitHub App 配置文档，加入 Checks read 和 Commit statuses read 权限；已有安装需要重新授权。协议生成接口随之刷新，版本号保持 v2。

### 前端状态与交互

- 在 `Discussion` 后、文件列表前新增独立 `PullMergeStatus` 渲染区域；状态轮询只能刷新该区域，不得重建评论编辑器或文件 diff。
- 卡片包含：
  - CI 汇总及逐项明细、描述和外部 Details 链接。
  - 与 base 无冲突、正在计算、存在冲突、快照过期、规则阻止、已合并等明确状态。
  - 手动 Refresh 操作。
- 按钮规则：
  - `mergeable == false` 或 `rebaseable == false`：显示冲突说明，完全隐藏合并按钮。
  - 任一字段仍为未知：显示检查中，不显示合并按钮。
  - 快照过期、draft、closed、merged：不显示合并操作，并提供对应说明；快照过期提供现有 “Load latest” 操作。
  - GitHub 明确报告 `blocked`：显示禁用按钮及原因；CI 失败本身不额外硬编码阻止，最终以 GitHub 保护规则为准。
  - 状态可合并、快照最新且已登录：显示绿色 `Rebase and merge` 按钮；未登录时显示登录提示。
- 单击后立即提交，按钮变为 `Rebasing and merging…` 并防止重复请求。成功后切换为已合并状态；失败保留卡片并显示可重试错误。
- 对未知可合并性或进行中的 CI，沿用现有延迟机制按 2、4、8、16、30、30 秒进行有界刷新；路由切换时取消，页面重新激活时刷新，超过次数后依靠手动 Refresh。
- 使用文字加图标表达状态并添加 `aria-live`，不只依赖颜色区分。

## 测试计划

- 协议测试：新请求/响应往返、严格字段校验、SHA/PR 编号校验及读写分类。
- 后端测试：两类 CI 聚合与分页、部分来源失败、未知/无冲突/冲突状态、前后端快照不一致，以及合并请求的 URL、`rebase` 方法和 SHA；覆盖 401、403、405、409、422 和 `merged: false`。
- reducer/渲染测试：过期响应被忽略、轮询终止、状态汇总优先级、更新状态区不会使评论或文件区域失效。
- 浏览器测试：成功 CI、进行中/失败 CI、无 CI、冲突时不存在按钮、未登录提示、快照过期、单击合并成功、重复点击保护和失败重试。
- 完成后运行各 Playground MoonBit 模块检查与测试、`moon test --target all`，以及 `npm run test:playground`。

## 默认范围

- 仅在带评论区的 PR 根页面显示；commit 页面及普通 compare 页面不显示。
- 不实现 squash、merge commit、自动合并或 update branch。
- `behind` 本身不阻止 rebase 合并；若仓库保护规则要求先更新，由 GitHub 的 blocked 状态或最终合并响应决定。
