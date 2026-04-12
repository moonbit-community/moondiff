set -euox pipefail


ast_diff() {
  name=$1
  ./_build/native/release/build/astdiff/cli/cli.exe "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

moon build --target native --release

ast_diff "20251114"