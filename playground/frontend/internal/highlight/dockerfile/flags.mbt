///|
fn scan_flag(
  source : String,
  start : Int,
  end : Int,
  spans : Array[HighlightSpan],
) -> Int {
  let mut cursor = start + 2
  while cursor < end && !(source[cursor] is (' ' | '\t' | '=' | ',')) {
    cursor += 1
  }
  add_span(spans, 0, start, cursor, Attribute)
  if cursor < end && source[cursor] == '=' {
    add_span(spans, 0, cursor, cursor + 1, Operator)
    cursor += 1
    for parameter_start = cursor {
      while cursor < end && !(source[cursor] is (' ' | '\t' | ',')) {
        cursor += 1
      }
      if parameter_start < cursor {
        let parameter_end = cursor
        let mut part = parameter_start
        while part < parameter_end {
          let mut variable = part
          while variable < parameter_end && source[variable] != '$' {
            variable += 1
          }
          add_span(spans, 0, part, variable, AttributeParameter)
          if variable < parameter_end {
            let next = scan_variable(source, variable, parameter_end, spans)
            if next == variable + 1 {
              part = variable + 1
            } else {
              part = next
            }
          } else {
            part = parameter_end
          }
        }
      }
      if cursor < end && source[cursor] == ',' {
        add_span(spans, 0, cursor, cursor + 1, Operator)
        cursor += 1
        continue cursor
      }
      break
    }
  }
  cursor
}
