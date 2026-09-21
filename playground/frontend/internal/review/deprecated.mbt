///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend ReviewAnchor with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend ReviewAnchor with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend ReviewSide with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend ReviewSide with Eq::{not_equal, equal}
