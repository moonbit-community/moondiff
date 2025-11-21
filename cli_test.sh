set -euox pipefail


token_diff() {
  name=$1
  ./target/native/release/build/tokendiff/cli/cli.exe "cli_test/source/${name}.old.mbt" "cli_test/source/${name}.new.mbt" >"cli_test/snapshot/${name}.txt"
}

token_diff "20251114"