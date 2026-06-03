fn Syntax::looks_like_punctuation(self : Syntax) -> Bool {
  match self {
    Atom(content~, ..) => {
      if content.is_empty() {
        return false
      }
      for ch in content.to_array() {
        match ch {
          '0'..='9' | 'a'..='z' | 'A'..='Z' | '_' => return false
          _ => ()
        }
      } nobreak {
        true
      }
    }
    _ => false
  }
}