# Moondiff Review 即时响应优化验收

基线为 `bf9b82b`，对比本次工作区实现。原始样本保存在
[response-performance.json](benchmarks/response-performance.json)，测试入口为
[responsiveness.stress.mjs](frontend/tests/responsiveness.stress.mjs)。

使用 Chromium、两个 MoonBit 文件、每文件 24 个声明，交替执行两个版本各八轮。
固定延迟模型为浏览器往返 25 ms、每个上游阶段 25 ms；聚合请求包含 metadata、
并行比较／文件、独立复核三个上游阶段。重复访问前将时钟推进五分钟；历史恢复使用
真实 SPA 历史记录。可读延迟在首个 diff 表格出现并完成两帧后计时，统计请求量和响应量
时等待 RPC 结束。响应字节为统计窗口内收到的 UTF-8 RPC 正文，不包含 HTTP 头。
这些数据用于回归对照，线上延迟仍取决于实际网络和 PR 规模。

| 场景 | 基线 P50 / P95（ms） | 优化后 P50 / P95（ms） | P50 缩短 | 浏览器 RPC 数 | 平均响应字节 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 冷访问 | 559.5 / 625.2 | 463.3 / 503.4 | 17.2% | 13 → 10 | 10696 → 10325.5 |
| 五分钟后重复访问 | 373.1 / 413.5 | 101.7 / 145.6 | 72.7% | 9 → 6 | 6368 → 1886 |
| 历史恢复 | 94.1 / 140.0 | 87.8 / 109.8 | 6.7% | 6 → 6 | 1886 → 1886 |

三次访问后的累计快照缓存命中率为 33.3% → 66.7%。优化后的重复访问和历史恢复
不再增加缓存文件的 diff／高亮计算次数。冷访问使用一次 `PullSnapshotGet`，没有额外的
浏览器 `CompareGet`／`PullFiles` 快照阶段；上表 RPC 总数也包含评论、Viewed 和合并状态。

实现与边界说明见[加载链路文档](frontend/internal/github_client/README.md)。
前后端需要同步部署，SQLite 格式保持不变。

验证覆盖：

- 前端 MoonBit 测试与零警告检查；共享协议 JS／Native／Wasm／Wasm GC 测试。
- 后端 Native／Wasm 检查和测试；服务测试覆盖会话、认证代次、300 文件／8 MiB 上限及一次漂移重建。
- Playwright 全量回归及 Viewed、手动加载、导航、预取专项复测；31 秒／五分钟恢复时阻塞 metadata，已缓存 diff 仍可见且计算次数不变。
- 悬停／键盘焦点提升、源请求并发上限、草稿及写入竞态、缓存淘汰与 DOM 回收。
- 渲染压力测试包含真实 parser fixture、大小合成 fixture、1×／6× CPU 和 CI 折叠交互。

复现性能对比：先将基线放入单独的工作目录，共用已安装的 `.mooncakes` 依赖，并构建
基线的 release JS。然后在当前仓库运行：

```sh
moon -C /tmp/moondiff-response-baseline build review-web/frontend/main --target js --release
cd review-web
MOONDIFF_BASELINE_JS=/tmp/moondiff-response-baseline/_build/js/release/build/moonbit-community/moondiff-review-web/main/main.js \
  ./node_modules/.bin/playwright test --config playwright.stress.config.mjs responsiveness.stress.mjs
```

报告写入该用例输出目录中的 `response-performance.json`，包含每轮延迟、请求、字节、
命中率及各文件的计算计数。没有提供 `MOONDIFF_BASELINE_JS` 时只测当前实现。
