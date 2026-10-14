///|
test "avatar URLs encode path separators and Unicode as URI components" {
  assert_eq(
    comment_avatar_url("a/b ?#%"),
    "https://github.com/a%2Fb%20%3F%23%25.png?size=64",
  )
  assert_eq(
    comment_avatar_url("中文😀"),
    "https://github.com/%E4%B8%AD%E6%96%87%F0%9F%98%80.png?size=64",
  )
  assert_eq(
    comment_avatar_url("a-_.!~*'()"),
    "https://github.com/a-_.!~*'().png?size=64",
  )
}

///|
test "relative time preserves thresholds, pluralization and future labels" {
  for
    (seconds, expected) in [
      (0.0, "just now"),
      (59.999, "just now"),
      (60.0, "1 minute ago"),
      (119.9, "1 minute ago"),
      (120.0, "2 minutes ago"),
      (3600.0, "1 hour ago"),
      (86400.0, "1 day ago"),
      (2592000.0, "1 month ago"),
      (31536000.0, "1 year ago"),
      (-60.0, "in 1 minute"),
      (-7200.0, "in 2 hours"),
    ] {
    assert_eq(relative_time(seconds), expected)
  }
}

///|
test "tree drag width clamps to viewport and rounds to whole CSS pixels" {
  assert_eq(tree_drag_width(300.0, -200.0, 1440.0), 240)
  assert_eq(tree_drag_width(300.0, 900.0, 1440.0), 640)
  assert_eq(tree_drag_width(300.0, 900.0, 800.0), 400)
  assert_eq(tree_drag_width(300.0, 900.0, 400.0), 240)
  assert_eq(tree_drag_width(300.0, 0.5, 1440.0), 301)
}

///|
test "menu keyboard wraps and ignores empty or unhandled cases" {
  assert_eq(menu_key_index("ArrowDown", 2, 3), Some(0))
  assert_eq(menu_key_index("ArrowUp", 0, 3), Some(2))
  assert_eq(menu_key_index("ArrowDown", -1, 3), Some(0))
  assert_eq(menu_key_index("Home", 2, 3), Some(0))
  assert_eq(menu_key_index("End", 0, 3), Some(2))
  assert_eq(menu_key_index("ArrowDown", 0, 0), None)
  assert_eq(menu_key_index("Enter", 0, 3), None)
}
