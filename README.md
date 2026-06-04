# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

## install

```shell
mkdir -p "$HOME/.local/share/moondiff"
curl -fsSL \
  -o "$HOME/.local/share/moondiff/moondiff_git_wrapper.sh" \
  "https://raw.githubusercontent.com/myfreess/moondiff/main/scripts/moondiff_git_wrapper.sh"
curl -fsSL \
  -o "$HOME/.local/share/moondiff/moondiff.wasm" \
  "https://github.com/myfreess/moondiff/releases/latest/download/moondiff.wasm"
```

## Use Moondiff in Git Repository

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
