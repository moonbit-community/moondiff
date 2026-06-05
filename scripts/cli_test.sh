set -euox pipefail


ast_diff() {
  name=$1
  moonrun ./_build/wasm/release/build/moonbit-community/moondiff/moondiff/moondiff.wasm "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

moon build --target wasm --release

ast_diff "20251114"
ast_diff "20260601"
ast_diff "20260603"
ast_diff "20260604"
ast_diff "z0_20260604"
ast_diff "z0_20260605"
