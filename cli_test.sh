set -euox pipefail


ast_diff() {
  name=$1
  ./_build/native/release/build/myfreess/moondiff/astdiff/cli/cli.exe "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

moon build --target native --release

ast_diff "20251114"
ast_diff "pipeline_test_001"
ast_diff "pipeline_test_002"
ast_diff "pipeline_test_003"
ast_diff "pipeline_test_004"
ast_diff "pipeline_test_005"
ast_diff "pipeline_test_006"
ast_diff "pipeline_test_007"
ast_diff "pipeline_test_008"
ast_diff "pipeline_test_009"
ast_diff "pipeline_test_010"
ast_diff "pipeline_test_011"
ast_diff "pipeline_test_012"
ast_diff "pipeline_test_add_string"
ast_diff "pipeline_test_adt"
ast_diff "pipeline_test_alias_bug"
ast_diff "pipeline_test_alias_to_object_type"
ast_diff "pipeline_test_allow_positional"
ast_diff "pipeline_test_annotation_node"
ast_diff "pipeline_test_any_as_object"
