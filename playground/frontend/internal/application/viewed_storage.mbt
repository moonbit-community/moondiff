///|
// Only operation metadata belongs in sessionStorage. Expansion, code, drafts and
// credentials stay out of this record. Paths are kept verbatim, including controls.
pub(all) struct ViewedRecord {
  id : String
  user_id : String
  owner : String
  repo : String
  number : String
  path : String
  viewed : Bool
  base_sha : String
  head_sha : String
} derive(Eq, ToJson, FromJson)

///|
fn ViewedRecord::target(self : ViewedRecord) -> @protocol.FileViewedState {
  if self.viewed {
    Viewed
  } else {
    Unviewed
  }
}

///|
fn ViewedRecord::key(self : ViewedRecord) -> String {
  "moondiff.viewed.pending.v1:" +
  [
    self.user_id,
    self.owner.to_lower(),
    self.repo.to_lower(),
    self.number,
    self.path,
  ]
  .to_json()
  .stringify()
}

///|
extern "js" fn viewed_storage_put(key : String, value : String) -> Bool =
  #| (key, value) => {
  #|   try {
  #|     if (sessionStorage.getItem(key) !== null) return false;
  #|     sessionStorage.setItem(key, value);
  #|     return sessionStorage.getItem(key) === value;
  #|   } catch { return false; }
  #| }

///|
extern "js" fn viewed_storage_read(
  ok : (String) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #| (ok, failed) => {
  #|   try {
  #|     const records = [];
  #|     for (let i = 0; i < sessionStorage.length; i++) {
  #|       const key = sessionStorage.key(i);
  #|       if (key?.startsWith('moondiff.viewed.pending.v1:')) {
  #|         const record = JSON.parse(sessionStorage.getItem(key));
  #|         const expected = 'moondiff.viewed.pending.v1:' + JSON.stringify([
  #|           record.user_id, record.owner.toLowerCase(), record.repo.toLowerCase(), record.number, record.path
  #|         ]);
  #|         if (key !== expected) throw new Error('Invalid Viewed record');
  #|         records.push(record);
  #|       }
  #|     }
  #|     ok(JSON.stringify(records));
  #|   } catch { failed(); }
  #| }

///|
extern "js" fn viewed_storage_remove(key : String, id : String) -> Bool =
  #| (key, id) => {
  #|   try {
  #|     const value = sessionStorage.getItem(key);
  #|     if (value === null || JSON.parse(value).id !== id) return true;
  #|     sessionStorage.removeItem(key);
  #|     return sessionStorage.getItem(key) === null;
  #|   } catch { return false; }
  #| }

///|
fn viewed_restore_request(
  model : Model,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    let failed = () => {
      scheduler.add(
        emit(
          Viewed(
            Restored(
              model.viewed.epoch,
              model.viewed.serial,
              Err(
                "Cannot read pending Viewed changes from session storage. Restore storage access and recheck Viewed.",
              ),
            ),
          ),
        ),
      )
    }
    viewed_storage_read(
      text => {
        try (@json.from_json(@json.parse(text)) : Array[ViewedRecord]) catch {
          _ => failed()
        } noraise {
          records => {
            guard records.all(record => {
              !record.id.is_empty() && !record.user_id.is_empty()
            }) else {
              failed()
              return
            }
            scheduler.add(
              emit(
                Viewed(
                  Restored(model.viewed.epoch, model.viewed.serial, Ok(records)),
                ),
              ),
            )
          }
        }
      },
      failed,
    )
  })
}

///|
fn viewed_persist_request(
  model : Model,
  index : Int,
  record : ViewedRecord,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  // Commit the optimistic checkbox before an immediate storage failure can
  // roll it back, otherwise the browser's native toggle outlives the VDOM diff.
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    let ok = viewed_storage_put(
      record.key(),
      ToJson::to_json(record).stringify(),
    )
    scheduler.add(emit(Viewed(Stored(model.viewed.epoch, index, record, ok))))
  })
}

///|
fn viewed_forget(
  model : Model,
  record : ViewedRecord,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    if !viewed_storage_remove(record.key(), record.id) {
      scheduler.add(emit(Viewed(StorageFailed(model.viewed.epoch))))
    }
  })
}

///|
fn restore_viewed_records(
  model : Model,
  records : Array[ViewedRecord],
) -> Model {
  guard model.auth is SignedIn(user_id=Some(user_id), ..) &&
    model.phase is Showing(view) &&
    view.reference.target is PullRequest(number) else {
    return model
  }
  let files = model.viewed.files.copy()
  for record in records {
    if record.user_id != user_id ||
      record.owner.to_lower() != view.reference.owner.to_lower() ||
      record.repo.to_lower() != view.reference.repo.to_lower() ||
      record.number != number {
      continue
    }
    for index, file in view.files {
      if file.file.filename == record.path && files[index].pending is None {
        let old = files[index]
        files[index] = {
          ..old,
          state: Some(record.target()),
          // Never restore an old expansion choice, even on the same snapshot.
          // A recovered operation cannot roll back: it can only be confirmed.
          touched: true,
          pending: Some({
            record,
            stored: true,
            before: record.target(),
            expanded: file.expanded,
            expansion_revision: old.expansion_revision,
            confirming: true,
          }),
        }
      }
    }
  }
  { ..model, viewed: { ..model.viewed, files, storage_ready: true, }, }
}
