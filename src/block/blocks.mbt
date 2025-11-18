///|
pub type Blocks[T] = Array[Block[T]]

///|
pub fn create_blocks(
  input : StringView,
) -> Blocks[String] raise BlockProcessingError {
  let buf = StringBuilder::new()
  let res = Array::new()
  let lines = input.split("\n").collect()
  let mut current_uuid = ""
  let mut current_start_line = 1
  for i in 0..<lines.length() {
    let line = lines[i]
    if line lexmatch? ("///\|UUID\(", rest) {
      if rest lexmatch? ("[0-9a-z\-]+" as next_uuid, _) {
        if current_uuid != "" {
          res.push(Block::{
            start_line: current_start_line,
            uuid: current_uuid,
            contents: buf.to_string(),
          })
          buf.reset()
        }
        current_uuid = next_uuid.to_string()
        current_start_line = i + 1
      } else {
        raise UUIDNotFound(line.to_string())
      }
    } else {
      buf.write_stringview(line)
      buf.write_char('\n')
    }
  } else {
    if !buf.is_empty() {
      res.push(Block::{
        start_line: current_start_line,
        uuid: current_uuid,
        contents: buf.to_string(),
      })
    }
  }
  res
}

///|
test {
  let text =
    #|///|UUID(1)
    #|fn foo
    #|  // comment here
    #|///|UUID(2)
    #|fn bar
    #|  // another comment here
  @json.inspect(create_blocks(text), content=[
    { "start_line": 1, "uuid": "1", "contents": "fn foo\n  // comment here\n" },
    {
      "start_line": 4,
      "uuid": "2",
      "contents": "fn bar\n  // another comment here\n",
    },
  ])
}

///|
test "empty block" {
  let text =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
  @json.inspect(create_blocks(text), content=[
    { "start_line": 1, "uuid": "1", "contents": "" },
    { "start_line": 2, "uuid": "2", "contents": "" },
  ])
  let text =
    #|///|UUID(1)
    #|///|UUID(2)
    #|///|UUID(3)
    #|///|UUID(4)
    #|///|UUID(5)
  @json.inspect(create_blocks(text), content=[
    { "start_line": 1, "uuid": "1", "contents": "" },
    { "start_line": 2, "uuid": "2", "contents": "" },
    { "start_line": 3, "uuid": "3", "contents": "" },
    { "start_line": 4, "uuid": "4", "contents": "" },
  ])
}
