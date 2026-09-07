///|
/// Match MoonBit test-file suffixes exactly, including case.
pub fn is_test_file(path : String) -> Bool {
  path.has_suffix("_test.mbt") || path.has_suffix("_wbtest.mbt")
}
