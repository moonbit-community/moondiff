alias u := update

update:
  moon fmt -- -add-uuid
  moon build --target native --release
  cp target/native/release/build/tokendiff/cli/cli.exe ~/.local/bin/tokendiff