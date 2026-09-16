///|
/// Opt-in counters for the browser regression harness. Production has no sink.
pub extern "js" fn count(path : String, operation : String) -> Unit =
  #| (path, operation) => {
  #|   const sink = globalThis.__moondiffMetrics;
  #|   if (!sink) return;
  #|   const counts = sink.files[path] ??= {};
  #|   counts[operation] = (counts[operation] ?? 0) + 1;
  #| }

///|
pub extern "js" fn active(kind : String, delta : Int) -> Unit =
  #| (kind, delta) => {
  #|   const sink = globalThis.__moondiffMetrics;
  #|   if (!sink) return;
  #|   sink.active[kind] = (sink.active[kind] ?? 0) + delta;
  #| }
