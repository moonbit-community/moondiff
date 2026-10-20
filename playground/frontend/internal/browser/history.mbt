///|
pub extern "js" fn history_state() -> String = "() => JSON.stringify(history.state?.moondiff ?? null)"

///|
pub extern "js" fn history_entry_id() -> String = "() => Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16)).join('-')"

///|
pub extern "js" fn history_replace(state : String, path : String) -> Unit = "(state, path) => history.replaceState({...history.state, moondiff: JSON.parse(state)}, '', path)"

///|
pub extern "js" fn history_push(state : String, path : String) -> Unit = "(state, path) => history.pushState({...history.state, moondiff: JSON.parse(state)}, '', path)"

///|
pub extern "js" fn history_go(delta : Int32) -> Unit = "delta => history.go(delta)"

///|
pub extern "js" fn manual_scroll_restoration() -> Unit = "() => { history.scrollRestoration = 'manual'; }"

///|
pub extern "js" fn scroll_x() -> Double = "() => window.scrollX"

///|
pub extern "js" fn scroll_y() -> Double = "() => window.scrollY"

///|
pub extern "js" fn scroll_to(x : Double, y : Double) -> Unit = "(x, y) => window.scrollTo({left: x, top: y, behavior: 'instant'})"
