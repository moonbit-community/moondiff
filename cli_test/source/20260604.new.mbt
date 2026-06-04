///|UUID(31d25c5a-0e2a-49e8-9e32-8de8940bded3)
test "diff_text colors file headers blue" {
  let old_source =
    #|fn f() {
    #|  foo(bar)
    #|}
  let new_source =
    #|fn f() {
    #|  foo(baz(bar))
    #|}
  let result = diff_text(
    "old.mbt",
    old_source,
    "new.mbt",
    new_source,
    options=DiffOptions::new(use_color=true),
  )
}