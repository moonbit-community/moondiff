///|
fn projection_document_fixture() -> @model.HunkDocument {
  {
    hunks: [
      {
        old_start: 0,
        old_len: 1,
        new_start: 0,
        new_len: 1,
        blocks: [
          ChangeBlock([
            Paired({ index: 0, segments: [{ kind: Changed, text: "old", }], }, {
              index: 0,
              segments: [{ kind: Changed, text: "new", }],
            }),
          ]),
        ],
      },
    ],
  }
}

///|
test "same-line projection uses the first expanded matched inserted or deleted section" {
  let before = "let first = 11; let second = 22"
  let after = "let first = 33; let second = 44"
  for
    (old, new, patch, side) in [
      (before, after, "@@ -1 +1 @@\n-\{before}\n+\{after}", @review.Right),
      (
        "fn keep() {}",
        after + "\nfn keep() {}",
        "@@ -1 +1,2 @@\n+\{after}\n fn keep() {}",
        Right,
      ),
      (
        before + "\nfn keep() {}",
        "fn keep() {}",
        "@@ -1,2 +1 @@\n-\{before}\n fn keep() {}",
        Left,
      ),
    ] {
    let api = {
      ..fixture_file("same_line.mbt", "modified"),
      patch: Some(patch),
    }
    let reference = @github.commit_reference("owner", "repo", "head")
    let base = @change.finish_change(
      reference,
      None,
      { repository: { owner: "owner", repo: "repo", }, sha: "head", },
      "",
      "",
      { additions: 1, deletions: 1, total: 2, },
      [api],
    )
    for algorithm in [@change.LexicalAlgorithm, AstAlgorithm] {
      let file = ensure_file_document(
        ready_test_file(api, [old], [new]),
        algorithm,
      )
      guard cached_file_document(file, algorithm)
        is Some(MoonBit(document=TopLevel(top), ..)) else {
        fail("expected same-line declarations")
      }
      let visible = (if side is Left { top.old_order } else { top.new_order }).filter(i => {
          fragment_has_output(semantic_section_fragment(top.sections[i]))
        },
      )
      assert_eq(visible.length(), 2)
      let keys = semantic_section_keys(top.sections)
      let first = visible[0]
      let second = visible[1]
      for mode in [@change.Split, Unified] {
        for
          (collapsed, selected) in [
            ([], Some(first)),
            ([keys[first]], Some(second)),
            ([keys[second]], Some(first)),
            ([keys[first], keys[second]], None),
          ] {
          let view = {
            ..base,
            files: [{ ..file, collapsed_sections: collapsed, }],
          }
          let model = Model::{
            input: "",
            generation: 1,
            view_mode: mode,
            diff_algorithm: algorithm,
            ignore_comments: false,
            ignore_tests: false,
            phase: Showing(view),
            route: Some(reference),
            file_tree: test_file_tree_state(),
            auth: Anonymous(None),
            auth_revision: 0,
            restore_pending: false,
            last_authenticated_user_id: None,
            review: @comments.Session::new(),
          }
          let projection = review_projection(view, model)
          let key = discussion_key(0, side, 1)
          let expected = selected.map(i => "0:section:\{i}:0:0:0")
          assert_eq(projection.lines.get(key), expected)
          assert_eq(projection.editors.get(key), expected)
          if selected is None {
            assert_true(projection.lines.is_empty())
            assert_true(projection.editors.is_empty())
          }
        }
      }
    }
  }
}

///|
test "projection chooses the first visible occurrence independently of rendering" {
  let file = {
    ..fixture_file("a.txt", "modified"),
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  }
  for mode in [@change.Split, Unified] {
    let projection = ReviewProjection::{ lines: Map([]), editors: Map([]), }
    project_document(
      projection,
      file,
      0,
      projection_document_fixture(),
      mode,
      0,
      0,
      fragment="first",
    )
    project_document(
      projection,
      file,
      0,
      projection_document_fixture(),
      mode,
      0,
      0,
      fragment="second",
    )
    for side in [@review.Left, Right] {
      let key = discussion_key(0, side, 1)
      assert_eq(projection.lines.get(key), Some("0:first:0:0:0"))
      assert_eq(projection.editors.get(key), Some("0:first:0:0:0"))
    }
    let item = InlineDiscussion::{
      id: ReviewComment(1L),
      file_index: Some(0),
      anchor: Some({ path: "a.txt", side: Right, line: 1, position: Some(2), }),
      location: "a.txt",
      outdated: false,
      content: @html.div("thread"),
    }
    let discussions = {
      ..empty_discussions(),
      projection,
      items: [item],
      index: Map([(discussion_key(0, Right, 1), [item])]),
    }
    // Render second first: it still cannot claim the discussion.
    assert_eq(
      inline_cards(discussions, 0, Some(1), Some(1), 4, "0:second:0:0:0").length(),
      0,
    )
    let first = inline_cards(
      discussions,
      0,
      Some(1),
      Some(1),
      4,
      "0:first:0:0:0",
    )
    let repeated = inline_cards(
      discussions,
      0,
      Some(1),
      Some(1),
      4,
      "0:first:0:0:0",
    )
    assert_eq(first.length(), 1)
    assert_eq(first[0].0, repeated[0].0)
    assert_eq(projection.lines.length(), 2)
  }
}

///|
#warnings("-alert_unstable")
test "projection source identity does not depend on hunk headings" {
  let file = {
    ..fixture_file("a.txt", "modified"),
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  }
  let projection = ReviewProjection::{ lines: Map([]), editors: Map([]), }
  let document = projection_document_fixture()
  project_document(projection, file, 0, document, Split, 0, 0)
  let anchor = ReviewAnchor::{
    path: "a.txt",
    side: Right,
    line: 1,
    position: Some(2),
  }
  let reference = @github.commit_reference("owner", "repo", "head")
  let (session, _) = @comments.update(
    @comments.Session::new(enabled=true),
    ContextChanged({
      generation: 1,
      route: Some(reference),
      snapshot: Some({ reference, sha: "head", pull_snapshot: None, }),
      enabled: true,
    }),
  )
  let (session, _) = @comments.update(session, Identity(true, Some("me")))
  let (session, _) = @comments.update(session, OpenInlineDraft(0, anchor))
  let discussions = { ..empty_discussions(), projection, }
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for headers in [false, true] {
    let html = safe_review_diff(
      file,
      0,
      document,
      Split,
      session,
      emit,
      show_hunk_headers=headers,
      discussions~,
    )
    let rendered = @rabbita.render_to_string(() => @rabbita.Val::constant(html))
    assert_true(rendered.contains("inline-comment-editor-row"))
  }
}

///|
#warnings("-alert_unstable")
test "projection omits collapsed filtered and structural-placeholder documents" {
  let api = {
    ..fixture_file("a.mbt", "modified"),
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  }
  let reference = @github.commit_reference("owner", "repo", "head")
  let repository = @github.RepositoryRef::{ owner: "owner", repo: "repo", }
  let base_view = @change.finish_change(
    reference,
    None,
    { repository, sha: "head", },
    "",
    "",
    { additions: 1, deletions: 1, total: 2, },
    [api],
  )
  for
    (algorithm, status, expanded, visible) in [
      (@change.AstAlgorithm, @model.NoStructuralChanges, true, false),
      (LexicalAlgorithm, NoStructuralChanges, true, true),
      (LexicalAlgorithm, IgnoredOnly, true, false),
      (LexicalAlgorithm, Changed, false, false),
    ] {
    let base_file = ready_test_file(api, ["old"], ["new"], expanded~)
    let file = {
      ..base_file,
      diff_cache: base_file.diff_cache.put(
        MoonBit(algorithm, false, false),
        MoonBit(
          document=Whole({
            document: projection_document_fixture(),
            fallbacks: [],
          }),
          status~,
          ignore_reason=None,
        ),
      ),
    }
    let view = { ..base_view, files: [file], }
    let model = Model::{
      input: "",
      generation: 1,
      view_mode: Split,
      diff_algorithm: algorithm,
      ignore_comments: false,
      ignore_tests: false,
      phase: Showing(view),
      route: Some(reference),
      file_tree: test_file_tree_state(),
      auth: Anonymous(None),
      auth_revision: 0,
      restore_pending: false,
      last_authenticated_user_id: None,
      review: @comments.Session::new(),
    }
    let projection = review_projection(view, model)
    assert_eq(!projection.lines.is_empty(), visible)
    let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
    let html = @rabbita.render_to_string(() => {
      @rabbita.Val::constant(file_list_view(view, model, emit))
    })
    assert_eq(html.contains("<table"), visible)
  }
}

///|
#warnings("-alert_unstable")
test "source rows precede both sides of discussion and the selected editor" {
  let file = {
    ..fixture_file("a.txt", "modified"),
    patch: Some("@@ -1 +1 @@\n-old\n+new"),
  }
  let reference = @github.commit_reference("owner", "repo", "head")
  let (session, _) = @comments.update(
    @comments.Session::new(enabled=true),
    ContextChanged({
      generation: 1,
      route: Some(reference),
      snapshot: Some({ reference, sha: "head", pull_snapshot: None, }),
      enabled: true,
    }),
  )
  let (session, _) = @comments.update(session, Identity(true, Some("me")))
  let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
  for mode in [@change.Split, Unified] {
    let projection = ReviewProjection::{ lines: Map([]), editors: Map([]), }
    project_document(
      projection,
      file,
      0,
      projection_document_fixture(),
      mode,
      0,
      0,
    )
    let discussions = { ..empty_discussions(), projection, }
    for (id, side) in [(1L, @review.Left), (2L, Right), (3L, Right)] {
      let anchor = ReviewAnchor::{
        path: "a.txt",
        side,
        line: 1,
        position: Some(if side is Left { 1 } else { 2 }),
      }
      let item = InlineDiscussion::{
        id: ReviewComment(id),
        file_index: Some(0),
        anchor: Some(anchor),
        location: anchor_location(anchor),
        outdated: false,
        content: @html.div("Comment \{id}"),
      }
      let key = discussion_key(0, side, 1)
      match discussions.index.get(key) {
        Some(items) => items.push(item)
        None => discussions.index[key] = [item]
      }
    }
    for side in [@review.Left, Right] {
      let anchor = ReviewAnchor::{
        path: "a.txt",
        side,
        line: 1,
        position: Some(if side is Left { 1 } else { 2 }),
      }
      let (session, _) = @comments.update(session, OpenInlineDraft(0, anchor))
      let html = safe_review_diff(
        file,
        0,
        projection_document_fixture(),
        mode,
        session,
        emit,
        discussions~,
      )
      let rendered = @rabbita.render_to_string(() => {
        @rabbita.Val::constant(html)
      })
      let old_code = rendered.find("old</b>").unwrap()
      let new_code = rendered.find("new</b>").unwrap()
      let left = rendered.find("Comment 1").unwrap()
      let right = rendered.find("Comment 2").unwrap()
      let second = rendered.find("Comment 3").unwrap()
      let editor = rendered.find("inline-comment-editor-row").unwrap()
      assert_true(old_code < left)
      assert_true(new_code < right && right < second)
      assert_true(
        if mode is Split || side is Right {
          second < editor
        } else {
          left < editor && editor < new_code
        },
      )
      assert_true(rendered.contains("inline-discussion inline-left"))
      assert_true(rendered.contains("inline-discussion inline-right"))
    }
  }
}
