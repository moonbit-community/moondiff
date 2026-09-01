set -euox pipefail


ast_diff() {
  name=$1
  moon run --target wasm --release . "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

ast_diff_ignore_comments() {
  name=$1
  moon run --target wasm --release . --ignore-comments "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

ast_diff_ignore_tests() {
  name=$1
  moon run --target wasm --release . --ignore-tests "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

ast_diff "20251114"
ast_diff "20260601"
ast_diff "20260603"
ast_diff "20260604"
ast_diff "z0_20260604"
ast_diff "z0_20260605"
ast_diff "z0_20260608"
ast_diff "20260814"
ast_diff "20260820"
ast_diff_ignore_comments "ignore_comments"
ast_diff_ignore_comments "ignore_blank_lines"
ast_diff_ignore_tests "ignore_tests"
