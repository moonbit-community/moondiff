# Token-level Diff 评审报告

日期：2026-03-07  
范围：仅评审 `src/tokendiff/*` 与其 CLI 消费链路；未评审 `src/astdiff/*`。

## 1. 当前实现结构（简要）

主流程在 `src/tokendiff/diff_with_opt/diff_with_opt.mbt`：

1. `mbttoken`：源码词法化为 `MbtToken`（含 `Visible` / `Invisible` / `Barrier`）
2. `preopt`：剥离公共前后缀
3. `myers`：核心最短编辑路径
4. `compress`：合并连续同类 edit
5. `postopt`：边界对齐与空白处理
6. CLI：`line_group` + `rendering` 输出

## 2. 逻辑 Bug（含可复现结论）

### Bug 1：`split_matching_block` 重复消费同一个换行，可能产生多余空行/错位

- 位置：`src/tokendiff/cli/main.mbt:52`, `:66`
- 根因：
  - 找到首个换行后用 `widths[start:]` 再 `split(0)`，会把该首个 `0` 重复参与后续分段。
- 影响：
  - side-by-side 渲染中可能出现额外空行，左右行对应关系被扰动。

### Bug 2：`alignment` 的“满匹配最高分(4)”会被后续覆盖

- 位置：`src/tokendiff/postopt/alignment.mbt:243-247`, `:257-261`, `:266-271`
- 根因：
  - 先写入 `score=4`，随后循环调用 `calc_score` 又将同槽位改写为 `2`（Invisible）或 `1`（Int）。
- 影响：
  - 预期“全匹配优先”的策略失效，滑动边界选择可能偏离设计目标。
- 复现：
  - 白盒最小测试中 `fullfill_next_scoreboard([Invisible([1])])` 的结果为 `[2]`，不是预期的 `[4]`。

### Bug 3：`line_group` 会忽略仅尾部换行差异

- 位置：`src/tokendiff/line_group/line_group.mbt:10-16`
- 根因：
  - 对 `split("\n")` 结果反复去除末尾空串，导致尾部空行信息丢失。
- 影响：
  - `"a\n"` vs `"a"` 被判定为无差异（`None`）。
  - 对需要精确保留 EOF newline 语义的场景不正确。

## 3. 设计可改进点

### 改进 1：把“语义等价”与“格式等价”分层

- 现状：`MbtToken::Eq` 里 `Invisible` 与 `Barrier` 互相等价（`src/tokendiff/mbttoken/token.mbt:37-43`）。
- 问题：后处理需要额外特判把空白在 Equal/Insert/Delete 之间迁移，语义边界不清晰。
- 建议：
  - 保留严格 token 相等；另引入“可忽略空白”的比较策略（参数化或独立 comparator）。

### 改进 2：`compress` 合并路径避免重复拷贝

- 现状：连续合并使用 `hd + [tl]` 反复创建新数组（`src/tokendiff/compress/compress.mbt`）。
- 风险：长编辑序列下可能退化到较高常数/次优复杂度。
- 建议：
  - 在最后一个 chunk 上就地 `push`，减少中间数组分配。

### 改进 3：`alignment` 规则拆层，降低耦合

- 现状：`align_edit_boundaries` 同时承担模式识别、打分、滑动、反模式规避。
- 风险：行为难预测，新增规则易互相干扰。
- 建议：
  - 拆为 `candidate generation -> scoring -> apply` 三段；每段独立测试。

### 改进 4：补齐性质测试，而不只依赖快照场景

建议新增 invariant 测试：

1. edits 能分别重建 old/new 文本
2. 无空 edit chunk
3. 无相邻同类 edit（compress/postopt 后）
4. 针对 `Invisible([0,...])`、多空行、EOF newline 的边界案例

## 4. 测试现状补充

- 当前仓库 `moon test -v` 全绿（56/56）。
- 说明现有样例覆盖了常规路径，但对白盒边界（尤其空白/换行和后处理打分）覆盖不足。

