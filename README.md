# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

Try it in playground: https://moonbit-community.github.io/moondiff/

## CLI

```shell
moondiff [--ignore-comments] [--ignore-tests] old-file new-file
```

`--ignore-tests` is off by default. If either path ends in `_test.mbt` or
`_wbtest.mbt` (case-sensitive), the entire comparison is ignored before parsing,
including helper functions, imports, and invalid syntax. This also covers
additions, deletions (`/dev/null`), and renames to or from ordinary files. File
headers remain visible with an ignored-file notice; identical content still
reports no changes.

For other pairs where both paths end in `.mbt`, after both inputs parse
successfully, top-level `test` and
`async test` blocks are removed from lexical and AST comparison, together with
their leading documentation comments, `///|UUID(...)` markers, and `///|`
separators. Test-only changes report no changes; when production code also
changes, only that production change is highlighted. Imports such as
`import { ... } for "test"` remain ordinary source and are still compared.

`--ignore-comments` independently excludes comments and blank-line-only
changes. The flags can be combined. If either MoonBit input fails to parse,
the CLI retains its existing whole-file lexical fallback unless a test-file
path matched; test-block filtering is not guaranteed in that fallback. Other
pairs, including ordinary `.mbt`/text comparisons and ordinary `.mbt` additions
or deletions, go directly to the plain line diff without MoonBit parsing and
are unaffected by either MoonBit filter.

The library's `mbtdiff.diff` uses `old_name` and `new_name` for both path
filtering and parser diagnostics. With `DiffOptions(ignore_tests=true)`, a
matching path returns `IgnoredOnly`, an empty `Whole` document, and no fallbacks
when content differs; `Identical` retains priority. Omitting names keeps the
defaults `"old"` and `"new"` and only applies test-block filtering.
`DiffResult.ignore_reason()` returns `Some(TestFile)` for a whole-file exclusion
and `Some(FilteredContent)` when content filters exclude all changes. Other
statuses return `None`. The CLI uses the shared internal test-file path rule
to decide whether MoonBit calculation is needed; displayed statuses and ignore
notices still come from the core result.

For reliably aligned MoonBit declarations, each CLI section title ends with
the trimmed source line containing that declaration's keyword, and every
visible `@@ ... @@` hunk heading repeats the same context. Matching old/new
lines are shown once; changed declaration lines are rendered as
`old: … → new: …`. Leading documentation, UUID markers, separators, and
standalone attribute lines are not used as the context. Whole-file results,
including parse-failure fallbacks, and ordinary text diffs do not attach a
top-level declaration context.

## install (unfinish)


## Use Moondiff in Git Repository (unfinish)

configure git to use the installed wasm as an optional diff tool within that repository:

```shell
git config diff.tool moondiff
git config difftool.moondiff.cmd 'bash "$HOME/.local/share/moondiff/moondiff_git_wrapper.sh" "$LOCAL" "$REMOTE" "$MERGED"'
git config difftool.prompt false
```

usage:

```shell
git difftool <commit>^ <commit> # view diff for a specific commit
git difftool <edited file>
```
