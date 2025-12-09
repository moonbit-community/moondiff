

install:
  moon update
  moon fmt -- -add-uuid
  moon build --target native --release
  mkdir -p ~/.local/bin/
  cp target/native/release/build/tokendiff/cli/cli.exe ~/.local/bin/tokendiff

test:
  moon test --target all
  bash cli_test.sh
  git diff --exit-code