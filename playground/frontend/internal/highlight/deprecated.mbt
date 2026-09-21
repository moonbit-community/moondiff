///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend FileHighlights with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend HighlightKind with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend HighlightKind with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend HighlightSpan with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend HighlightSpan with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend SourceHighlights with Eq::{not_equal, equal}
