///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend ComputationStage with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend ComputationStage with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend ContextLine with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffBlock with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffDocument with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffFragment with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffHunk with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffLine with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffRow with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffSection with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffSegment with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffSegmentKind with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffSide with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend DiffSide with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend DiffStatus with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend DiffStatus with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend FallbackReason with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend FallbackReason with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend HunkDocument with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend IgnoreReason with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend IgnoreReason with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend LineRange with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend LineRange with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend TopLevelDiff with Eq::{not_equal, equal}
