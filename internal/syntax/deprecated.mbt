///|
// Preserve trait methods that were previously promoted implicitly.
#deprecated
#doc(hidden)
pub extend AtomKind with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend ListKind with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend StringKind with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend Syntax with @moonbit-community/prettyprinter.Pretty::{pretty}

///|
#deprecated
#doc(hidden)
pub extend Syntax with Default::{default}

///|
#deprecated
#doc(hidden)
pub extend Syntax with Eq::{not_equal, equal}

///|
#deprecated
#doc(hidden)
pub extend SyntaxInfo with Default::{default}
