///|
extern "js" fn same_highlights(
  a : @highlight.FileHighlights,
  b : @highlight.FileHighlights,
) -> Bool =
  #| (a, b) => a === b

///|
test "C headers and MoonBit apply line and source budgets independently per side" {
  let source = "0,".repeat(1025) +
    "\n" +
    ("0,".repeat(1024) + "\n").repeat(16) +
    "1"
  for path in ["code.c", "code.h", "code.mbt"] {
    let highlights = file_highlights(path, path, source, source)
    for side in [highlights.old.unwrap(), highlights.new.unwrap()] {
      assert_true(side.line(1).is_empty())
      for line in 2..<=17 {
        assert_eq(side.line(line).length(), 1024)
      }
      assert_true(side.line(18).is_empty())
    }
  }
}

///|
test "source highlights are computed once across all diff options" {
  let initial = ready_test_file(
    fixture_file("src/code.mbt", "modified"),
    ["fn value() { 1 // before", "}"],
    ["fn value() { 22 // after", "}"],
  )
  assert_true(initial.diff_cache.highlights is None)
  let mut file = ensure_file_document(initial, LexicalAlgorithm)
  let highlights = file.diff_cache.highlights.unwrap()
  assert_true(highlights.old is Some(_))
  assert_true(highlights.new is Some(_))
  for algorithm in [LexicalAlgorithm, AstAlgorithm] {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        file = ensure_file_document(
          file,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
        assert_true(
          same_highlights(highlights, file.diff_cache.highlights.unwrap()),
        )
      }
    }
  }
  assert_true(initial.diff_cache.highlights is None)
}

///|
test "highlights wait for source and remain available for fallback diffs" {
  let initial = ready_test_file(
    fixture_file("src/broken.mbt", "modified"),
    ["fn incomplete( { let x = 1"],
    ["fn incomplete( [ let x = 2"],
  )
  for
    state in [
      NotRequested,
      Loading,
      LoadFailed("retry"),
      CannotRender("binary", false),
    ] {
    let pending = ensure_file_document(
      { ..initial, old_side: state, },
      AstAlgorithm,
    )
    assert_true(pending.diff_cache.highlights is None)
  }
  let fallback = ensure_file_document(initial, AstAlgorithm)
  let highlights = fallback.diff_cache.highlights.unwrap()
  assert_true(highlights.old.unwrap().line(1).length() > 0)
  assert_true(highlights.new.unwrap().line(1).length() > 0)
  for (old, new) in [("code.mbt", "code.txt"), ("code.txt", "code.mbt")] {
    let renamed = ensure_file_document(
      ready_test_file(
        fixture_file(new, "renamed", previous_filename=old),
        ["let x = 1"],
        ["let x = 2"],
      ),
      AstAlgorithm,
    )
    let highlights = renamed.diff_cache.highlights.unwrap()
    assert_eq(highlights.old is Some(_), old.has_suffix(".mbt"))
    assert_eq(highlights.new is Some(_), new.has_suffix(".mbt"))
  }
}

///|
test "highlight routing is case sensitive and independent for every rename side" {
  let cases = [
    ("code.c", "int x = 1;", Some(@highlight.Type)),
    ("code.h", "int x = 1;", Some(Type)),
    ("config.yaml", "enabled: true", Some(Variable)),
    ("config.yml", "enabled: true", Some(Variable)),
    ("config.YAML", "enabled: true", None),
    ("config.YML", "enabled: true", None),
    ("config.Yaml", "enabled: true", None),
    ("config.yaml.txt", "enabled: true", None),
    ("code.mbt", "let x = 1", Some(Keyword)),
    ("moon.mod", "name = \"example/demo\"", Some(Variable)),
    ("src/moon.mod", "name = \"example/demo\"", Some(Variable)),
    ("moon.pkg", "import { \"moonbitlang/core/json\" }", Some(Keyword)),
    ("src/moon.pkg", "options(\"is-main\": true)", Some(Function)),
    ("moon.mod.json", "name = \"example/demo\"", None),
    ("src/notmoon.mod", "name = \"example/demo\"", None),
    ("src/moon.pkg.json", "import {}", None),
    ("notmoon.pkg", "import {}", None),
    ("src/MOON.PKG", "import {}", None),
    ("code.txt", "int x = 1;", None),
    ("code.mbti", "pub fn x() -> Int", None),
    ("code.C", "int x = 1;", None),
    ("code.H", "int x = 1;", None),
    ("code.MBT", "let x = 1", None),
    ("code.cpp", "int x = 1;", None),
    ("code.c.txt", "int x = 1;", None),
  ]
  for (old_path, old_source, old_kind) in cases {
    for (new_path, new_source, new_kind) in cases {
      let file = ensure_file_document(
        ready_test_file(
          fixture_file(new_path, "renamed", previous_filename=old_path),
          [old_source],
          [new_source],
        ),
        LexicalAlgorithm,
      )
      let highlights = file.diff_cache.highlights.unwrap()
      assert_eq(highlights.old.map(h => h.line(1)[0].kind), old_kind)
      assert_eq(highlights.new.map(h => h.line(1)[0].kind), new_kind)
    }
  }
}

///|
test "C additions deletions and renames retain line diffs and reuse source highlights" {
  for
    file in [
      fixture_file("code.c", "added"),
      fixture_file("code.h", "added"),
      fixture_file("code.c", "removed"),
      fixture_file("code.h", "removed"),
      fixture_file("code.h", "renamed", previous_filename="old.c"),
    ] {
    let old = if file.status == "added" { [] } else { ["int value = 1;"] }
    let new = if file.status == "removed" { [] } else { ["int value = 2;"] }
    let initial = ready_test_file(file, old, new)
    assert_true(initial.diff_mode is LineDiff)
    let mut cached = ensure_file_document(initial, LexicalAlgorithm)
    let highlights = cached.diff_cache.highlights.unwrap()
    assert_eq(
      highlights.old.unwrap().line(1).is_empty(),
      file.status == "added",
    )
    assert_eq(
      highlights.new.unwrap().line(1).is_empty(),
      file.status == "removed",
    )
    for algorithm in [LexicalAlgorithm, AstAlgorithm] {
      for ignore_comments in [false, true] {
        for ignore_tests in [false, true] {
          cached = ensure_file_document(
            cached,
            algorithm,
            ignore_comments~,
            ignore_tests~,
          )
          assert_true(
            same_highlights(highlights, cached.diff_cache.highlights.unwrap()),
          )
          assert_true(cached.diff_cache.get(Line) is Some(Line(_)))
        }
      }
    }
    assert_true(initial.diff_cache.highlights is None)
  }
}

///|
test "C highlights wait for both loaded source sides" {
  let initial = ready_test_file(
    fixture_file("code.c", "modified"),
    ["int old;"],
    ["int new;"],
  )
  for
    pending in [
      NotRequested,
      Loading,
      LoadFailed("retry"),
      CannotRender("binary", false),
    ] {
    for
      file in [
        { ..initial, old_side: pending, },
        { ..initial, new_side: pending, },
      ] {
      assert_true(
        ensure_file_document(file, LexicalAlgorithm).diff_cache.highlights
        is None,
      )
    }
  }
}

///|
test "YAML additions deletions and renames retain line diffs and reuse highlights" {
  for
    file in [
      fixture_file("config.yaml", "added"),
      fixture_file("config.yml", "added"),
      fixture_file("config.yaml", "removed"),
      fixture_file("config.yml", "removed"),
      fixture_file("config.yaml", "renamed", previous_filename="old.yml"),
      fixture_file("config.yml", "renamed", previous_filename="old.yaml"),
    ] {
    let old = if file.status == "added" { [] } else { ["value: 1"] }
    let new = if file.status == "removed" { [] } else { ["value: 2"] }
    let initial = ready_test_file(file, old, new)
    assert_true(initial.diff_mode is LineDiff)
    let mut cached = ensure_file_document(initial, LexicalAlgorithm)
    let highlights = cached.diff_cache.highlights.unwrap()
    assert_eq(
      highlights.old.unwrap().line(1).is_empty(),
      file.status == "added",
    )
    assert_eq(
      highlights.new.unwrap().line(1).is_empty(),
      file.status == "removed",
    )
    for algorithm in [LexicalAlgorithm, AstAlgorithm] {
      for ignore_comments in [false, true] {
        for ignore_tests in [false, true] {
          cached = ensure_file_document(
            cached,
            algorithm,
            ignore_comments~,
            ignore_tests~,
          )
          assert_true(
            same_highlights(highlights, cached.diff_cache.highlights.unwrap()),
          )
          assert_true(cached.diff_cache.get(Line) is Some(Line(_)))
        }
      }
    }
    assert_true(initial.diff_cache.highlights is None)
  }
}

///|
test "YAML highlights wait for both loaded sources" {
  for path in ["config.yaml", "config.yml"] {
    let initial = ready_test_file(
      fixture_file(path, "modified"),
      ["value: 1"],
      ["value: 2"],
    )
    for
      pending in [
        NotRequested,
        Loading,
        LoadFailed("retry"),
        CannotRender("binary", false),
      ] {
      for
        file in [
          { ..initial, old_side: pending, },
          { ..initial, new_side: pending, },
        ] {
        assert_true(
          ensure_file_document(file, LexicalAlgorithm).diff_cache.highlights
          is None,
        )
      }
    }
  }
}

///|
test "YAML span budgets apply independently to each file side" {
  let crowded = "[" + "0,".repeat(512) + "]\n"
  let full = "[" + "0,".repeat(511) + "]\n"
  let source = crowded + full.repeat(16) + "tail: true"
  for path in ["config.yaml", "config.yml"] {
    let highlights = file_highlights(path, path, source, source)
    for side in [highlights.old.unwrap(), highlights.new.unwrap()] {
      assert_true(side.line(1).is_empty())
      for line in 2..<=17 {
        assert_eq(side.line(line).length(), 1024)
      }
      assert_true(side.line(18).is_empty())
    }
  }
}
