set -euox pipefail


ast_diff() {
  name=$1
  moonrun ./_build/wasm/release/build/moondiff.wasm "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

ast_diff_ignore_comments() {
  name=$1
  moonrun ./_build/wasm/release/build/moondiff.wasm --ignore-comments "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

moon build --target wasm --release

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
