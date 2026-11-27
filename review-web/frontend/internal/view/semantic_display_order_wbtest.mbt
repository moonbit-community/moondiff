///|
fn display_order_fixture(
  old : Array[String],
  new : Array[String],
  hidden~ : Array[String] = [],
) -> @mbtdiff.TopLevelDiff {
  let names = old.copy()
  for name in new {
    if !names.contains(name) {
      names.push(name)
    }
  }
  let sections = names.map(name => {
    let diff : @mbtdiff.DiffFragment = {
      document: if hidden.contains(name) {
        { hunks: [], }
      } else {
        projection_document_fixture()
      },
      fallbacks: [],
    }
    let old_range = old
      .search(name)
      .map(start => @mbtdiff.LineRange::{ start, len: 1, })
    let new_range = new
      .search(name)
      .map(start => @mbtdiff.LineRange::{ start, len: 1, })
    match (old_range, new_range) {
      (Some(old), Some(new)) =>
        @mbtdiff.DiffSection::Matched(
          old~,
          new~,
          old_context=Some(name),
          new_context=Some(name),
          diff~,
        )
      (Some(old), None) => Deleted(old~, old_context=Some(name), diff~)
      (None, Some(new)) => Inserted(new~, new_context=Some(name), diff~)
      _ => panic()
    }
  })
  {
    sections: sections[:],
    old_order: old.map(name => names.search(name).unwrap())[:],
    new_order: new.map(name => names.search(name).unwrap())[:],
    reordered: old.filter(name => new.contains(name)) !=
    new.filter(name => old.contains(name)),
  }
}

///|
fn assert_display_order(
  old : Array[String],
  new : Array[String],
  expected : Array[String],
) -> Unit raise {
  let top = display_order_fixture(old, new)
  let order = semantic_display_order(top)
  assert_eq(
    order.map(i => {
      match semantic_section_old_context(top.sections[i]) {
        Some(name) => name
        None => semantic_section_new_context(top.sections[i]).unwrap()
      }
    }),
    expected,
  )
  assert_eq(order.length(), top.sections.length())
  for index in 0..<top.sections.length() {
    assert_eq(order.filter(i => i == index).length(), 1)
  }
  assert_eq(
    order.filter(i => !(top.sections[i] is Deleted(..))),
    top.new_order.to_owned(),
  )
}

///|
test "display order keeps deletions beside old neighbors and preserves new order" {
  for
    (old, new, expected) in [
      (["A", "D", "B"], ["A", "X", "B"], ["A", "D", "X", "B"]),
      (["D", "A"], ["X", "A"], ["X", "D", "A"]),
      (["A", "D", "B"], ["B", "A"], ["B", "A", "D"]),
      (["D1", "D2"], ["X1", "X2"], ["D1", "D2", "X1", "X2"]),
      ([], [], []),
      ([], ["X1", "X2"], ["X1", "X2"]),
      (["D1", "D2"], [], ["D1", "D2"]),
      (["A", "B"], ["B", "A"], ["B", "A"]),
      (["A", "D1", "D2", "B"], ["A", "X", "B"], ["A", "D1", "D2", "X", "B"]),
      (["D1", "D2", "A"], ["X", "A"], ["X", "D1", "D2", "A"]),
      (["A", "D1", "D2"], ["X", "A", "Y"], ["X", "A", "D1", "D2", "Y"]),
      (
        ["D0", "A", "D1", "B", "D2", "C", "D3"],
        ["A", "X", "B", "C"],
        ["D0", "A", "D1", "X", "B", "D2", "C", "D3"],
      ),
      // A's trailing run and B's leading run meet at the same display position.
      (
        ["D0", "B", "D1", "A", "D2", "C", "D3"],
        ["C", "A", "B"],
        ["C", "D3", "A", "D0", "D2", "B", "D1"],
      ),
    ] {
    assert_display_order(old, new, expected)
  }
}

///|
#warnings("-alert_unstable")
#skip("browser DOM: npm run test:views")
test "hidden anchors and collapsed sections retain display order and stable identities" {
  for
    (old, new, hidden, expected) in [
      (["A", "D", "B"], ["A", "X", "B"], ["A"], [1, 3, 2]),
      (["D", "A"], ["X", "A"], ["A"], [2, 0]),
      (["A", "D", "B"], ["B", "A"], ["A"], [2, 1]),
      (["A", "D", "B"], ["B", "A"], [], [2, 0, 1]),
    ] {
    let top = display_order_fixture(old, new, hidden~)
    let keys = semantic_section_keys(top.sections)
    for mode in [@change.Split, Unified] {
      for collapsed in [[], [keys[0]], keys] {
        let file = {
          ..ready_test_file(fixture_file("order.mbt", "modified"), [], []),
          collapsed_sections: collapsed,
        }
        let emit : @rabbita.Emit[Msg] = Emit(_ => @rabbita.none)
        let html = render_test_html(() => {
          top_level_diff_view(
            file,
            7,
            0,
            top,
            mode,
            false,
            @comments.Session::new().read_view(),
            emit,
          )
        })
        assert_false(html.contains("semantic-deleted-group"))
        assert_eq(html.contains("semantic-reorder"), top.reordered)
        assert_eq(
          html.split("class=\"semantic-section\"").count() - 1,
          expected.length(),
        )
        let mut last = -1
        for index in expected {
          let position = html.find("Section #\{index + 1} ·").unwrap()
          assert_true(position > last)
          last = position
          assert_true(html.contains("data-section-key=\"\{keys[index]}\""))
        }
        assert_eq(
          html.split("open=\"\"").count() - 1,
          expected.filter(i => !collapsed.contains(keys[i])).length(),
        )
      }
    }
  }
}
