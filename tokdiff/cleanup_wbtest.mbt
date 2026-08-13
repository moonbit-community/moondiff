// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
fn cleanup_op_signature(ops : ArrayView[Op]) -> String {
  ops
  .map(op => {
    match op {
      OEq(t) => "=\{t.text}"
      OSub(a, b) => "~\{a.text}>\{b.text}"
      ODel(t) => "-\{t.text}"
      OIns(t) => "+\{t.text}"
    }
  })
  .join("|")
}

///|
fn reconstruct_ops(ops : ArrayView[Op]) -> (String, String) {
  let old = StringBuilder::new()
  let new = StringBuilder::new()
  for op in ops {
    match op {
      OEq(t) => {
        old <+ "\{t.text}"
        new <+ "\{t.text}"
      }
      OSub(a, b) => {
        old <+ "\{a.text}"
        new <+ "\{b.text}"
      }
      ODel(t) => old <+ "\{t.text}"
      OIns(t) => new <+ "\{t.text}"
    }
  }
  (old.to_string(), new.to_string())
}

///|
fn ops_cost(ops : ArrayView[Op]) -> Int {
  let mut cost = 0
  for op in ops {
    cost += match op {
      OEq(_) => 0
      OSub(a, b) => subst_cost(a, b).unwrap()
      ODel(t) | OIns(t) => alignment_weight(t)
    }
  }
  cost
}

///|
fn changed_spans(ops : ArrayView[Op]) -> Array[(String, String)] {
  let spans : Array[(String, String)] = []
  let old_text : Array[String] = []
  let new_text : Array[String] = []
  let mut changed = false
  fn flush() {
    if changed {
      spans.push((old_text.join(""), new_text.join("")))
      old_text.clear()
      new_text.clear()
      changed = false
    }
  }

  for op in ops {
    match op {
      OEq(_) => flush()
      OSub(a, b) => {
        changed = true
        old_text.push(a.text)
        new_text.push(b.text)
      }
      ODel(t) => {
        changed = true
        old_text.push(t.text)
      }
      OIns(t) => {
        changed = true
        new_text.push(t.text)
      }
    }
  }
  flush()
  spans
}

///|
test "global traceback places repeated edits at natural right boundary" {
  let repeated_old = tokenize_line("x x")
  let repeated_new = tokenize_line("x")
  inspect(
    cleanup_op_signature(pair_ops_min(repeated_old, repeated_new)),
    content="=x|- |-x",
  )
  inspect(
    cleanup_op_signature(pair_ops(repeated_old, repeated_new)),
    content="=x|- |-x",
  )
  inspect(
    cleanup_op_signature(
      pair_ops(tokenize_line("// foo foo"), tokenize_line("// foo")),
    ),
    content="=//|= |=foo|- |-foo",
  )
  inspect(
    cleanup_op_signature(
      pair_ops(tokenize_line("f((x))"), tokenize_line("f(x)")),
    ),
    content="=f|=(|-(|=x|=)|-)",
  )
}

///|
test "global traceback keeps call parentheses and isolates the insertion" {
  let old = "    match candidate.normalized_expr_identifier_name() {"
  let new = "    if candidate.normalized_expr_identifier_name() is Some(candidate_name) {"
  let old_toks = tokenize_line(old)
  let new_toks = tokenize_line(new)
  let ops = pair_ops(old_toks, new_toks)
  assert_eq(reconstruct_ops(ops), (old, new))
  assert_eq(ops_cost(ops), wdist(old_toks, new_toks))
  assert_eq(changed_spans(ops), [
    ("match", "if"),
    ("", " is Some(candidate_name)"),
  ])
  let equal_call_parentheses : Array[String] = []
  let mut before_insertion = true
  for op in ops {
    match op {
      OIns(_) => before_insertion = false
      OEq(t) if before_insertion && (t.text == "(" || t.text == ")") =>
        equal_call_parentheses.push(t.text)
      _ => ()
    }
  }
  assert_eq(equal_call_parentheses, ["(", ")"])
}

///|
test "token boundary score follows the language-aware priority table" {
  let word = Tok::{ kind: Word, text: "word" }
  let string = Tok::{ kind: Str, text: "\"s\"" }
  let punct = Tok::{ kind: Punct, text: ")" }
  let space = Tok::{ kind: Space, text: " " }
  let filler = Tok::{ kind: Filler, text: "//" }
  assert_eq(token_boundary_score(None, Some(word)), 4)
  assert_eq(token_boundary_score(Some(word), Some(space)), 3)
  assert_eq(token_boundary_score(Some(filler), Some(word)), 3)
  assert_eq(token_boundary_score(Some(word), Some(punct)), 2)
  assert_eq(token_boundary_score(Some(word), Some(string)), 1)
  assert_eq(token_boundary_score(Some(word), Some(word)), 0)
}

///|
test "formatter trailing comma keeps repeated closing boilerplate soft" {
  let old = ["}),", "old body", "}),"]
  let new = ["}),", "new body", "}),"]
  assert_eq(tok_mass(tokenize_line("}),")), 13)
  assert_true(is_soft_line(old, new, 0, 0))
  assert_true(is_soft_line(old, new, 2, 2))
}

///|
test "global traceback preserves both texts and weighted minimum cost" {
  for
    pair in [
      ("x x", "x"),
      ("x", "x x"),
      ("x  x", "x"),
      ("a a a", "a a"),
      ("alpha beta alpha beta", "alpha beta"),
      ("// foo foo", "// foo"),
      ("// // foo foo", "// foo"),
      ("f((x))", "f(x)"),
      ("f(x)", "f((x))"),
      ("call((alpha), (alpha))", "call((alpha))"),
      ("a \t a", "a"),
      ("let 名 = \"é😀\" // 注释 注释", "let 名 = \"z\" // 注释"),
      (
        "    match candidate.normalized_expr_identifier_name() {", "    if candidate.normalized_expr_identifier_name() is Some(candidate_name) {",
      ),
      ("", "only new"),
    ] {
    let (old, new) = pair
    let old_toks = tokenize_line(old)
    let new_toks = tokenize_line(new)
    let minimum = pair_ops_min(old_toks, new_toks)
    let cleaned = pair_ops(old_toks, new_toks)
    assert_eq(reconstruct_ops(minimum), (old, new))
    assert_eq(reconstruct_ops(cleaned), (old, new))
    assert_eq(ops_cost(minimum), wdist(old_toks, new_toks))
    assert_eq(ops_cost(cleaned), wdist(old_toks, new_toks))
  }
}

///|
test "blank soft anchor is removed when coherent line pairs are stronger" {
  let old = ["let a = old", "", "let b = old", "let c = old"]
  let new = ["let a = new", "let b = new", "let c = new", ""]
  @debug.debug_inspect(
    rendering_diff(old, new, false).edits(),
    content=(
      #|<ArrayView:
      #|  [
      #|    Delete(old_index=0, old_len=1, new_index=0),
      #|    Insert(old_index=1, new_index=0, new_len=3),
      #|    Equal(old_index=1, new_index=3, len=1),
      #|    Delete(old_index=2, old_len=2, new_index=4),
      #|  ]>
    ),
  )
  @debug.debug_inspect(
    rendering_diff(old, new, true).edits(),
    content=(
      #|<ArrayView:
      #|  [
      #|    Delete(old_index=0, old_len=4, new_index=0),
      #|    Insert(old_index=4, new_index=0, new_len=4),
      #|  ]>
    ),
  )
}

///|
test "repeated bracket soft anchor yields to meaningful exact context" {
  let old = ["let a = old", "same line", "let b = old", "}", "let c = old", "}"]
  let new = ["let a = new", "}", "same line", "let b = new", "let c = new", "}"]
  @debug.debug_inspect(
    rendering_diff(old, new, true).edits(),
    content=(
      #|<ArrayView:
      #|  [
      #|    Delete(old_index=0, old_len=1, new_index=0),
      #|    Insert(old_index=1, new_index=0, new_len=2),
      #|    Equal(old_index=1, new_index=2, len=1),
      #|    Delete(old_index=2, old_len=3, new_index=3),
      #|    Insert(old_index=5, new_index=3, new_len=2),
      #|    Equal(old_index=5, new_index=5, len=1),
      #|  ]>
    ),
  )
}

///|
test "meaningful equal middle line remains a hard anchor" {
  let old = ["let a = old", "same semantic anchor", "let b = old"]
  let new = ["let a = new", "same semantic anchor", "let b = new"]
  assert_eq(
    rendering_diff(old, new, true).edits(),
    rendering_diff(old, new, false).edits(),
  )
}

///|
test "soft equal spans are bounded and significant lines never soften" {
  let eight = Array::make(8, "")
  let old_eight = ["old head"] + eight + ["old tail"]
  let new_eight = ["new head"] + eight + ["new tail"]
  let diff_eight = @diff.Diff(old=old_eight, new=new_eight)
  assert_true(
    soft_equal_edits(diff_eight.edits(), old_eight, new_eight).contains(true),
  )

  let nine = Array::make(9, "")
  let old_nine = ["old head"] + nine + ["old tail"]
  let new_nine = ["new head"] + nine + ["new tail"]
  let diff_nine = @diff.Diff(old=old_nine, new=new_nine)
  assert_false(
    soft_equal_edits(diff_nine.edits(), old_nine, new_nine).contains(true),
  )

  let old_word = ["old head", "semantic anchor", "old tail"]
  let new_word = ["new head", "semantic anchor", "new tail"]
  let diff_word = @diff.Diff(old=old_word, new=new_word)
  assert_false(
    soft_equal_edits(diff_word.edits(), old_word, new_word).contains(true),
  )
}
