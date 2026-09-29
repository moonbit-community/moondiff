///|
test "Dockerfile routing matches VS Code filenames case-sensitively" {
  let accepted = [
    "Dockerfile", "Containerfile", "src/Dockerfile", "containers/Containerfile",
    "Dockerfile.dev", "src/Dockerfile.linux.arm64", "Containerfile.test", "src/service.dockerfile",
    "src/service.containerfile",
  ]
  let rejected = [
    ".dockerignore", "dockerfile", "CONTAINERFILE", "src/dockerfile.dev", "src/ContainerFile.dev",
    "src/service.Dockerfile", "src/service.Containerfile", "src/Dockerfiledev", "src/Containerfiletest",
    "src/Dockerfile.txt/docker.txt",
  ]
  for path in accepted {
    let highlights = source_highlights(path, "FROM alpine AS build").unwrap()
    assert_eq(highlights.line(1)[0].kind, Keyword)
    assert_eq(highlights.line(1)[1].kind, Control)
  }
  for path in rejected {
    assert_true(source_highlights(path, "FROM alpine AS build") is None)
  }
}

///|
test "Dockerfile old and new rename sides select languages independently" {
  for
    (old_path, new_path, old_source, new_source, old_kind, new_kind) in [
      (
        "Dockerfile",
        "src/code.c",
        "FROM alpine",
        "int value = 2;",
        @highlight.Keyword,
        @highlight.Type,
      ),
      (
        "src/code.mbt",
        "Containerfile.dev",
        "let value = 1",
        "RUN echo ok",
        Keyword,
        Keyword,
      ),
      (
        "src/plain.txt",
        "src/app.dockerfile",
        "FROM fake",
        "FROM scratch",
        Comment,
        Keyword,
      ),
    ] {
    let highlights = file_highlights(old_path, new_path, old_source, new_source)
    if old_path == "src/plain.txt" {
      assert_true(highlights.old is None)
    } else {
      assert_eq(highlights.old.unwrap().line(1)[0].kind, old_kind)
    }
    assert_eq(highlights.new.unwrap().line(1)[0].kind, new_kind)
  }
}

///|
test "Dockerfile additions deletions and option changes reuse cached highlights" {
  for
    file in [
      fixture_file("Dockerfile", "added"),
      fixture_file("src/app.containerfile", "removed"),
      fixture_file(
        "Containerfile.dev",
        "renamed",
        previous_filename="Dockerfile.old",
      ),
    ] {
    let old = if file.status == "added" { [] } else { ["FROM alpine AS old"] }
    let new = if file.status == "removed" { [] } else { ["FROM alpine AS new"] }
    let initial = ready_test_file(file, old, new)
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
  }
}
