///|UUID(326ec6a8-e68b-41d0-ab16-0875a58ccf10)
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

///|UUID(b9434b86-3c80-4b4f-9247-626f03afb5b9)
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

///|UUID(be21eb4c-40fb-4d9e-8646-8489b3a90c87)
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

///|UUID(c69cc691-01af-4531-a9cf-ea24f25b2e2e)
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

///|UUID(30ce4d20-4468-458a-b99a-8a6782b74d8a)
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

///|UUID(037dbbeb-49fd-475f-90eb-4b9dbebd2071)
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

///|UUID(df9662aa-75b1-4764-bac2-ce5419efcd26)
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

///|UUID(74d7fabd-e3df-40bd-8c2b-cdc99f8eae95)
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

///|UUID(afb2ba62-9737-486f-8147-5c7fc34281db)
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

///|UUID(19dfb45c-8484-42c8-8c31-7dd22759430d)
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

///|UUID(11b8543d-14aa-4932-a0b5-bd276b6a94e9)
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

///|UUID(ba560e80-26ec-4925-acac-ab0bc521f2d3)
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

///|UUID(2cc41314-c89e-427c-bb42-78f6c46498e2)
test "insert at end" {
  let old =
    #|foo
    #|bar
  let new =
    #|foo
    #|bar
    #|baz
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|  bar
      #|+ baz
      #|
    ),
  )
}

///|UUID(32dbb096-dfbe-414e-9d12-4e6acc21e185)
test "delete at end" {
  let old =
    #|foo
    #|bar
    #|baz
  let new =
    #|foo
    #|bar
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|  bar
      #|- baz
      #|
    ),
  )
}

///|UUID(aaf86abf-5c6e-4881-9772-ab04eb8801da)
test "insert at beginning" {
  let old =
    #|bar
    #|baz
  let new =
    #|foo
    #|bar
    #|baz
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|+ foo
      #|  bar
      #|  baz
      #|
    ),
  )
}

///|UUID(c418df6e-df9c-4233-9884-976fd88f9c8e)
test "delete at beginning" {
  let old =
    #|foo
    #|bar
    #|baz
  let new =
    #|bar
    #|baz
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|- foo
      #|  bar
      #|  baz
      #|
    ),
  )
}

///|UUID(80fc4496-5c98-47f2-b8e8-2c73917e6c29)
test "consecutive inserts and deletes" {
  let old =
    #|foo
    #|bar
    #|baz
    #|qux
  let new =
    #|foo
    #|corge
    #|grault
    #|qux
  let old = old.split("\n").collect()
  let new = new.split("\n").collect()
  inspect(
    print_edits(diff(old~, new~)),
    content=(
      #|  foo
      #|- bar
      #|- baz
      #|+ corge
      #|+ grault
      #|  qux
      #|
    ),
  )
}
