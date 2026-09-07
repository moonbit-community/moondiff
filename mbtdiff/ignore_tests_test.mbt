///|
test "test file filtering matches only exact case-sensitive suffixes" {
  let old = "fn helper() { old_value() }"
  let new = "fn helper() { new_value() }"
  let options = @mbtdiff.DiffOptions(ignore_tests=true)
  for path in ["foo_test.mbt", "src/foo_wbtest.mbt", "_test.mbt", "_wbtest.mbt"] {
    let result = @mbtdiff.diff(old, new, old_name=path, options~)
    assert_true(result.status() is IgnoredOnly, msg=path)
    assert_true(result.ignore_reason() is Some(TestFile), msg=path)
  }
  for
    path in [
      "foo_tests.mbt", "foo_TEST.mbt", "foo_WBTEST.mbt", "foo_test.MBT", "foo_wbtest.Mbt",
      "foo.mbt", "foo_test.txt", "foo_test.mbt.bak", "foo_test.mbt/ordinary.mbt",
      "/dev/null", "",
    ] {
    let result = @mbtdiff.diff(old, new, old_name=path, options~)
    assert_true(result.status() is Changed, msg=path)
    assert_true(result.ignore_reason() is None, msg=path)
  }
}

///|
test "test file pairs ignore every source change before parsing or diffing" {
  let paths = [
    ("src/foo_test.mbt", "src/foo_test.mbt"),
    ("src/foo_wbtest.mbt", "src/foo_wbtest.mbt"),
    ("old_test.mbt", "new.mbt"),
    ("old.mbt", "new_wbtest.mbt"),
    ("old_wbtest.mbt", "new.txt"),
    ("old.txt", "new_test.mbt"),
    ("/dev/null", "new_test.mbt"),
    ("old_wbtest.mbt", "/dev/null"),
  ]
  let sources = [
    ("fn helper() { old_value() }", "fn helper() { new_value() }"),
    ("import { \"a/b\" } for \"test\"", "import { \"a/c\" } for \"test\""),
    ("fn broken( {", "fn broken( ["),
    ("", "fn added() { value() }"),
    ("fn deleted() { value() }", ""),
    ("// old comment", "// new comment"),
  ]
  let modes : Array[@mbtdiff.DiffMode] = [Ast, Lexical]
  for mode in modes {
    for ignore_comments in [false, true] {
      for paths in paths {
        let (old_name, new_name) = paths
        for sources in sources {
          let (old_source, new_source) = sources
          let result = @mbtdiff.diff(
            old_source,
            new_source,
            old_name~,
            new_name~,
            options=DiffOptions(
              ignore_tests=true,
              ignore_comments~,
              mode~,
              graph_limit=0,
            ),
          )
          assert_true(result.status() is IgnoredOnly)
          assert_true(result.ignore_reason() is Some(TestFile))
          guard result.document() is Whole(fragment) else {
            fail("expected an empty Whole document")
          }
          assert_true(fragment.document.hunks.is_empty())
          assert_true(fragment.fallbacks.is_empty())
        }
      }
    }
  }
}

///|
test "identical test file sources retain priority including invalid and empty input" {
  let modes : Array[@mbtdiff.DiffMode] = [Ast, Lexical]
  for mode in modes {
    for ignore_comments in [false, true] {
      for source in ["", "fn broken( {", "fn helper() { 1 }"] {
        let result = @mbtdiff.diff(
          source,
          source,
          old_name="old_test.mbt",
          new_name="new.txt",
          options=DiffOptions(ignore_tests=true, ignore_comments~, mode~),
        )
        assert_true(result.status() is Identical)
        assert_true(result.ignore_reason() is None)
        guard result.document() is Whole(fragment) else {
          fail("expected Whole")
        }
        assert_true(fragment.document.hunks.is_empty())
        assert_true(fragment.fallbacks.is_empty())
      }
    }
  }
}

///|
test "test file filtering is default off and requires a matching source name" {
  let old = "fn helper() { old_value() }"
  let new = "fn helper() { new_value() }"
  let modes : Array[@mbtdiff.DiffMode] = [Ast, Lexical]
  for mode in modes {
    for ignore_comments in [false, true] {
      for path in ["foo_test.mbt", "foo_wbtest.mbt"] {
        let result = @mbtdiff.diff(
          old,
          new,
          old_name=path,
          new_name=path,
          options=DiffOptions(ignore_comments~, mode~),
        )
        assert_true(result.status() is Changed)
        assert_true(result.ignore_reason() is None)
        assert_false(public_document_is_empty(result.document()))
      }
      let unnamed = @mbtdiff.diff(
        old,
        new,
        options=DiffOptions(ignore_tests=true, ignore_comments~, mode~),
      )
      assert_true(unnamed.status() is Changed)
      for
        path in [
          "foo_tests.mbt", "foo_TEST.mbt", "foo_WBTEST.mbt", "foo_test.MBT", "foo.mbt",
          "foo.txt",
        ] {
        let result = @mbtdiff.diff(
          old,
          new,
          old_name=path,
          new_name=path,
          options=DiffOptions(ignore_tests=true, ignore_comments~, mode~),
        )
        assert_true(result.status() is Changed, msg=path)
        assert_false(public_document_is_empty(result.document()))
      }
    }
  }
}

///|
test "ordinary and unnamed sources keep test block filtering and parse fallback" {
  let modes : Array[@mbtdiff.DiffMode] = [Ast, Lexical]
  for mode in modes {
    for ignore_comments in [false, true] {
      let options = @mbtdiff.DiffOptions(
        ignore_tests=true,
        ignore_comments~,
        mode~,
      )
      for paths in [("old", "new"), ("old.mbt", "new.mbt")] {
        let (old_name, new_name) = paths
        let blocks = @mbtdiff.diff(
          "test { old_value() }\nasync test { old_async() }",
          "test { new_value() }\nasync test { new_async() }",
          old_name~,
          new_name~,
          options~,
        )
        assert_true(blocks.status() is IgnoredOnly)
        assert_true(blocks.ignore_reason() is Some(FilteredContent))
        let imports = @mbtdiff.diff(
          "import { \"a/b\" } for \"test\"",
          "import { \"a/c\" } for \"test\"",
          old_name~,
          new_name~,
          options~,
        )
        assert_true(imports.status() is Changed)
        let broken = @mbtdiff.diff(
          "fn broken( {",
          "fn broken( [",
          old_name~,
          new_name~,
          options~,
        )
        assert_true(broken.status() is Changed)
        assert_true(broken.ignore_reason() is None)
        assert_true(public_fallbacks(broken.document()) is [ParseError(..)])
      }
    }
  }
}
