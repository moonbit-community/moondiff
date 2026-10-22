///|
extern "js" fn read_fixture(path : String) -> String =
  #| (path) => require("node:fs").readFileSync(path, "utf8")

///|
fn[T : @json.FromJson] decode_fixture(body : String) -> T raise {
  @json.from_json(@json.parse(body))
}

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
test "without interfaces the first twenty MoonBit files auto-load in original order" {
  let fixture : ApiCommit = decode_fixture(
    read_fixture("testdata/github/root_commit.json"),
  )
  let files : Array[ApiFile] = []
  files.push(fixture_file("README.md", "added"))
  files.push(fixture_file("moon.mod", "added"))
  files.push(fixture_file("src/moon.pkg", "added"))
  files.push(fixture_file("build.mbtx", "added"))
  files.push(fixture_file("scripts/build.mbtx", "added"))
  files.push(
    fixture_file(
      "scripts/build.txt",
      "renamed",
      previous_filename="scripts/build.mbtx",
    ),
  )
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
  assert_false(view.files[0].expanded)
  assert_true(view.files[0].new_side is NotRequested)
  for state in view.files[1:6] {
    assert_true(state.diff_mode is LineDiff)
    assert_true(state.expanded)
    assert_true(state.old_side is Ready([]))
    assert_true(state.new_side is Loading)
  }
  let mut auto_load_index = 5
  for state in view.files[6:] {
    match state.diff_mode {
      MoonBitDiff => {
        if auto_load_index < 20 {
          assert_true(state.expanded, msg=state.file.filename)
          assert_true(state.old_side is Ready([]), msg=state.file.filename)
          assert_true(state.new_side is Loading, msg=state.file.filename)
        } else {
          assert_false(state.expanded, msg=state.file.filename)
          assert_true(state.new_side is NotRequested, msg=state.file.filename)
        }
        auto_load_index += 1
      }
      LineDiff => {
        assert_false(state.expanded, msg=state.file.filename)
        assert_true(state.new_side is NotRequested, msg=state.file.filename)
      }
    }
  }
  assert_eq(auto_load_index, 26)
}

///|
test "interfaces from either rename path lead a stable global partition" {
  let files = [
    fixture_file("README.md", "modified"),
    fixture_file("z/main.mbt", "modified"),
    fixture_file("z/deep/pkg.generated.mbti", "modified"),
    fixture_file("moon.pkg", "modified"),
    fixture_file("pkg.generated.mbti", "added"),
    fixture_file("a/tail.mbtx", "modified"),
    fixture_file(
      "archive/interface.txt",
      "renamed",
      previous_filename="old/pkg.generated.mbti",
    ),
    fixture_file("deleted/pkg.generated.mbti", "removed"),
    fixture_file(
      "new/pkg.generated.mbti",
      "renamed",
      previous_filename="old/interface.txt",
    ),
  ]
  let original = files.map(file => file.filename)
  let reference = commit_reference("example", "repo", "a".repeat(40))
  let repository = reference_repository(reference)
  let view = finish_change(
    reference,
    Some({ repository, sha: "b".repeat(40), }),
    { repository, sha: "a".repeat(40), },
    "",
    "",
    { additions: 0, deletions: 0, total: 0, },
    files,
  )
  assert_eq(view.total_files, files.length())
  assert_eq(files.map(file => file.filename), original)
  assert_eq(view.files.map(state => state.file.filename), [
    "z/deep/pkg.generated.mbti", "pkg.generated.mbti", "archive/interface.txt", "deleted/pkg.generated.mbti",
    "new/pkg.generated.mbti", "README.md", "z/main.mbt", "moon.pkg", "a/tail.mbtx",
  ])
  for state in view.files[:5] {
    assert_true(state.expanded)
    assert_true(state.diff_mode is LineDiff)
  }
  assert_true(view.files[1].old_side is Ready([]))
  assert_true(view.files[1].new_side is Loading)
  assert_true(view.files[3].old_side is Loading)
  assert_true(view.files[3].new_side is Ready([]))
  let renamed = source_requests_for_file(view, 2)
  assert_eq(renamed.map(request => request.1.path), [
    "old/pkg.generated.mbti", "archive/interface.txt",
  ])
  let renamed = source_requests_for_file(view, 4)
  assert_eq(renamed.map(request => request.1.path), [
    "old/interface.txt", "new/pkg.generated.mbti",
  ])
}

///|
test "interface expansion uses twenty anonymous slots and an explicit signed-in policy" {
  let fixture : ApiCommit = decode_fixture(
    read_fixture("testdata/github/root_commit.json"),
  )
  let reference = commit_reference("example", "root", fixture.sha)
  for count in [0, 1, 19, 20, 21, 35] {
    for expand_all_interfaces in [false, true] {
      let files = Array::makei(25, index => {
        fixture_file("src/file\{index}.mbt", "added")
      })
      for index in 0..<count {
        files.push(fixture_file("pkg\{index}/pkg.generated.mbti", "added"))
      }
      let view = finish_commit(
        reference,
        reference_repository(reference),
        fixture,
        files,
        expand_all_interfaces~,
      )
      for index, state in view.files {
        let expanded = (expand_all_interfaces && index < count) || index < 20
        assert_eq(state.expanded, expanded, msg=state.file.filename)
        assert_true(state.old_side is Ready([]))
        assert_eq(state.new_side is Loading, expanded)
        assert_eq(state.new_side is NotRequested, !expanded)
      }
      assert_eq(
        view.files.filter(state => state.expanded).length(),
        if expand_all_interfaces {
          Int32::max(20, count)
        } else {
          20
        },
      )
    }
  }
}

///|
test "anonymous mixed interface changes use at most forty initial source sides" {
  let reference = commit_reference("example", "root", "a".repeat(40))
  for count in [19, 20, 21, 35] {
    let files = Array::makei(count, index => {
      fixture_file("pkg\{index}/pkg.generated.mbti", "modified")
    })
    for status in ["added", "removed", "renamed", "modified"] {
      let files = files.map(file => {
        ..file,
        status,
        previous_filename: if status == "renamed" {
          Some("old/" + file.filename)
        } else {
          None
        },
      })
      let view = finish_change(
        reference,
        Some({
          repository: reference_repository(reference),
          sha: "b".repeat(40),
        }),
        { repository: reference_repository(reference), sha: "a".repeat(40), },
        "",
        "",
        { additions: 1, deletions: 1, total: 2, },
        files,
      )
      assert_eq(
        view.files.filter(file => file.expanded).length(),
        Int32::min(20, count),
      )
      let mut sides = 0
      for index, file in view.files {
        if file.expanded {
          sides += source_requests_for_file(view, index).length()
        }
      }
      assert_eq(
        sides,
        Int32::min(20, count) *
        (if status == "added" || status == "removed" { 1 } else { 2 }),
      )
    }
  }
}

///|
fn ready_test_file(
  file : ApiFile,
  old : Array[String],
  new : Array[String],
  expanded~ : Bool = true,
) -> FileState {
  {
    file,
    diff_mode: file_diff_mode(file),
    expanded,
    manually_collapsed: false,
    collapsed_sections: [],
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
test "test file caches use both rename paths and restore unfiltered results" {
  for
    file in [
      fixture_file("src/helper_test.mbt", "modified"),
      fixture_file("src/helper_wbtest.mbt", "added"),
      fixture_file("src/deleted_test.mbt", "removed"),
      fixture_file(
        "src/ordinary.mbt",
        "renamed",
        previous_filename="src/old_test.mbt",
      ),
      fixture_file(
        "src/ordinary.txt",
        "renamed",
        previous_filename="src/old_wbtest.mbt",
      ),
      fixture_file(
        "src/new_test.mbt",
        "renamed",
        previous_filename="src/old.txt",
      ),
    ] {
    let old = if file.status == "added" { [] } else { ["fn broken( {"] }
    let new = if file.status == "removed" { [] } else { ["fn broken( ["] }
    let mut cached = ready_test_file(file, old, new)
    let algorithms : Array[DiffAlgorithm] = [LexicalAlgorithm, AstAlgorithm]
    for algorithm in algorithms {
      for ignore_comments in [false, true] {
        cached = ensure_file_document(cached, algorithm, ignore_comments~)
        let original = cached_file_document(cached, algorithm, ignore_comments~)
        assert_true(original is Some(MoonBit(status=Changed, ..)))
        cached = ensure_file_document(
          cached,
          algorithm,
          ignore_comments~,
          ignore_tests=true,
        )
        guard cached_file_document(
            cached,
            algorithm,
            ignore_comments~,
            ignore_tests=true,
          )
          is Some(
            MoonBit(
              document=Whole(fragment),
              status=IgnoredOnly,
              ignore_reason=Some(TestFile)
            )
          ) else {
          fail("expected ignored test-file cache for \{file.filename}")
        }
        assert_true(fragment.document.hunks.is_empty())
        assert_true(fragment.fallbacks.is_empty())
        assert_true(cached.expanded)
        assert_true(cached.file == file)
        cached = ensure_file_document(cached, algorithm, ignore_comments~)
        assert_true(
          cached_file_document(cached, algorithm, ignore_comments~) == original,
        )
      }
    }
  }
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
