///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend DiffMode with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend DiffMode with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffOptions with Default::{default}
