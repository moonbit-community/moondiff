///|
pub(all) enum LoadMsg {
  CommitPageLoaded(Int, Int, Result[ApiCommit, Error])
  ToggleFile(Int, Int)
  OpenFile(Int, Int)
  RetryFile(Int, Int)
  SourceLoaded(Int, Int, SourceSide, Result[(String, Bytes), Error])
  PullMetadataLoaded(Int, Int, Result[ApiPull, Error])
  PullCompareLoaded(Int, Int, Result[ApiCompare, Error])
  PullFilesPageLoaded(Int, Int, Int, Result[Array[ApiFile], Error])
  PullValidationLoaded(Int, Int, Result[ApiPull, Error])
  PullCommitMetadataLoaded(Int, Result[ApiPull, Error])
}

///|
fn update_load(
  model : Model,
  msg : LoadMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    PullMetadataLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullMetadata(reference~, attempt=expected_attempt) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(metadata) =>
          start_pull_snapshot(model, reference, attempt, metadata, emit)
      }
    }
    PullCommitMetadataLoaded(generation, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is LoadingPullCommitMetadata(reference~) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(pull) => {
          let repository = branch_repository(
            pull.head,
            reference_repository(reference),
          )
          (
            with_phase(
              model,
              LoadingCommit(reference~, repository~, page=1, first=None, files=[]),
            ),
            commit_request(reference, repository, generation, 1, emit),
          )
        }
      }
    }
    PullCompareLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare=_,
          page~,
          files~
        ) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(compare) =>
          continue_pull_snapshot(
            model,
            reference,
            attempt,
            metadata,
            Some(compare),
            page,
            files,
            emit,
          )
      }
    }
    PullFilesPageLoaded(generation, attempt, page, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare~,
          page=expected_page,
          files~
        ) &&
        attempt == expected_attempt &&
        page == expected_page &&
        page > 0 else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(response) => {
          let accumulated = merge_file_pages(files, response)
          if should_fetch_next_pull_page(
              page,
              response.length(),
              accumulated.length(),
              Some(metadata.changed_files),
            ) {
            (
              with_phase(
                model,
                LoadingPullSnapshot(
                  reference~,
                  attempt~,
                  metadata~,
                  compare~,
                  page=page + 1,
                  files=accumulated,
                ),
              ),
              pull_files_request(reference, generation, attempt, page + 1, emit),
            )
          } else {
            continue_pull_snapshot(
              model, reference, attempt, metadata, compare, 0, accumulated, emit,
            )
          }
        }
      }
    }
    PullValidationLoaded(generation, attempt, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is ValidatingPullSnapshot(
          reference~,
          attempt=expected_attempt,
          metadata~,
          compare~,
          files~
        ) &&
        attempt == expected_attempt else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(verified) =>
          validate_or_retry_pull_snapshot(
            model, reference, attempt, metadata, compare, files, verified, emit,
          )
      }
    }
    CommitPageLoaded(generation, page, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase
        is LoadingCommit(reference~, repository~, page=expected, first~, files~) &&
        page == expected else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_phase(model, LoadFailed(error_message(error, true))),
            @rabbita.none,
          )
        Ok(response) => {
          let accumulated = merge_file_pages(files, response.files)
          let first_commit = first.unwrap_or(response)
          if should_fetch_next_page(page, response.files.length()) {
            (
              with_phase(
                model,
                LoadingCommit(
                  reference~,
                  repository~,
                  page=page + 1,
                  first=Some(first_commit),
                  files=accumulated,
                ),
              ),
              commit_request(reference, repository, generation, page + 1, emit),
            )
          } else {
            let view = finish_commit(
              reference, repository, first_commit, accumulated,
            )
            (
              with_phase(
                model,
                Showing(
                  ensure_expanded_file_documents(
                    view,
                    model.diff_algorithm,
                    ignore_comments=model.ignore_comments,
                    ignore_tests=model.ignore_tests,
                  ),
                ),
              ),
              commands_for_change(view, generation, emit),
            )
          }
        }
      }
    }
    ToggleFile(generation, index) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      if file.expanded {
        let changed = @change.FileState::{
          file: file.file,
          diff_mode: file.diff_mode,
          expanded: false,
          old_side: file.old_side,
          new_side: file.new_side,
          diff_cache: file.diff_cache,
        }
        (
          with_phase(model, Showing(set_file_state(view, index, changed))),
          @rabbita.none,
        )
      } else {
        expand_file(model, view, generation, index, file, emit)
      }
    }
    OpenFile(generation, index) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      let selected = select_file(model, index)
      let (opened, load_command) = if file.expanded {
        (selected, @rabbita.none)
      } else {
        expand_file(selected, view, generation, index, file, emit)
      }
      (
        opened,
        @rabbita.batch([load_command, @nav.scroll_to(file_dom_id(index))]),
      )
    }
    RetryFile(generation, index) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      let pair = source_pair_for_revisions(
        view.old_revision,
        view.new_revision,
        file.file,
      )
      let commands : Array[@rabbita.Cmd] = []
      let old_side = if file.old_side is LoadFailed(_) &&
        pair.old_location is Some(location) {
        commands.push(
          source_load_request(location, generation, index, Old, emit),
        )
        @change.Loading
      } else {
        file.old_side
      }
      let new_side = if file.new_side is LoadFailed(_) &&
        pair.new_location is Some(location) {
        commands.push(
          source_load_request(location, generation, index, New, emit),
        )
        @change.Loading
      } else {
        file.new_side
      }
      let changed = @change.FileState::{
        file: file.file,
        diff_mode: file.diff_mode,
        expanded: true,
        old_side,
        new_side,
        diff_cache: DiffCache::empty(),
      }
      (
        with_phase(model, Showing(set_file_state(view, index, changed))),
        @rabbita.batch(commands),
      )
    }
    SourceLoaded(generation, index, side, result) => {
      if generation != model.generation {
        return (model, @rabbita.none)
      }
      guard model.phase is Showing(view) && view.files.get(index) is Some(file) else {
        return (model, @rabbita.none)
      }
      let loaded = side_from_result(result)
      let changed = match side {
        Old =>
          @change.FileState::{
            file: file.file,
            diff_mode: file.diff_mode,
            expanded: file.expanded,
            old_side: loaded,
            new_side: file.new_side,
            diff_cache: DiffCache::empty(),
          }
        New =>
          {
            file: file.file,
            diff_mode: file.diff_mode,
            expanded: file.expanded,
            old_side: file.old_side,
            new_side: loaded,
            diff_cache: DiffCache::empty(),
          }
      }
      let changed = if changed.expanded {
        ensure_file_document(
          changed,
          model.diff_algorithm,
          ignore_comments=model.ignore_comments,
          ignore_tests=model.ignore_tests,
        )
      } else {
        changed
      }
      let changed_model = with_phase(
        model,
        Showing(set_file_state(view, index, changed)),
      )
      (changed_model, @rabbita.none)
    }
  }
}
