///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend AlignedDiffMode with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DetailedDiffResult with Eq::{not_equal, equal}
