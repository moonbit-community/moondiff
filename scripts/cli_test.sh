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

ast_diff_ignore_test_file() {
  name=$1
  old_path=$2
  new_path=$3
  moon run --target wasm --release . --ignore-tests "$old_path" "$new_path" >"cli_test/snapshot/${name}.txt"
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
ast_diff_ignore_test_file "test_file_rename_from" "cli_test/source/helper_test.mbt" "cli_test/source/helper.txt"
ast_diff_ignore_test_file "test_file_rename_to" "cli_test/source/helper.txt" "cli_test/source/helper_wbtest.mbt"
ast_diff_ignore_test_file "test_file_added" "/dev/null" "cli_test/source/helper_test.mbt"
ast_diff_ignore_test_file "test_file_deleted" "cli_test/source/helper_wbtest.mbt" "/dev/null"
