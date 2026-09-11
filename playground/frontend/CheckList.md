**Rabbita 复选框在同步失败回滚后与模型状态不一致的问题记录**

记录日期：2026-09-11。涉及版本：本项目声明并安装的 `moonbit-community/rabbita@0.14.2`，前端编译目标为 JavaScript，相关浏览器回归使用 Chromium。

本记录整理 Viewed 功能实现过程中遇到的一个问题：浏览器已经切换了 checkbox 的实际 `checked` 属性，但应用的乐观更新与失败回滚发生在下一次 DOM 更新之前，最终可能出现“模型已经回滚，复选框仍显示操作后的状态”。当前应用通过 `after_render` 调整持久化命令的执行时机，已解决已覆盖的场景。

项目中的异常现象和规避效果已经观察到；下面列出的本地依赖源码也支持对原因的分析。不过，目前尚未抽出脱离 moondiff 的独立最小复现，也没有确认 Rabbita 对这类受控表单行为的完整 API 契约，因此暂时应将其视为值得反馈的上游设计问题候选，而不是已经定性的上游 bug。尚未向上游提交 issue。

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
| 渲染器比较前后 `checked`，两者都是 `true` | `true` | `true` | 若未重新写入该属性，仍为 `false` |

这里“模型最终恢复到旧值”并不意味着“DOM 仍然等于旧值”：浏览器已经在应用之外修改了复选框。反方向的勾选失败也存在同类时序风险，但不能把这一推论当作已经完成的独立双向复现。

**从当前依赖源码能够确认的部分**

本次记录核对了仓库中安装的 Rabbita 源码，得到以下事实：

- [`html/html_utils.mbt`](../../.mooncakes/moonbit-community/rabbita/html/html_utils.mbt) 的 `push_checked` 和 [`html/attrs.mbt`](../../.mooncakes/moonbit-community/rabbita/html/attrs.mbt) 的 `Attrs::checked` 都把 `checked` 放入 DOM property 集合，而不是仅设置 HTML attribute。
- [`cmd/commands.mbt`](../../.mooncakes/moonbit-community/rabbita/cmd/commands.mbt) 中，`custom_cmd` 默认使用 `Immediately`；`AfterRender` 的说明是当前 flush 的 DOM patch 完成后执行。
- [`internal/runtime/sandbox.mbt`](../../.mooncakes/moonbit-community/rabbita/internal/runtime/sandbox.mbt) 中，`Immediately` 直接执行回调；消息队列被依次处理，DOM 更新通过 `request_animation_frame` 安排。`AfterRender` 队列则在 `diff_node` 完成之后执行。这允许同步副作用的结果消息在下一次 DOM 更新之前再次改变模型。
- [`internal/runtime/vdom.mbt`](../../.mooncakes/moonbit-community/rabbita/internal/runtime/vdom.mbt) 的 `diff_props` 在处理已有 property 时，先比较旧虚拟值和新虚拟值，仅在 `v1 != v2` 时调用 `set_property`。这个分支没有读取实际 DOM 的当前值，也没有针对 `checked` 的特殊处理。

上述源码与观察到的现象相符：如果渲染器最终比较的是回滚前后相同的虚拟值，就可能跳过对已被浏览器改变的 DOM 属性的纠正。不过，源码阅读和项目内回归还不能替代独立复现，也不足以断言 Rabbita 的所有表单控件或所有事件路径都有同样的问题。

值得向上游讨论的设计问题是：当应用显式提供 `checked` 时，框架是否承诺在原生交互后把 DOM 恢复为模型指定的值，即使两次已提交视图中的值相同？如果承诺，单纯比较前后虚拟值可能不够；如果没有这样的承诺，则需要明确事件处理、同步拒绝以及命令执行时机的使用规则。

**当前应用采用的处理方式**

当前在 [`viewed_storage.mbt`](internal/application/viewed_storage.mbt) 的 `viewed_persist_request` 中显式使用 `after_render`：

```moonbit
@cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
  let ok = viewed_storage_put(
    record.key(),
    ToJson::to_json(record).stringify(),
  )
  scheduler.add(emit(Viewed(Stored(model.viewed.epoch, index, record, ok))))
})
```

这样，乐观状态先提交到 DOM 和渲染器保存的视图，再执行可能同步失败的存储操作。如果存储失败，随后回滚会形成一次实际的虚拟属性变化：以上面的取消勾选为例，先提交 `false`，然后回滚到 `true`，渲染器便会重新写入 `checked`。

这里的 `after_render` 指 DOM patch 已经完成，不表示屏幕必然已经显示过一帧乐观状态，也不是人为等待若干毫秒。规避方式依赖的是渲染提交顺序。

“存储成功后才能发送 mutation”的约束仍由 [`reducer_viewed.mbt`](internal/application/reducer_viewed.mbt) 的 `Stored` 分支保证：失败时回滚；成功且操作仍有效时才进入 `viewed_write_request`。把存储推迟到 DOM patch 之后，并没有把网络写入提前到存储之前。迟到的存储结果仍需经过页面 epoch 和操作 ID 等校验。

这是一处应用级时序调整，没有修改 Rabbita 源码。它解决了当前“乐观更新后同步存储失败”的场景，但不能据此声称已经修复框架中所有可能的受控表单同步问题。例如，事件被应用直接拒绝、模型从始至终不变的情况，需要单独验证。

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

该用例在此前功能实现的验证中已通过。本次仅新增问题记录并核对源码，没有重新运行浏览器测试。可在仓库根目录执行下列命令单独运行该回归；Playwright 配置会启动测试服务并构建所需产物：

```sh
cd playground
./node_modules/.bin/playwright test frontend/tests/viewed.spec.mjs --grep 'session storage failure sends no mutation' --workers=1
```

当前代码包含规避方式，因此上述命令是回归验证入口，不是“当前版本仍会失败”的声明。若要重现旧路径，应在独立实验副本中移除 `viewed_persist_request` 的 `kind=@cmd.after_render`，保留存储同步失败注入，再比较实际 DOM 与模型状态。

**向上游反馈前的待办**

- [x] 记录项目内触发条件、实际 DOM 异常和用户可见影响。
- [x] 核对当前安装版本的 `checked` 属性生成、命令调度及 property diff 实现。
- [x] 在应用内使用 `after_render` 规避，并保留存储失败的浏览器回归。
- [ ] 建立独立最小复现：只保留一个布尔模型、一个 checkbox、一次乐观切换，以及立即返回失败消息的自定义命令；移除 GitHub、文件树、草稿、真实存储等无关依赖。
- [ ] 在最小复现中记录点击处理、模型更新、DOM patch 前后的顺序，以及实际 `input.checked`；分别比较默认命令和 `AfterRender`。
- [ ] 覆盖初始勾选与初始未勾选、鼠标点击、空格键、label 点击，并区分真实用户输入与合成事件。
- [ ] 覆盖同步失败、异步失败，以及应用拒绝事件但模型不变的情形；确认哪些条件是必要触发条件。
- [ ] 确认上游对显式 `checked` 的控制语义，再判断应修复 property 同步、提供专用表单机制，还是补充 API 文档与示例。
- [ ] 若提出框架补丁，验证是否影响其他 DOM property、文本输入的光标和选择、输入法组合状态，以及不应由框架反复覆盖的原生状态。不要未经评估就对所有 property 无条件赋值。
- [ ] 在独立复现和结论齐备后，整理版本、复现步骤、预期与实际行为、应用规避方式，形成可提交的上游报告。

**与另一处草稿焦点问题的区别**

同一轮实现还发现过身份检查期间草稿编辑器失去焦点，但那是本项目的视图条件问题：`AuthChecking` 临时禁止提交，而编辑器是否渲染也依赖同一个 `can_comment` 判断，于是编辑器被卸载，身份确认后再创建，原 DOM 节点和选择状态随之丢失。

目前通过 [`comments.mbt`](internal/comments/comments.mbt) 的 `draft_visible()` 和 [`update.mbt`](internal/comments/update.mbt) 的 `IdentityChecking` 状态，将身份检查期间已有草稿的显示与提交权限分别处理。检查期间保留编辑器，提交按钮仍禁用；身份检查得到明确结果后再应用对应权限。这个问题已有应用层原因，不应列为 Rabbita 缺陷，也不能拿来佐证上述 checkbox 问题。
