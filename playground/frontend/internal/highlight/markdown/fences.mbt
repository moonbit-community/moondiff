///|
priv enum FenceLanguage {
  MoonBit
  C
  Yaml
  Json
  JavaScript
  Dockerfile
  Plain
}

///|
priv struct CodeLine {
  start : Int
  end : Int
}

///|
fn fence_language(info : String) -> FenceLanguage {
  let trimmed = info.trim()
  let mut end = 0
  while end < trimmed.length() && !(trimmed[end] is (' ' | '\t')) {
    end += 1
  }
  let word = trimmed[0:end].to_lower()
  match word {
    "moonbit" | "mbt" => MoonBit
    "c" | "h" => C
    "yaml" | "yml" => Yaml
    "json" => Json
    "javascript" | "js" | "mjs" | "cjs" => JavaScript
    "dockerfile" | "containerfile" => Dockerfile
    _ => Plain
  }
}

///|
fn nested_highlights(
  language : FenceLanguage,
  source : String,
) -> @highlight.SourceHighlights? {
  match language {
    MoonBit => Some(@highlight_moonbit.highlight(source))
    C => Some(@highlight_c.highlight(source))
    Yaml => Some(@highlight_yaml.highlight(source))
    Json => Some(@highlight_json.highlight(source))
    JavaScript => Some(@highlight_javascript.highlight(source))
    Dockerfile => Some(@highlight_dockerfile.highlight(source))
    Plain => None
  }
}

///|
fn add_fence_body(
  source : String,
  body : Array[CodeLine],
  language : FenceLanguage,
  candidates : Array[Candidate],
) -> Unit {
  if language is Plain {
    for line in body {
      candidate(candidates, line.start, line.end, StringLiteral, 70)
    }
    return
  }
  let code = StringBuilder()
  for index, line in body {
    if index > 0 {
      code.write_char('\n')
    }
    code.write_view(source[line.start:line.end])
  }
  let highlights = nested_highlights(language, code.to_string()).unwrap()
  for index, line in body {
    for span in highlights.line(index + 1) {
      candidate(
        candidates,
        line.start + span.start,
        line.start + span.end,
        span.kind,
        90,
      )
    }
  }
}

///|
fn fence_run(source : String, start : Int, end : Int) -> (UInt16, Int)? {
  if start >= end || !(source[start] is ('`' | '~')) {
    return None
  }
  let marker = source[start]
  let mut cursor = start
  while cursor < end && source[cursor] == marker {
    cursor += 1
  }
  if cursor - start >= 3 {
    Some((marker, cursor - start))
  } else {
    None
  }
}
