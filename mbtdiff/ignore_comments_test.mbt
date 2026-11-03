///|
let attribute_docs : Array[String] = [
  "///|", "/// Creates a view of a portion of the array.",
]

///|
let attribute_line : String = "#intrinsic(\"%array.get_view\")"

///|
fn attribute_source(with_attribute : Bool) -> String {
  let lines = attribute_docs.copy()
  if with_attribute {
    lines.push(attribute_line)
  }
  lines.push_iter(
    [
      "pub fn[T] Array::get_view(", "  self : Array[T],", "  start~ : Int = 0,",
      "  end? : Int,", ") -> ArrayView[T]? {", "  let len = self.length()", "  let end = end.unwrap_or(len)",
      "  guard start >= 0 && start <= end && end <= len else { None }", "  Some(self[start:end])",
      "}",
    ].iter(),
  )
  lines.join("\n")
}

///|
fn assert_attribute_rows(
  document : @mbtdiff.HunkDocument,
  reverse : Bool,
  ignore_comments : Bool,
) -> Unit raise {
  let paired_docs : Array[String] = []
  let changes : Array[String] = []
  let old_indexes : Array[Int32] = []
  let new_indexes : Array[Int32] = []
  for hunk in document.hunks {
    for block in hunk.blocks {
      match block {
        ContextBlock(lines) =>
          for line in lines {
            old_indexes.push(line.old_index)
            new_indexes.push(line.new_index)
            if attribute_docs.contains(line.text) {
              assert_false(ignore_comments)
              paired_docs.push(line.text)
            }
          }
        ChangeBlock(rows) | IgnoredBlock(rows) =>
          for row in rows {
            match row {
              Paired(old, new) => {
                old_indexes.push(old.index)
                new_indexes.push(new.index)
                assert_eq(old.text(), new.text())
                for line in [old, new] {
                  assert_true(line.segments.all(s => s.kind != Changed))
                }
                if attribute_docs.contains(old.text()) {
                  paired_docs.push(old.text())
                  if ignore_comments {
                    assert_true(block is IgnoredBlock(_))
                    assert_true(old.segments.all(s => s.kind is Ignored))
                    assert_true(new.segments.all(s => s.kind is Ignored))
                  }
                }
              }
              OldOnly(line) | NewOnly(line) => {
                assert_true(block is ChangeBlock(_))
                assert_eq(line.text(), attribute_line)
                assert_eq(row is OldOnly(_), reverse)
                changes.push(line.text())
                if reverse {
                  old_indexes.push(line.index)
                } else {
                  new_indexes.push(line.index)
                }
              }
            }
          }
      }
    }
  }
  assert_eq(paired_docs, attribute_docs)
  assert_eq(changes, [attribute_line])
  assert_eq(old_indexes, [ for i in 0..<(if reverse { 13 } else { 12 }) => i ])
  assert_eq(new_indexes, [ for i in 0..<(if reverse { 12 } else { 13 }) => i ])
}

///|
test "attribute changes keep shared documentation paired in matched AST and lexical sections" {
  for mode in [@mbtdiff.Ast, Lexical] {
    for ignore_comments in [false, true] {
      for ignore_tests in [false, true] {
        for reverse in [false, true] {
          let result = @mbtdiff.diff(
            attribute_source(reverse),
            attribute_source(!reverse),
            options=DiffOptions(
              mode~,
              ignore_comments~,
              ignore_tests~,
              context_lines=100,
            ),
          )
          assert_true(result.status() is Changed)
          guard result.document()
            is TopLevel({ sections: [Matched(diff~, ..)], .. }) else {
            fail("attribute changes must retain one matched declaration")
          }
          assert_true(diff.fallbacks.is_empty())
          assert_attribute_rows(diff.document, reverse, ignore_comments)
        }
      }
    }
  }
}

///|
test "attribute comment alignment survives ignored tests and graph limit fallback" {
  for mode in [@mbtdiff.Ast, Lexical] {
    for graph_limit in [0U, 30000U] {
      for reverse in [false, true] {
        let result = @mbtdiff.diff(
          attribute_source(reverse) + "\ntest { old_test() }",
          attribute_source(!reverse) + "\ntest { new_test() }",
          options=DiffOptions(
            mode~,
            graph_limit~,
            ignore_comments=true,
            ignore_tests=true,
            context_lines=100,
          ),
        )
        assert_true(result.status() is Changed)
        guard result.document()
          is TopLevel({ sections: [Matched(diff~, ..)], .. }) else {
          fail(
            "expected the matched production declaration with tests filtered",
          )
        }
        if mode is Ast && graph_limit == 0 {
          assert_true(diff.fallbacks is [GraphLimitExceeded(limit=0)])
        } else {
          assert_true(diff.fallbacks.is_empty())
        }
        assert_attribute_rows(diff.document, reverse, true)
      }
    }
  }
}

///|
test "attribute comment alignment survives whole file parse fallback" {
  for mode in [@mbtdiff.Ast, Lexical] {
    for reverse in [false, true] {
      let result = @mbtdiff.diff(
        attribute_source(reverse) + " fn broken(",
        attribute_source(!reverse) + " fn broken(",
        options=DiffOptions(mode~, ignore_comments=true, context_lines=100),
      )
      assert_true(result.status() is Changed)
      guard result.document() is Whole(diff) else {
        fail("expected whole file parse fallback")
      }
      assert_true(diff.fallbacks is [ParseError(..)])
      assert_attribute_rows(diff.document, reverse, true)
    }
  }
}
