///|
/// Drops threads that cannot contribute anything an earlier thread does not
/// already cover: two threads with the same future differ only in priority,
/// so the later one can go.
///
/// Threads in `self` all continue with `next` once they finish, which is
/// what makes a thread that has *already* finished — one sitting at `Eps` —
/// equivalent to a thread sitting at `next` itself. Both are keyed by
/// `next.id` so that the pair collapses to one; without that, a sequence
/// whose first part can both finish and continue doubles its thread set on
/// every character.
///
/// The equivalence is used as a dedup key only. Rewriting the finished
/// thread to `Exp(marks, next)` would *look* like the same statement, but
/// the caller wraps the result in `ts_seq(.., next)`, which appends `next`
/// again — so the continuation would be matched twice over. Keeping the
/// thread at `Eps` also leaves `ts_seq` able to collapse a sequence whose
/// first part has come down to a single finished thread.
fn ThreadSet::remove_duplicates(self : ThreadSet, next : Expr) -> ThreadSet {
  let seen = @hashset.HashSet([])
  for thread in self; result = ts_empty {
    match thread {
      End(_) => break result + ts_one(thread)
      Exp(_, { def: Eps, .. }) =>
        if !seen.contains(next.id) {
          seen.add(next.id)
          continue result + ts_one(thread)
        } else {
          continue result
        }
      Exp(_, { id, .. }) =>
        if !seen.contains(id) {
          seen.add(id)
          continue result + ts_one(thread)
        } else {
          continue result
        }
      Seq(pref, first, next) => {
        let first_dedup = first.remove_duplicates(next)
        continue result + ts_seq(pref, first_dedup, next)
      }
    }
  } nobreak {
    result
  }
}
