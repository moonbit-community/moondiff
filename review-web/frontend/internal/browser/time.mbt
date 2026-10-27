///|
// Preserve browser Date parsing and local timezone/Intl formatting semantics.
pub extern "js" fn date_parse(value : String) -> Double = "value => Date.parse(value)"

///|
pub extern "js" fn date_now() -> Double = "() => Date.now()"

///|
pub extern "js" fn performance_now() -> Double = "() => performance.now()"

///|
pub extern "js" fn date_iso_now() -> String = "() => new Date().toISOString()"

///|
pub extern "js" fn date_utc(time : Double) -> String = "time => new Date(time).toUTCString()"

///|
pub extern "js" fn date_local(time : Double) -> String =
  #| time => new Intl.DateTimeFormat('en', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(time))

///|
pub extern "js" fn random_uuid() -> String = "() => crypto.randomUUID()"
