///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend CacheKey with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend CacheKey with Hash::{hash, hash_combine}

///|
#deprecated
#doc(hidden)
pub extend CachedDiffResult with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend ChangeView with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffAlgorithm with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffAlgorithm with Hash::{hash, hash_combine}

///|
#deprecated
#doc(hidden)
pub extend DiffCache with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend FileState with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend SideLoad with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend SourceSide with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend ViewMode with Eq::{not_equal, equal}
