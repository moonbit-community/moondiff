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
  Json([
    self.user_id,
    self.owner.to_lower(),
    self.repo.to_lower(),
    self.number,
    self.path,
  ]).stringify()
}

///|
fn viewed_storage_put(key : String, value : String) -> Bool {
  try {
    if @browser.storage_get(key) is Some(_) {
      return false
    }
    @browser.storage_set(key, value)
    @browser.storage_get(key) == Some(value)
  } catch {
    _ => false
  }
}

///|
fn viewed_storage_read(ok : (String) -> Unit, failed : () -> Unit) -> Unit {
  try {
    let records : Array[ViewedRecord] = []
    for i = 0; i < @browser.storage_length(); i = i + 1 {
      if @browser.storage_key(i) is Some(key) &&
        key.has_prefix("moondiff.viewed.pending.v1:") {
        let record : ViewedRecord = @json.from_json(
          @json.parse(@browser.storage_get(key).unwrap_or("null")),
        )
        guard key == record.key() else {
          failed()
          return
        }
        records.push(record)
      }
    }
    ok(Json(records).stringify())
  } catch {
    _ => failed()
  }
}

///|
priv suberror InvalidStoredViewedRecord

///|
fn viewed_storage_matches(value : String, id : String) -> Bool raise {
  let record = @json.parse(value)
  if record is Null {
    raise InvalidStoredViewedRecord
  }
  record is Object(fields) && fields.get("id") == Some(Json::string(id))
}

///|
fn viewed_storage_remove(key : String, id : String) -> Bool {
  try {
    guard @browser.storage_get(key) is Some(value) else { return true }
    if !viewed_storage_matches(value, id) {
      return true
    }
    @browser.storage_remove(key)
    @browser.storage_get(key) is None
  } catch {
    _ => false
  }
}

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
  index : Int32,
  record : ViewedRecord,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  // Commit the optimistic checkbox before an immediate storage failure can
  // roll it back, otherwise the browser's native toggle outlives the VDOM diff.
  let epoch = model.viewed.epoch
  @cmd.custom_cmd(scheduler => {
    let ok = viewed_storage_put(
      record.key(),
      ToJson::to_json(record).stringify(),
    )
    scheduler.add(emit(Viewed(Stored(epoch, index, record, ok))))
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
            deferred: false,
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
