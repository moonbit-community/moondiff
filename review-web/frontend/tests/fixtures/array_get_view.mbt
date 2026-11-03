///|
/// Creates a view of a portion of the array, returning `None` when indices are
/// invalid.
///
/// Parameters:
///
/// * `array` : The array to create a view from.
/// * `start` : The starting index of the view (inclusive). Defaults to 0.
/// * `end` : The ending index of the view (exclusive). If not provided, defaults
/// to the length of the array.
///
/// Returns `Some(ArrayView)` that provides a window into the specified portion
/// of the array, or `None` when the indices are invalid.
///
/// Example:
///
/// ```mbt check
/// test {
///   let arr = [1, 2, 3, 4, 5]
///   let start = 1
///   let end = 4
///   debug_inspect(
///     arr.get_view(start~, end~),
///     content=(
///       #|Some(<ArrayView: [2, 3, 4]>)
///     ),
///   )
///   let start = 3
///   let end = 10
///   debug_inspect(arr.get_view(start~, end~), content="None")
/// }
/// ```
pub fn[T] Array::get_view(
  self : Array[T],
  start~ : Int32 = 0,
  end? : Int32,
) -> ArrayView[T]? {
  let len = self.length()
  let end = match end {
    Some(end) | (None with end = len) => end
  }
  guard start >= 0 && start <= end && end <= len else { None }
  Some(self.buffer().unsafe_view(start~, end~))
}
