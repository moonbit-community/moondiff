我的理解是：**他希望 playground 更像一个可以连续使用的工作区——页面切换少打断、点击后少等待、返回时能接着看。** “SPA？Prefetch 之类的”是在提示优化方向，具体方案还需要结合现有实现判断。

看过代码后，一个关键发现是：**项目已经有 SPA 的基础，但几个主要入口仍然采用新标签页打开，数据加载也有继续优化的空间。**

| 他提到的方向 | 解决什么问题 | 对 playground 的具体意义 |
|---|---|---|
| SPA（单页应用） | 在同一个页面内切换内容，减少重新启动应用的过程 | 首页 → PR → Commit → 比较区间可以连续浏览 |
| Prefetch（预取） | 用户点击之前，提前获取很可能需要的数据或资源 | 悬停某个 PR、准备打开文件时，后台先获取必要数据 |
| 配套的缓存与状态恢复 | 已经加载、操作过的内容能复用 | 返回列表保留位置，重看 diff 减少重复请求，保留筛选和展开状态 |

SPA 负责页面切换方式，Prefetch 负责把请求时间提前；两者可以配合，但 SPA 本身不会自动消除接口等待。[SPA 说明](https://developer.mozilla.org/en-US/docs/Glossary/SPA)、[Prefetch 说明](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/prefetch)。

当前实现中，有几处值得对照他的建议看：

- **前端路由已经存在。** 提交链接时会调用 `@nav.push_url`，并通过 `RouteChanged` 加载相应内容，可以沿着现有架构完善体验。[路由处理代码](playground/frontend/internal/application/reducer_ui.mbt#L253)
- **主要入口主动打开新标签页。** 首页 PR、Commit 链接使用 `target=Blank`；“View interval”也是如此。每次都会创建新的应用实例，当前页面中的内存状态和缓存无法直接复用。这很可能是他感到“不够像 SPA”的一个原因。[首页链接](playground/frontend/internal/view/home_view.mbt#L2)、[区间链接](playground/frontend/internal/view/range_panel.mbt#L189)
- **存在需要等待的请求链。** PR 详情先取元数据，再并行取比较结果和文件列表，校验版本一致性后才继续加载源码。预取有机会提前完成其中一部分，但具体收益需要实测。[加载流程](playground/frontend/internal/application/load_flow.mbt#L88)
- **已有部分缓存基础。** 静态资源已经配置哈希缓存；匿名读取也有针对完整 SHA 的数据缓存和重复请求合并。可以扩展这些机制。[静态资源策略](playground/README_CN.md#L197)、[数据缓存](playground/frontend/internal/github_client/public_requests.mbt#L314)

我建议把技术路线分成三个递进步骤：

1. **先打通连续导航。** 普通点击默认在当前标签页切换，保留 Ctrl/Cmd 点击另开标签页的习惯。同时做好前进、后退、列表滚动位置、筛选和展开状态恢复。未提交的评论草稿也需要明确的保存策略。
2. **再建立导航可复用的数据缓存。** 固定 SHA 的源码、比较结果适合复用；PR 状态、评论等可变数据需要过期和重新校验机制。登录用户的数据按身份隔离，切换账号时失效。
3. **最后加入有选择的预取。** 从悬停或键盘聚焦的 PR、下一步可能打开的文件开始，限制并发和数量，让预取结果与正式点击共享同一份缓存、同一个进行中的请求。

这里的 Prefetch，**更适合优先理解为“应用主动预取业务数据”**。项目登录后的读取走 `/api/rpc`，API 使用 `no-store`；单纯添加 `<link rel="prefetch">`，无法直接覆盖这条数据加载链路。[请求入口](playground/frontend/internal/github_client/github_client.mbt#L31)

预取范围尤其要克制：匿名 GitHub REST 请求按 IP 只有每小时 60 次额度，因此应优先预取用户有明确访问意图的内容。[GitHub 限额说明](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)

可以这样向老板回应：

> 目前前端已经具备 SPA 路由基础。我准备先把首页、PR 和比较区间串成连续导航，补齐返回时的状态恢复，再结合数据缓存做按用户意图触发的预取。效果主要看“点击到首个可读 diff 的时间”、返回页面的恢复速度，以及额外请求量。

以上是基于代码的分析；实际最耗时的是网络请求还是 diff 计算、渲染，还需要一次浏览器性能测量来确定。
