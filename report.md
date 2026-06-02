# moondiff 与 difftastic AST diff 逻辑差异报告

本报告对比当前项目 `moondiff` 与相邻仓库 `../difftastic` 的核心 AST diff 算法逻辑，以及预处理和后处理逻辑。渲染层暂不纳入比较。

对比基准：

- `moondiff`: `1606d7d`
- `difftastic`: `cc064349a`

## 总体结论

当前项目并不是对 `difftastic` 当前版本 AST diff 管线的等价移植。两边共享了同源的核心思路：把 AST diff 建模为图搜索问题，在 `(lhs_next, rhs_next, delimiter_stack)` 状态图上用 Dijkstra 找最短路径，再将路径转换为 `ChangeMap`。但是在进入核心算法之前的分段预处理、MoonBit 专用顶层对齐、若干图搜索启发式、以及输出位置后处理上，存在会影响结果的明显差异。

这些差异不是单纯的实现语言差异，而是可能改变匹配路径、fallback 行为、diff 粒度、性能边界和最终 changed positions 的行为差异。

## 1. 预处理分段逻辑差异明显

### difftastic 当前逻辑

`difftastic` 在真正运行 Dijkstra 前，会先执行 `mark_unchanged()`：

- 先调用 `shrink_unchanged_at_ends()` 标记两端完全相同的节点。
- 再调用 `split_mostly_unchanged_toplevel()`，把多个顶层节点中“基本未变”的 list 单独切出来。
- 再通过 `split_unchanged()` 和 `split_unchanged_toplevel()` 进一步按 LCS 切分。
- 对超过 `TINY_TREE_THRESHOLD` 的完全相同大节点直接 `insert_deep_unchanged()`，避免进入图搜索。
- 最终返回一组 `possibly_changed` sections，只对这些 section 分别运行 `mark_syntax()`。

相关位置：

- `../difftastic/src/diff/unchanged.rs`
- `../difftastic/src/main.rs` 中调用 `unchanged::mark_unchanged(...)`

### moondiff 当前逻辑

当前项目没有使用上述 `mark_unchanged -> possibly_changed sections` 管线，而是在 `astdiff/unchanged.mbt` 中实现了另一套逻辑：

- `mark_syntax_roots()` 先做顶层 shared prefix/suffix。
- 中间部分用 `root_matches()` 做 top-level root LCS。
- 对 LCS 命中的 root 直接 deep unchanged。
- 对不匹配的 segment 递归调用 `mark_root_segments()` 或直接进入 `mark_syntax_subtree()`。
- 当两个 root 是相同显式 delimiter 的 list 时，会直接标记外层 delimiter unchanged，然后递归 children。

相关位置：

- `astdiff/unchanged.mbt`
- `tool/root_alignment.mbt` 中调用 `@diff.mark_syntax_roots(...)`

### 影响

这会影响大文件、多顶层声明、局部改动和移动场景下的行为：

- 两边进入 Dijkstra 的节点范围不同。
- 两边对顶层节点的配对策略不同。
- `moondiff` 没有 `difftastic` 当前的 tiny-tree threshold 逻辑，可能在小的相同节点上更积极地配对，也可能在大树上进入不同的搜索区间。
- `difftastic` 的 mostly-unchanged list 分段主要是性能和可读性优化，当前项目用 root LCS 替代后，结果未必等价。

这是最主要的算法管线差异之一。

## 2. moondiff 增加了 MoonBit 专用顶层 UUID 对齐

当前项目在 `tool/root_alignment.mbt` 中有 MoonBit 专用顶层对齐逻辑：

- 解析 top-level `ImplUnit`。
- 从 docstring 中识别 `///|UUID(...)`。
- 如果 old/new 两边所有 top-level unit 都有 UUID，则先按 UUID 对齐。
- 对齐后的每个 replace/delete/insert 单元再分别做 AST diff。
- 如果不是所有 unit 都有 UUID，则退回整文件 root-list diff。

相关位置：

- `tool/root_alignment.mbt`
- `collect_impl_units()`
- `align_impl_units_by_uuid()`
- `render_uuid_aligned_impl_diffs()`
- `render_root_list_diff()`

`difftastic` 没有这层 MoonBit 专用逻辑。它的通用 pipeline 是按语言 parse 出 root nodes 后，整体执行 unchanged 预处理和 section diff。

### 影响

这会在以下场景中显著改变 diff 输入：

- 顶层声明重排。
- 顶层声明插入/删除。
- UUID 保持不变但代码移动。
- UUID 重复或缺失。

如果 UUID 全覆盖，`moondiff` 会优先相信 UUID 对齐，而不是让核心 AST diff 自行在 root list 中寻找最佳路径。这可能是有意的 MoonBit 体验优化，但它与 difftastic 通用算法不等价。

## 3. 核心图搜索模型相同，但若干启发式不同

两边都有相似的核心图模型：

- `Vertex` 表示当前 lhs/rhs 待匹配节点，以及 delimiter stack。
- `Edge` 包含 unchanged node、enter unchanged delimiter、replace comment/string、novel lhs/rhs。
- `set_neighbours()` 根据当前状态生成可走边。
- `shortest_path()` 用 Dijkstra 找低成本路径。
- `populate_change_map()` 把路径转换为 `ChangeMap`。

但是细节上有几处会改变最短路径选择。

## 4. AST 构造层不是同一种输入

这是非常重要的前提差异。

### difftastic

`difftastic` 使用 tree-sitter 通用解析层：

- 根据路径和内容猜语言。
- 按语言配置 `atom_nodes`、`delimiter_tokens`、highlight query。
- 支持 embedded sublanguage。
- 支持 `ignore_comments`。
- 支持 `byte_limit` 和 `parse_error_limit`。
- parser error 可作为 `TreeSitterError` atom 进入 AST，错误数超过限制才 fallback。

相关位置：

- `../difftastic/src/parse/tree_sitter_parser.rs`
- `../difftastic/src/options.rs`

### moondiff

当前项目使用 MoonBit parser：

- `@parser.parse_string(old_source)`
- `@parser.parse_string(new_source)`
- parser report 非空时直接 fallback 到 line diff。
- parse 成 MoonBit AST 后，通过 `elab` 转成 `@syntax.Syntax`。
- `elab` 会基于 AST loc 把 gap token、docstring、attribute、type、keyword、string 等组织成 `Syntax`。

相关位置：

- `tool/diff_text.mbt`
- `parser/top.mbt`
- `elab/context.mbt`
- `elab/decl_elab.mbt`
- `elab/expr_elab.mbt`
- `elab/types_elab.mbt`

### 影响

即使核心图搜索完全一致，只要 `Syntax` 树形结构不同，最终 diff 也会不同。当前项目的 AST 输入是 MoonBit 语义化 AST elaboration，difftastic 的输入是 tree-sitter token/list 结构。这意味着：

- delimiter 的归属可能不同。
- atom/list 的边界可能不同。
- comment/docstring 处理不同。
- parse error 策略不同。
- gap 中的符号拆分方式不同。

因此，不能把当前项目的输出直接视为 difftastic 对 MoonBit 的输出等价物。

## 5. Atom 规范化存在差异

`difftastic` 的 `Syntax::new_atom()` 会做两个清理：

- 如果 atom 内容以 `\r` 结尾，会去掉。
- 如果 atom 内容以 `\n` 结尾，会同步去掉尾部 newline 和最后一个 position。

相关位置：

- `../difftastic/src/parse/syntax.rs`

当前项目的 `Syntax::atom()` 本身没有这一步：

- `syntax/syntax.mbt`

### 影响

如果 `elab` 或 parser loc 产生的 atom 含有 trailing `\r` 或 `\n`，两边的 `content_id` 和位置会不同，从而影响 matching 和 highlighting。

当前项目中多数 token 来自 loc 切片和 gap tokenization，未必经常触发这个问题，但这是一个实际逻辑差异。

## 6. Slider 后处理大体同源，但语言策略固定

两边都有 slider 修正逻辑：

- 对连续 novel region 做前后滑动。
- 修正 nested slider。
- 运行两轮 one-step slider，再处理 nested slider。

但是 `difftastic` 根据语言选择 prefer outer/inner delimiter：

- Lisp、JSON、TOML、HCL、SQL 等 prefer outer。
- 其它语言 prefer inner。

当前项目固定：

```moonbit
fn prefer_outer_delimiter() -> Bool {
  false
}
```

相关位置：

- `../difftastic/src/diff/sliders.rs`
- `astdiff/sliders.mbt`

### 影响

这对 MoonBit 可能是合理选择，因为 MoonBit 更接近 call-like syntax，倾向 prefer inner。但它与 difftastic 的通用语言参数化行为不同。

如果未来支持 MoonBit 内嵌 DSL、JSON-like literal 或其它不同风格结构，固定策略可能不够。

## 7. Changed positions 后处理语义更简化

### difftastic

`difftastic` 的 `MatchedPos` 和 `MatchKind` 更丰富：

- `UnchangedToken`
- `Novel`
- `UnchangedPartOfNovelItem`
- `NovelWord`
- `Ignored`

并且保留 token highlight：

- delimiter
- normal atom
- string
- text
- comment
- type
- keyword
- tree-sitter error

在没有 unchanged item 时，还会插入 0 宽 dummy unchanged anchor，供后续 hunk/context 对齐使用。

相关位置：

- `../difftastic/src/parse/syntax.rs`
- `../difftastic/src/line_parser.rs`
- `../difftastic/src/display/context.rs`
- `../difftastic/src/display/hunks.rs`

### moondiff

当前项目的 `tool/positions.mbt` 中 `MatchKind` 只有：

- `Novel`
- `Unchanged(opposite_pos)`

虽然 `split_replaced_atom_positions()` 也会对 replaced string/comment 做词级拆分，但输出状态仍然简化为 novel/unchanged 两类。

相关位置：

- `tool/positions.mbt`

### 影响

如果只看“哪些位置改变”，当前项目能表达核心信息；但若看后续 hunk 组织、inline 粒度或忽略项语义，它比 difftastic 少了状态。

即使暂不比较渲染，这仍然属于后处理语义差异，因为 changed positions 本身已经不同。

## 8. Replaced comment/string 的词级 diff 逻辑不完全一致

两边都支持对 replaced comment/string 做更细粒度拆分，但实现不同。

`difftastic`：

- 使用 `split_words_and_numbers()`。
- 数字和字母会拆开，例如 `foo123bar` -> `foo`, `123`, `bar`。
- 使用 `lcs_diff::slice_by_hash()`。
- `has_common_words()` 要求 common word 数量更严格，注释里说明是因为字符串/comment delimiter 也参与内容。

`moondiff`：

- 使用本地 `split_word_parts()`。
- 将连续字母数字下划线作为同一类 word，不按数字/字母边界拆开。
- 使用本地 DP LCS。
- `has_common_words()` 阈值是 `unchanged_count > 1 && unchanged_count * 2 >= novel_count`。

相关位置：

- `../difftastic/src/words.rs`
- `../difftastic/src/parse/syntax.rs`
- `tool/positions.mbt`

### 影响

字符串和注释内部变更时，两边的局部高亮粒度可能不同。特别是包含数字版本号、标识符+数字、Unicode word 的场景。

## 9. fallback 条件不同

`difftastic` fallback 条件包括：

- 未识别语言。
- byte limit 超过。
- parse error count 超过限制。
- graph limit 超过。
- 用户选择 text override。

当前项目主要包括：

- MoonBit parser reports 非空。
- graph limit 超过。

相关位置：

- `../difftastic/src/main.rs`
- `../difftastic/src/options.rs`
- `tool/diff_text.mbt`
- `tool/root_alignment.mbt`

### 影响

两边对“语法不完整但可解析部分 AST”的容忍度不同。`difftastic` 可以在一定 parse error 数内继续做 AST diff；当前项目只要 parser report 非空就 fallback。

这会影响编辑中代码、语法错误代码、半成品文件的 diff 行为。

## 10. ChangeMap 深度标记有小的健壮性差异

`difftastic` 的 `insert_deep_unchanged()` 对 list children 使用 `zip()`：

- 如果两边 children 数量不一致，只会按较短侧递归。
- 但正常情况下 deep unchanged 只应在 content 相同结构上发生。

当前项目在 children 长度不一致时会 `panic()`：

- `astdiff/changes.mbt`

### 影响

理论上 deep unchanged 节点结构应该一致，所以不应触发。但如果上游错误地调用，当前项目会更早失败，difftastic 会更宽容一些。

## 优先级建议

### 高优先级：明确是否需要与 difftastic 当前行为对齐

如果目标是“尽量等价于 difftastic 当前核心算法”，建议优先处理：

1. punctuation 识别策略：确认是否故意为 MoonBit 扩大范围。
2. unchanged 预处理：决定是保留当前 root LCS 方案，还是移植 difftastic 的 `mark_unchanged()` section pipeline。

### 中优先级：补齐测试覆盖

建议新增对比测试覆盖：

- 顶层插入/删除/重排。
- 大函数中只改少量节点。
- 包含多个相同小 punctuation token 的表达式。
- 嵌套括号 slider。
- 字符串/comment 内数字变化，例如 `"foo123bar"` -> `"foo124bar"`。
- 语法错误输入 fallback。
- UUID 对齐启用和未启用两种路径。

### 低优先级：后处理状态精细化

如果后续渲染、JSON 输出或 API 需要更接近 difftastic，可考虑扩展 `tool/positions.mbt` 的状态表达，增加类似：

- delimiter vs atom kind
- novel word vs whole novel token
- unchanged part of novel item
- ignored token/comment
- dummy anchor

## 总结

当前项目的核心 Dijkstra AST diff 模型与 `difftastic` 同源，但整体管线已经明显分叉：

- 预处理不是同一套 section shrinking 算法。
- 增加了 MoonBit UUID 顶层对齐。
- 图搜索 punctuation heuristic 有差异。
- parser/AST 构造完全不同。
- positions 后处理更简化。

如果项目目标是 MoonBit 专用体验，这些差异中有些可能是合理的定制；如果目标是对齐 `difftastic` 当前算法行为，则需要逐项收敛，并用 targeted tests 锁定行为。
