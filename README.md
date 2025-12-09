# moondiff

Difftool that aware MoonBit language syntax.

![tokendiff](./tokendiff.png)

## Token based diff

### install

+ native binary

```shell
moon build --target native
# add `~/.local/bin` to your `PATH`
mkdir -p ~/.local/bin
cp target/native/release/build/tokendiff/cli/cli.exe ~/.local/bin/tokendiff
```
### use

moondiff relies on some features of `moonfmt`: 

+ `-block-style` (which is now the default behavior) 
+ `-add-uuid` (not the default behavior). 

If you want to use moondiff in a MoonBit repository, please first execute the following command:

```shell
moon fmt -- -add-uuid
```

Then, configure git to use the installed binary as an optional diff tool within that repository:

```shell
git config diff.tool tokendiff
git config difftool.tokendiff.cmd '~/.local/bin/tokendiff $LOCAL $REMOTE'
git config difftool.prompt false
```