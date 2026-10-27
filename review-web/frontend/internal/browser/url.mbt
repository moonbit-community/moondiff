///|
#external
pub type URL

///|
extern "js" fn parse_url_native(
  source : String,
  base : String,
) -> @js.Nullable[URL] =
  #| (source, base) => { try { return new URL(source, base || undefined); } catch { return null; } }

///|
pub fn parse_url(source : String, base~ : String = "") -> URL? {
  parse_url_native(source, base).to_option()
}

///|
pub extern "js" fn URL::href(self : URL) -> String = "url => url.href"

///|
pub extern "js" fn URL::protocol(self : URL) -> String = "url => url.protocol"

///|
pub extern "js" fn URL::hostname(self : URL) -> String = "url => url.hostname"

///|
pub extern "js" fn URL::port(self : URL) -> String = "url => url.port"

///|
pub extern "js" fn URL::username(self : URL) -> String = "url => url.username"

///|
pub extern "js" fn URL::password(self : URL) -> String = "url => url.password"

///|
pub extern "js" fn URL::pathname(self : URL) -> String = "url => url.pathname"

///|
pub extern "js" fn URL::search(self : URL) -> String = "url => url.search"

///|
pub extern "js" fn URL::hash(self : URL) -> String = "url => url.hash"
