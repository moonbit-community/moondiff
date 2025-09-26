///|
// typealias @edit.Edit

///|
// test "single delete move forward" {
//   let edits : Array[Edit[Array[Char]]] = [
//     Equal(new=['T', 'h'], old=[]),
//     Delete(old=['a', 't', ' ', 'c']),
//     Equal(new=['a', 't', ' ', 'c', 'a', 'r', 't', 'o', 'o', 'n'], old=[]),
//   ]
//   @json.inspect(@postopt.align_edit_boundaries(edits), content=[
//     ["Equal", { "old": [], "new": ["T", "h", "a", "t"] }],
//     ["Delete", { "old": [" ", "c", "a", "t"] }],
//     ["Equal", { "old": [], "new": [" ", "c", "a", "r", "t", "o", "o", "n"] }],
//   ])
// }
// 
// ///|
// test "single insert move forward" {
//   let edits : Array[Edit[Array[Char]]] = [
//     Equal(new=['T', 'h'], old=[]),
//     Insert(new=['a', 't', ' ', 'c']),
//     Equal(new=['a', 't', ' ', 'c', 'a', 'r', 't', 'o', 'o', 'n'], old=[]),
//   ]
//   @json.inspect(@postopt.align_edit_boundaries(edits), content=[
//     ["Equal", { "old": [], "new": ["T", "h", "a", "t"] }],
//     ["Insert", { "new": [" ", "c", "a", "t"] }],
//     ["Equal", { "old": [], "new": [" ", "c", "a", "r", "t", "o", "o", "n"] }],
//   ])
// }
// 
// ///|
// test "single delete move backward" {
//   let edits : Array[Edit[Array[Char]]] = [
//     Equal(new=['h', 'e'], old=[]),
//     Delete(old=['l', 'l', 'o', ' ', 'h', 'e']),
//     Equal(new=['l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd'], old=[]),
//   ]
//   @json.inspect(@postopt.align_edit_boundaries(edits), content=[
//     ["Equal", { "old": [], "new": [] }],
//     ["Delete", { "old": ["h", "e", "l", "l", "o", " "] }],
//     [
//       "Equal",
//       {
//         "old": [],
//         "new": ["h", "e", "l", "l", "o", " ", "W", "o", "r", "l", "d"],
//       },
//     ],
//   ])
// }
// 
// ///|
// test "fn insert errorpoly" {
//   let edits : Array[Edit[Array[Char]]] = [
//     Equal(new=['(', 'T', ')', ' ', '-', '>', ' ', 'U', ' '], old=[]),
//     Insert(new=['r', 'a', 'i', 's', 'e', '?']),
//     Equal(new=[')', ' ', '-', '>', ' ', 'U'], old=[]),
//     Insert(new=['?', ' ', 'r', 'a', 'i', 's', 'e']),
//     Equal(new=['?', ' ', '{'], old=[]),
//   ]
//   @json.inspect(@postopt.align_edit_boundaries(edits), content=[
//     [
//       "Equal",
//       { "old": [], "new": ["(", "T", ")", " ", "-", ">", " ", "U", " "] },
//     ],
//     ["Insert", { "new": ["r", "a", "i", "s", "e", "?"] }],
//     ["Equal", { "old": [], "new": [")", " ", "-", ">", " ", "U", "?"] }],
//     ["Insert", { "new": [" ", "r", "a", "i", "s", "e", "?"] }],
//     ["Equal", { "old": [], "new": [" ", "{"] }],
//   ])
// }
