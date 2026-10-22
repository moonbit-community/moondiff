**Rabbita 复选框在同步失败回滚后与模型状态不一致的问题记录**

首次记录：2026-09-11，当时使用 `moonbit-community/rabbita@0.14.2`。最近复核：2026-10-16，当前 [`moon.mod`](moon.mod) 声明且本地安装的版本为 `moonbit-community/rabbita@0.16.5`。前端编译目标为 JavaScript，本次浏览器验证使用 Chromium。

本记录整理 Viewed 功能实现过程中遇到的一个问题：浏览器已经切换了 checkbox 的实际 `checked` 属性，但应用的乐观更新与失败回滚发生在下一次 DOM 更新之前，最终可能出现“模型已经回滚，复选框仍显示操作后的状态”。该现象在 Rabbita `0.16.5` 的独立复现中仍然存在；当前 Moondiff Review 通过等待对应文件区域完成渲染后再执行存储来规避，本次存储失败回归通过。

目前已完成脱离 moondiff 业务逻辑的独立复现，覆盖双向切换及四种输入方式，但尚未确认 Rabbita 对这类受控表单行为的完整 API 契约。应区分“已证实的模型与 DOM 不一致现象”和“上游是否将其定义为框架缺陷”。本次未向上游提交 issue，也未修改 Rabbita 源码。

**触发背景**

Viewed 复选框由应用模型提供 `checked` 值。用户切换后，应用先乐观修改文件状态和展开状态，再把待确认操作写入 `sessionStorage`；只有存储成功，才发送 GitHub Viewed mutation。这样即使页面刷新，也能恢复尚未确认的操作。

存储写入可能同步失败，例如浏览器抛出 `QuotaExceededError`。这属于发送请求之前的明确失败，正确处理应当是：显示存储错误、恢复操作前的 Viewed 状态及应恢复的展开状态，并且不发送 mutation。这里的回滚与“请求超时后结果未知，只能读取确认”的处理不同。

问题出现在最初使用默认执行时机的 `@cmd.custom_cmd(...)` 执行存储时。存储调用及失败结果消息都可以在下一次 DOM 更新前完成，使一次乐观切换和一次回滚被合并到同一次渲染中。

**实际观察到的现象**

存储失败的浏览器回归从一个已勾选的 Viewed 文件开始，尝试取消勾选，并让对应的 `sessionStorage.setItem` 同步抛出异常。应用显示了存储错误，mutation 数量为零，但在加入当前规避方式之前，复选框可能仍处于未勾选状态，而应用已经恢复为 Viewed。

这会让用户看到一个与应用状态不符的选择结果。仅断言错误提示、请求数量或 reducer 返回值，无法发现这个问题；需要读取实际 DOM 的 `checked` 属性。

以取消勾选失败为例，可以用下面的时序解释状态为何分离。表中的虚拟状态指渲染器用于和新视图比较的上一次已提交状态，DOM 状态指 `input.checked`。

| 阶段 | 应用模型 | 上一次已提交的虚拟状态 | 实际 DOM |
| --- | --- | --- | --- |
| 操作前 | Viewed / `true` | `true` | `true` |
| checkbox 原生点击切换后，应用处理前 | `true` | `true` | `false` |
| 应用乐观取消 Viewed | `false` | `true` | `false` |
| 存储同步失败，应用立即回滚 | `true` | `true` | `false` |
| 下一次渲染评估时，模型已恢复旧值 | `true` | `true` | 若复用旧视图，或属性比较相等而不重新写入，仍为 `false` |

这里“模型最终恢复到旧值”并不意味着“DOM 仍然等于旧值”：浏览器已经在应用之外修改了复选框。2026-10-16 的独立复现已经确认，初始已勾选和初始未勾选两种方向均可出现该现象，具体范围见后面的验证矩阵。

**从当前依赖源码能够确认的部分**

本次核对了仓库中安装的 Rabbita `0.16.5` 源码。下列依赖链接相对于本文件指向仓库根目录的 `.mooncakes`，需要先安装项目依赖：

- [`html/html_utils.mbt`](../../.mooncakes/moonbit-community/rabbita/html/html_utils.mbt) 的 `push_checked` 和 [`html/attrs.mbt`](../../.mooncakes/moonbit-community/rabbita/html/attrs.mbt) 的 `Attrs::checked` 都把 `checked` 放入 DOM property 集合，而不是仅设置 HTML attribute。
- [`cmd/commands.mbt`](../../.mooncakes/moonbit-community/rabbita/cmd/commands.mbt) 中，`custom_cmd` 默认使用 `Immediately`；`AfterRender` 的说明是当前 flush 的 DOM patch 完成后执行。
- [`internal/runtime/host_browser.mbt`](../../.mooncakes/moonbit-community/rabbita/internal/runtime/host_browser.mbt) 中，`request_task` 在微任务内依次处理消息和命令，遇到 `LegacyEffect(Immediately, f)` 直接调用 `f(self)`，之后通过 `request_animation_frame` 安排 DOM 更新。`AfterRender` 队列在 `document.update` 完成之后执行。这仍允许同步副作用的结果消息在下一次 DOM 更新之前再次改变模型。
- [`internal/vdom/diff.mbt`](../../.mooncakes/moonbit-community/rabbita/internal/vdom/diff.mbt) 的 `diff_props` 在处理已有 property 时，先比较旧虚拟值和新虚拟值，仅在 `value1 != value2` 时调用 `set_property`。这个分支没有读取实际 DOM 的当前值，也没有针对 `checked` 的特殊处理。

上述源码与独立复现相符：如果渲染器最终比较的是相同的虚拟值，就可能跳过对已被浏览器改变的 DOM 属性的纠正。另外，本次独立复现的立即回滚路径在初始 `view` 之后没有再次进入视图回调；不能假定每次异常都实际执行到了 `diff_props`。视图复用和相等属性比较都不能自行纠正已经变化的原生状态。这些证据仍不足以断言 Rabbita 的所有表单控件或所有事件路径都有同样的问题。

值得向上游讨论的设计问题是：当应用显式提供 `checked` 时，框架是否承诺在原生交互后把 DOM 恢复为模型指定的值，即使两次已提交视图中的值相同？如果承诺，单纯比较前后虚拟值可能不够；如果没有这样的承诺，则需要明确事件处理、同步拒绝以及命令执行时机的使用规则。

**当前应用采用的处理方式**

最初的规避方式是在 `viewed_persist_request` 中显式指定 `kind=@cmd.after_render`。2026-09-16 的区域渲染重构（提交 `6683edd`）把这一时序约束迁移到了应用的 `AfterCommit` 队列；2026-10-15 合入的依赖升级（提交 `0edf324`）将 Rabbita 更新为 `0.16.5`。不能把存储函数中移除显式 `after_render` 理解为框架已经修复了问题。

当前执行顺序为：

1. [`transition.mbt`](internal/application/transition.mbt) 的 `ui_after_commit` 在接受 Viewed 切换并创建待确认操作后，将 `viewed_persist_request` 放入以该文件为目标、`scope: Region` 的 `AfterCommit` 动作。
2. [`rendering/commit.mbt`](internal/rendering/commit.mbt) 的 `after_update` 在中央视图完成渲染后注册动作；[`rendering/region.mbt`](internal/rendering/region.mbt) 的 `wait_for` 检查对应文件区域的提交状态，尚未提交时将动作放入等待队列。区域自己的 BrowserHost 通过 `after_render` 通知 `committed`，布局处理完成后由 `finish_region` 释放等待中的命令。
3. [`viewed_storage.mbt`](internal/application/viewed_storage.mbt) 的 `viewed_persist_request` 执行存储并发送 `Stored`。该函数现在使用默认命令时机，渲染顺序由调用它的提交队列保证：

```moonbit
let epoch = model.viewed.epoch
@cmd.custom_cmd(scheduler => {
  let ok = viewed_storage_put(
    record.key(),
    ToJson::to_json(record).stringify(),
  )
  scheduler.add(emit(Viewed(Stored(epoch, index, record, ok))))
})
```

对于仍挂载的文件区域，乐观状态先提交到 DOM 和渲染器保存的视图，再执行可能同步失败的存储操作。如果存储失败，随后回滚会形成一次实际的虚拟属性变化：以上面的取消勾选为例，先提交 `false`，然后回滚到 `true`，渲染器便会重新写入 `checked`。

这里的 `after_render` 指相应 BrowserHost 的 DOM patch 已经完成，不表示屏幕必然已经显示过一帧乐观状态，也不是人为等待若干毫秒。区域独立渲染后，仅等待中央视图完成还不够；规避方式依赖的是对应文件区域的提交顺序。

“存储成功后才能发送 mutation”的约束仍由 [`reducer_viewed.mbt`](internal/application/reducer_viewed.mbt) 的 `Stored` 分支保证：失败时回滚；成功且操作仍有效时才进入 `viewed_write_request`。把存储推迟到 DOM patch 之后，并没有把网络写入提前到存储之前。该动作使用 `navigation: Continue`，在区域已卸载或页面切换时仍可能执行，因此迟到的存储结果仍需经过页面 epoch 和操作 ID 等校验。

这是一处应用级时序调整，没有修改 Rabbita 源码。它解决了当前已覆盖的“乐观更新后同步存储失败”场景，但不能据此声称已经修复框架中所有可能的受控表单同步问题。本次独立复现还确认，事件被直接拒绝、模型从始至终不变时也会出现 DOM 不一致；该结果不等于当前 Viewed 流程存在同样的可达问题。

**尝试过但没有保留的做法**

实现过程中曾尝试在 checkbox 的点击处理器中加入 `prevent_default()`，希望阻止浏览器自行切换。但该实验在项目中破坏了正常勾选和取消勾选的行为，因此已撤回。当前 [`viewed_view.mbt`](internal/view/viewed_view.mbt) 保留 `stop_propagation()`，没有采用该做法。

这一实验不能证明 `prevent_default()` 在所有框架或事件时序下都不适用。它只说明，取消 checkbox 默认行为还会影响浏览器对本次原生切换的处理，不能在未验证事件与渲染先后关系的情况下，把它当作通用修复。

**现有验证与重现入口**

[`tests/viewed.spec.mjs`](tests/viewed.spec.mjs) 中已有以下回归用例：

```text
session storage failure sends no mutation and preserves draft selection and expansion
```

该用例打开已有 Viewed 文件的行内草稿，保存草稿选择状态，然后仅对 Viewed 待确认记录的存储写入注入 `QuotaExceededError`。它通过可取消、冒泡的 `MouseEvent('click')` 触发复选框，以避免测试动作主动把焦点从编辑器移走。

用例检查：

- 显示无法保存 Viewed 操作的错误提示。
- 复选框恢复可操作，并保持操作前的已勾选状态。
- 文件保持应有的展开状态，草稿及选择状态得到保留。
- Viewed mutation 数量为零。
- 没有遗留待确认存储记录。

2026-10-16 已重新运行该用例，以及文末说明的 inline、reply、overall 三种编辑器在延迟身份检查期间保留状态的用例，结果为 **4 passed**。可在仓库根目录执行以下命令运行这四个回归；Playwright 配置会启动测试服务并构建所需产物：

```sh
cd review-web
./node_modules/.bin/playwright test frontend/tests/viewed.spec.mjs \
  --grep 'session storage failure sends no mutation|a delayed identity check retains' \
  --workers=1
```

当前代码包含区域提交队列，因此上述命令是应用回归验证入口，不是框架问题的复现入口。旧版文档中“移除 `viewed_persist_request` 的 `kind=@cmd.after_render` 即可重现”的步骤已不适用，该参数已经不在此函数中。验证底层行为应使用下面的隔离方案；若做应用级对照实验，应在独立副本中明确绕过对应区域的提交等待。

**Rabbita 0.16.5 独立复现结果**

2026-10-16 在临时目录中建立了独立 MoonBit 模块，使用本项目安装的 Rabbita `0.16.5` 编译 JavaScript release 产物，并通过 Playwright 在 Chromium 中加载。每个实验组件只有一个布尔模型、一个显式传入 `checked` 的 checkbox、关联 label、显示模型值的文本以及记录回调顺序的日志；没有 GitHub、文件树、草稿或真实存储依赖。

每个组合使用新页面，操作前检查初始 `checked`，操作后等待回滚或拒绝消息被处理，再等待三个动画帧，比较 reducer 记录的模型、页面中的模型文本和实际 `input.checked`。实验比较三种处理方式：

- `immediate`：`Toggle` 先返回相反布尔值，再由默认时机的 `custom_cmd` 立即发送 `Failed(before)`，恢复操作前的模型。
- `after_render`：与上面相同，仅将失败命令改为 `kind=@cmd.after_render`。
- `reject`：收到 `Toggle` 后直接返回原模型及 `none`，不做乐观切换。

每种处理方式分别覆盖初始勾选和初始未勾选，以及鼠标点击、空格键、关联 label 点击、合成 `MouseEvent('click', { bubbles: true, cancelable: true })`，共 8 种组合。前三种通过 Playwright 的浏览器鼠标/键盘输入触发，最后一种使用页面内的 `dispatchEvent`，没有将二者混为同一种输入。

| 处理方式 | 组合数 | 模型与实际 `checked` 不一致 | 结果 |
| --- | --- | --- | --- |
| 默认命令时机，乐观切换后同步回滚 | 8 | 8 | 两个切换方向、四种输入均复现 |
| `AfterRender` 命令，乐观切换后回滚 | 8 | 0 | 覆盖范围内均恢复为操作前状态 |
| 直接拒绝事件，模型不变 | 8 | 8 | 两个初始状态、四种输入均复现 |

总计 24 个组合，其中 16 个复现模型与 DOM 不一致，8 个验证了 `AfterRender` 的规避效果。例如初始为 `true` 时，立即回滚路径最终模型及模型文本均为 `true`，而 `input.checked` 为 `false`；初始为 `false` 时则相反。

日志记录了视图计算、乐观更新、副作用、回滚或拒绝回调及当时的 `checked`。立即回滚样例只有初始 `view(true)`，之后依次出现乐观 `false`、副作用和回滚 `true`；`AfterRender` 样例还出现中间的 `view(false)` 和回滚后的 `view(true)`。视图回调日志发生在生成视图时，不能当作 DOM patch 完成事件；最终 DOM 状态由浏览器单独读取确认。

这些实验未覆盖异步失败、Firefox、WebKit、文本输入或输入法组合状态，也未验证所有应用级并发路径。独立复现源码、驱动脚本和结果目前仅保存在本次核查的临时目录，尚未纳入仓库或整理为可提交的持久复现包；上面的矩阵记录的是已执行结果，不代表仓库已有这 24 个自动回归用例。

**向上游反馈前的待办**

- [x] 记录项目内触发条件、实际 DOM 异常和用户可见影响。
- [x] 核对当前安装版本的 `checked` 属性生成、命令调度及 property diff 实现。
- [x] 在应用内通过对应文件区域的 `AfterCommit` 队列规避，并重新运行存储失败的浏览器回归。
- [x] 建立独立最小复现：每个组件只保留一个布尔模型、一个 checkbox、一次乐观切换，以及立即返回失败消息的自定义命令；移除 GitHub、文件树、草稿、真实存储等无关依赖。
- [x] 记录模型更新、视图回调、副作用和实际 `input.checked`，比较默认命令与 `AfterRender` 的结果。
- [x] 覆盖初始勾选与初始未勾选、鼠标点击、空格键、label 点击，并区分浏览器输入与合成事件。
- [x] 验证同步失败回滚，以及应用直接拒绝事件、模型不变的情形。
- [ ] 将临时独立复现整理为可持久保存、可一键运行的复现包。
- [ ] 补充直接观察 DOM patch 前后顺序的记录，区分跳过视图计算与属性比较相等的路径。
- [ ] 覆盖异步失败，确认失败消息与渲染提交的先后关系如何影响结果；补充其他浏览器验证。
- [ ] 确认上游对显式 `checked` 的控制语义，再判断应修复 property 同步、提供专用表单机制，还是补充 API 文档与示例。
- [ ] 若提出框架补丁，验证是否影响其他 DOM property、文本输入的光标和选择、输入法组合状态，以及不应由框架反复覆盖的原生状态。不要未经评估就对所有 property 无条件赋值。
- [ ] 在独立复现和结论齐备后，整理版本、复现步骤、预期与实际行为、应用规避方式，形成可提交的上游报告。

**与另一处草稿焦点问题的区别**

同一轮实现还发现过身份检查期间草稿编辑器失去焦点，但那是本项目的视图条件问题：`AuthChecking` 临时禁止提交，而编辑器是否渲染也依赖同一个 `can_comment` 判断，于是编辑器被卸载，身份确认后再创建，原 DOM 节点和选择状态随之丢失。

目前通过 [`comments.mbt`](internal/comments/comments.mbt) 的 `draft_visible()` 和 [`update.mbt`](internal/comments/update.mbt) 的 `IdentityChecking` 状态，将身份检查期间已有草稿的显示与提交权限分别处理。检查期间保留编辑器，提交按钮仍禁用；身份检查得到明确结果后再应用对应权限。这个问题已有应用层原因，不应列为 Rabbita 缺陷，也不能拿来佐证上述 checkbox 问题。

2026-10-16 重新运行了 `tests/viewed.spec.mjs` 中的 `a delayed identity check retains the ${kind} editor while Viewed waits for confirmation`，其中 `kind` 分别为 `inline`、`reply`、`overall`，三例全部通过。用例检查身份检查期间编辑器 DOM 节点、焦点和内容得以保留，提交按钮禁用，并在身份确认后确认原节点、焦点和选择区间仍被保留。
