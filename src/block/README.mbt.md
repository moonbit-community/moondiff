# `myfreess/moondiff/block`

Splits MoonBit source text into top-level “blocks” keyed by the UUID comments produced by `moon fmt -- -add-uuid`, and provides a simple UUID-based pairing step for block-wise diffs.

## Examples

```mbt check
///|
test "split source into UUID blocks" {
  let src =
    #|///|UUID(1)
    #|fn foo() -> Int { 1 }
    #|///|UUID(2)
    #|fn bar() -> Int { 2 }
  let blocks = @block.create_blocks(src)
  assert_eq(blocks.length(), 2)
  assert_eq(blocks[0].uuid, "1")
  assert_eq(blocks[1].uuid, "2")
}

///|
test "pair blocks by UUID" {
  let old_src =
    #|///|UUID(1)
    #|fn foo() -> Int { 1 }
    #|///|UUID(2)
    #|fn bar() -> Int { 2 }
  let new_src =
    #|///|UUID(2)
    #|fn bar() -> Int { 20 }
    #|///|UUID(3)
    #|fn baz() -> Int { 3 }
  let old_blocks = @block.create_blocks(old_src)
  let new_blocks = @block.create_blocks(new_src)
  let edits = @block.pairing_blocks_by_uuid(old=old_blocks[:], new=new_blocks[:])
  assert_eq(edits.length(), 3)
}
```
