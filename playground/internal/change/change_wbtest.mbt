///|
extern "js" fn read_fixture(path : String) -> String =
  #| (path) => require("node:fs").readFileSync(path, "utf8")

///|
fn fixture_file(
  filename : String,
  status : String,
  previous_filename? : String,
) -> ApiFile {
  {
    filename,
    previous_filename,
    status,
    additions: 1,
    deletions: 2,
    changes: 3,
    patch: None,
  }
}

///|
test "all files remain listed but only the first twenty MoonBit diffs auto-load" {
  let fixture = decode_commit(read_fixture("testdata/github/root_commit.json"))
  let files : Array[ApiFile] = []
  files.push(fixture_file("README.md", "added"))
  for index in 0..<21 {
    if index == 5 {
      files.push(
        fixture_file(
          "src/file_5.txt",
          "renamed",
          previous_filename="src/file_5.mbt",
        ),
      )
    } else {
      files.push(fixture_file("src/file_\{index}.mbt", "added"))
    }
    if index == 9 {
      files.push(fixture_file("assets/logo.bin", "added"))
    }
  }
  let reference = commit_reference("example", "root", fixture.sha)
  let view = finish_commit(
    reference,
    reference_repository(reference),
    fixture,
    files,
  )
  assert_eq(view.files.length(), files.length())
  assert_eq(
    view.files.map(state => state.file.filename),
    files.map(file => file.filename),
  )
  let mut moonbit_index = 0
  for state in view.files {
    match state.diff_mode {
      MoonBitDiff => {
        if moonbit_index < 20 {
          assert_true(state.expanded, msg=state.file.filename)
          assert_true(state.old_side is Ready([]), msg=state.file.filename)
          assert_true(state.new_side is Loading, msg=state.file.filename)
        } else {
          assert_false(state.expanded, msg=state.file.filename)
          assert_true(state.new_side is NotRequested, msg=state.file.filename)
        }
        moonbit_index += 1
      }
      LineDiff => {
        assert_false(state.expanded, msg=state.file.filename)
        assert_true(state.new_side is NotRequested, msg=state.file.filename)
      }
    }
  }
  assert_eq(moonbit_index, 21)
}

///|
fn ready_test_file(
  file : ApiFile,
  old : Array[String],
  new : Array[String],
  expanded? : Bool = true,
) -> FileState {
  {
    file,
    diff_mode: file_diff_mode(file),
    expanded,
    old_side: Ready(old),
    new_side: Ready(new),
    diff_cache: DiffCache::empty(),
  }
}

///|
fn all_moonbit_cache_keys() -> Array[CacheKey] {
  [
    MoonBit(LexicalAlgorithm, false, false),
    MoonBit(LexicalAlgorithm, true, false),
    MoonBit(LexicalAlgorithm, false, true),
    MoonBit(LexicalAlgorithm, true, true),
    MoonBit(AstAlgorithm, false, false),
    MoonBit(AstAlgorithm, true, false),
    MoonBit(AstAlgorithm, false, true),
    MoonBit(AstAlgorithm, true, true),
  ]
}

///|
test "DiffCache put preserves old caches and overwrites only the matching key" {
  let line_key = CacheKey::Line
  let moonbit_key = CacheKey::MoonBit(LexicalAlgorithm, false, false)
  guard calculate_file_document(
      ready_test_file(fixture_file("README.md", "modified"), ["old"], ["first"]),
      line_key,
    )
    is Some(first) else {
    fail("expected first line result")
  }
  guard calculate_file_document(
      ready_test_file(fixture_file("CHANGELOG.md", "modified"), ["old"], [
        "replacement",
      ]),
      line_key,
    )
    is Some(replacement) else {
    fail("expected replacement line result")
  }
  guard calculate_file_document(
      ready_test_file(
        fixture_file("src/cache.mbt", "modified"),
        ["fn value() { old() }"],
        ["fn value() { new() }"],
      ),
      moonbit_key,
    )
    is Some(moonbit) else {
    fail("expected MoonBit result")
  }
  let original = DiffCache::empty()
  let with_line = original.put(line_key, first)
  let with_both = with_line.put(moonbit_key, moonbit)
  let overwritten = with_both.put(line_key, replacement)
  assert_true(original.get(line_key) is None)
  assert_true(original.get(moonbit_key) is None)
  assert_true(with_line.get(line_key) == Some(first))
  assert_true(with_line.get(moonbit_key) is None)
  assert_true(with_both.get(line_key) == Some(first))
  assert_true(with_both.get(moonbit_key) == Some(moonbit))
  assert_true(overwritten.get(line_key) == Some(replacement))
  assert_true(overwritten.get(moonbit_key) == Some(moonbit))
  assert_true(with_both.get(line_key) == Some(first))
}

///|
test "MoonBit files cache all eight algorithm and filter combinations" {
  let file = fixture_file("src/filters.mbt", "modified")
  let mut cached = ready_test_file(
    file,
    [
      "/// old docs", "fn production() { old_value() }", "test \"sample\" { old_test() }",
    ],
    [
      "/// new docs", "fn production() { new_value() }", "test \"sample\" { new_test() }",
    ],
  )
  let algorithms : Array[DiffAlgorithm] = [LexicalAlgorithm, AstAlgorithm]
  for algorithm in algorithms {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        let key = CacheKey::MoonBit(algorithm, ignore_comments, ignore_tests)
        assert_true(cached.diff_cache.get(key) is None)
        cached = ensure_file_document(
          cached,
          algorithm,
          ignore_comments~,
          ignore_tests~,
        )
        assert_true(cached.diff_cache.get(key) is Some(_))
      }
    }
  }
  for key in all_moonbit_cache_keys() {
    assert_true(cached.diff_cache.get(key) is Some(_))
  }
  assert_true(cached.diff_cache.get(Line) is None)
}

///|
test "non-MoonBit line document is shared across algorithm switches" {
  let file = fixture_file("README.md", "modified")
  let line_key = CacheKey::Line
  let cached = ensure_file_document(
    ready_test_file(file, ["old"], ["new"]),
    LexicalAlgorithm,
  )
  guard cached.diff_cache.get(line_key) is Some(before) else {
    fail("expected line cache")
  }
  let after = ensure_file_document(
    cached,
    AstAlgorithm,
    ignore_comments=true,
    ignore_tests=true,
  )
  assert_true(after.diff_cache == cached.diff_cache)
  assert_true(after.diff_cache.get(line_key) == Some(before))
  for key in all_moonbit_cache_keys() {
    assert_true(after.diff_cache.get(key) is None)
  }
}
