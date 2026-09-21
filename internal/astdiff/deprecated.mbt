///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend Edge with Debug::{to_repr}

///|
#deprecated
#doc(hidden)
pub extend EnteredDelimiter with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend EnteredDelimiter with Show::{to_string, output}

///|
#deprecated
#doc(hidden)
pub extend Node with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Stack with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Vertex with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Vertex with Hash::{hash, hash_combine}
