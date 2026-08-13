# tokdiff — lexer-based diff for MoonBit code

playground: https://moonbit-community.github.io/moondiff/

`tokdiff` separates diff calculation from presentation. The root package
tokenizes MoonBit, aligns lines and tokens, groups hunks, and returns a public
renderer-neutral `DiffDocument`. HTML and unified patch text live in dedicated
packages that consume the same calculated document.

```text
moonbit-community/moondiff/tokdiff       calculation and public diff IR
moonbit-community/moondiff/tokdiff/html  split and unified HTML rendering
moonbit-community/moondiff/tokdiff/text  unified patch text rendering
```

## Usage

Add the packages needed by the caller. An explicit alias keeps the tokdiff HTML
renderer distinct from other packages commonly named `html`:

```moon.pkg
import {
  "moonbit-community/moondiff/tokdiff",
  "moonbit-community/moondiff/tokdiff/html" @tokdiff_html,
  "moonbit-community/moondiff/tokdiff/text" @tokdiff_text,
}
```

Calculate once and select any renderer:

```mbt
let document = @tokdiff.diff(
  old=["let total = price"],
  new=["let total = price + tax"],
  context=3,
)
let split = @tokdiff_html.render_side_by_side(document, line_numbers=true)
let unified = @tokdiff_html.render_unified(document)
let patches = @tokdiff_text.render_unified_hunks(document)
```

Use `@tokdiff.line_diff` for plain text. It performs a Patience line diff without
MoonBit tokenization, semantic cleanup, or intraline highlights. The existing
convenience signatures remain available in their renderer packages, for
example `@tokdiff_html.side_by_side_html(old~, new~)` and
`@tokdiff_text.unified_hunks(old~, new~)`.

## Migration from the single root package

The calculation and rendered bytes are unchanged, but rendering names moved:

| Previous name | New name |
| --- | --- |
| `@tokdiff.side_by_side_html` and other `*_html` functions | `@tokdiff_html.side_by_side_html` and the corresponding HTML function |
| `@tokdiff.html_page` | `@tokdiff_html.html_page` |
| `@tokdiff.HunkNote` | `@tokdiff_html.HunkNote` |
| `@tokdiff.unified_hunks` | `@tokdiff_text.unified_hunks` |
| `@tokdiff.unified_line_hunks` | `@tokdiff_text.unified_line_hunks` |

The root package continues to expose `TokKind`, `Tok`, `weight`,
`tokenize_line`, and `similarity`, and now also exposes `diff`, `line_diff`,
and the `DiffDocument` IR types.
