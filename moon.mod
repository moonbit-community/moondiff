name = "moonbit-community/moondiff"

version = "0.0.6"

import {
  "moonbit-community/prettyprinter@0.4.10",
  "moonbit-community/chalk@0.0.1",
  "moonbitlang/lexer@0.3.16",
  "moonbitlang/parser@0.3.19",
  "moonbitlang/async@0.21.2",
}

readme = "README.md"

repository = "https://github.com/moonbit-community/moondiff"

license = "Apache-2.0"

keywords = [ "diff", "astdiff" ]

description = "Difftool that aware MoonBit language syntax"

preferred_target = "wasm"

options(
  exclude: [ "extension", "cli_test", "scripts", "playground" ],
)
