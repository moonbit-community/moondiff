///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend ScopeLimitExceeded with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend ScopeLimitExceeded with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Stage with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend Stage with Eq::{not_equal, equal}
