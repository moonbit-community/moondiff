# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

Try it in playground: https://moonbit-community.github.io/moondiff/

## CLI

```shell
moondiff [--ignore-comments] [--ignore-tests] old-file new-file
```

`--ignore-tests` is off by default and applies only when both paths end in
`.mbt`. After both MoonBit inputs parse successfully, top-level `test` and
`async test` blocks are removed from lexical and AST comparison, together with
their leading documentation comments, `///|UUID(...)` markers, and `///|`
separators. Test-only changes report no changes; when production code also
changes, only that production change is highlighted. Imports such as
`import { ... } for "test"` remain ordinary source and are still compared.

`--ignore-comments` independently excludes comments and blank-line-only
changes. The flags can be combined. If either MoonBit input fails to parse,
the CLI retains its existing whole-file lexical fallback; `--ignore-tests` is
not guaranteed to filter that fallback. Non-`.mbt` inputs always use the plain
line diff and are unaffected by either MoonBit filter.

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
