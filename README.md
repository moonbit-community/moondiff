# moondiff

Difftool that aware MoonBit language syntax.

Inspired by [difftastic](https://github.com/Wilfred/difftastic)

Try it in playground: https://moonbit-community.github.io/moondiff/

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
