///|
fn print_edits(edits : Array[@edit.Edit[StringView]]) -> String {
  let buf = StringBuilder::new()
  for edit in edits {
    match edit {
      Insert(new~) => {
        buf.write_string("+ ")
        buf.write_stringview(new)
      }
      Delete(old~) => {
        buf.write_string("- ")
        buf.write_stringview(old)
      }
      Equal(old~, ..) => {
        buf.write_string("  ")
        buf.write_stringview(old)
      }
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
test "single inserttion" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|bar
    #|quux
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|  bar
      #|+ quux
      #|  baz
      #|  qux
      #|
    ),
  )
}

///|
test "single deletion" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|- bar
      #|  baz
      #|  qux
      #|
    ),
  )
}

///|
test "insert and delete" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|quux
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|- bar
      #|+ quux
      #|  baz
      #|  qux
      #|
    ),
  )
}

///|
test "multiple insertions" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|bar
    #|quux
    #|corge
    #|baz
    #|grault
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|  bar
      #|+ quux
      #|+ corge
      #|  baz
      #|+ grault
      #|  qux
      #|
    ),
  )
}

///|
test "multiple deletions" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
    #|quux
    #|corge
  let new =
    #|foo
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|- bar
      #|  baz
      #|  qux
      #|- quux
      #|- corge
      #|
    ),
  )
}

///|
test "multiple insertions and deletions" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
    #|quux
  let new =
    #|foo
    #|corge
    #|baz
    #|grault
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|- bar
      #|+ corge
      #|  baz
      #|+ grault
      #|  qux
      #|- quux
      #|
    ),
  )
}

///|
test "no changes" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|bar
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|  bar
      #|  baz
      #|  qux
      #|
    ),
  )
}

///|
test "completely different" {
  let old =
    #|foo
    #|bar
  let new =
    #|baz
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|- foo
      #|- bar
      #|+ baz
      #|+ qux
      #|
    ),
  )
}

///|
test "empty to non-empty" {
  let old = []
  let new =
    #|foo
    #|bar
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|+ foo
      #|+ bar
      #|
    ),
  )
}

///|
test "non-empty to empty" {
  let old =
    #|foo
    #|bar
  let old = old.split("\n").collect()
  let new = []
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|- foo
      #|- bar
      #|
    ),
  )
}

///|
test "both empty" {
  let old = []
  let new = []
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|
    ),
  )
}
