///|
pub(all) enum AuthMsg {
  AuthStatusLoaded(Int, Result[ApiAuthStatus, Error])
  ReactivationAuthStatusLoaded(
    Int,
    Int,
    CommitRef?,
    Result[ApiAuthStatus, Error]
  )
  StartSignIn
  RestoreAuth
  DeviceUpdated(Int, String, Bool, Result[@protocol.DeviceResponse, Error])
  CancelSignIn
  DeviceCancelFinished(Int, String, Result[@protocol.DeviceResponse, Error])
  CopyDeviceCode
  DeviceCodeCopied(Int, String, Bool)
  Logout
  AuthLogoutFinished(Int, Result[ApiAuthStatus, Error])
}

///|
fn update_auth(
  model : Model,
  msg : AuthMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    AuthStatusLoaded(revision, result) => {
      guard revision == model.auth_revision else {
        return (model, @rabbita.none)
      }
      let (next, command) = match result {
        Ok(status) => {
          let (next, command, _) = apply_auth_status(model, status, false, emit)
          (next, command)
        }
        Err(error) =>
          (
            with_auth(model, AuthFailed(comment_failure_message(error))),
            @rabbita.none,
          )
      }
      if !model.restore_pending &&
        next.generation == 0 &&
        next.route is Some(reference) {
        let (loaded, load_command) = begin_change_load(next, reference, emit)
        (loaded, @rabbita.batch([command, load_command]))
      } else {
        (next, command)
      }
    }
    ReactivationAuthStatusLoaded(revision, generation, reference, result) => {
      guard revision == model.auth_revision &&
        (
          auth_device_id(model.auth) is Some(_) ||
          (generation == model.generation && model.route == reference)
        ) &&
        !(model.auth is DeviceCancelling(_, _)) else {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => finish_sign_in(model, status, emit)
        Err(error) =>
          if model.auth is Authorizing(_, _) {
            (model, @rabbita.none)
          } else {
            (
              with_auth(model, AuthFailed(comment_failure_message(error))),
              @rabbita.none,
            )
          }
      }
    }
    RestoreAuth => {
      let model = with_review(
        { ..model, restore_pending: true, },
        @comments.update(model.review, RecoverInterrupted).0,
      )
      if model.auth is DeviceCancelling(_, _) {
        return update_auth(model, CancelSignIn, emit)
      }
      let next = with_auth(
        { ..model, auth_revision: model.auth_revision + 1, },
        AuthChecking,
      )
      (
        next,
        if next.generation == 0 {
          auth_status_request(next.auth_revision, emit)
        } else {
          reactivation_auth_status_request(
            next.route,
            next.generation,
            next.auth_revision,
            emit,
          )
        },
      )
    }
    StartSignIn => {
      guard auth_device_id(model.auth) is None else {
        return (model, @rabbita.none)
      }
      let id = new_auth_attempt_id()
      let next = with_auth(
        { ..model, auth_revision: model.auth_revision + 1, },
        Authorizing(starting_device(id), ""),
      )
      (next, device_request(next, @github_client.Start, id, 0, emit))
    }
    DeviceUpdated(revision, id, starting, result) => {
      guard revision == model.auth_revision &&
        model.auth is Authorizing(flow, _) &&
        flow.id == id else {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => {
          guard status.request_id == id &&
            (
              starting ||
              status.status.device_flow.map(flow => flow.id) == Some(id)
            ) else {
            return (model, @rabbita.none)
          }
          finish_sign_in(model, status.status, emit)
        }
        Err(error) => {
          let retry = match error {
            @github_client.HttpRequestError(status~, code~, ..) =>
              code == "network_error" || status >= 500 || code == "rate_limit"
            _ => false
          }
          if retry {
            let next = with_auth(
              model,
              Authorizing(
                {
                  ..flow,
                  retry_after: Int::min(60, Int::max(5, flow.retry_after * 2)),
                  message: "Connection interrupted. Sign-in will retry automatically.",
                },
                "",
              ),
            )
            (next, device_poll_request(next, emit))
          } else {
            (
              with_auth(model, AuthFailed(comment_failure_message(error))),
              @rabbita.none,
            )
          }
        }
      }
    }
    CancelSignIn => {
      guard auth_device_id(model.auth) is Some(id) else {
        return (model, @rabbita.none)
      }
      let revision = model.auth_revision + 1
      let next = with_auth(
        { ..model, auth_revision: revision, },
        DeviceCancelling(id, ""),
      )
      (
        next,
        @github_client.auth_device_request(@github_client.Cancel, id, 0, result => {
          emit(Auth(DeviceCancelFinished(revision, id, result)))
        }),
      )
    }
    DeviceCancelFinished(revision, id, result) => {
      guard revision == model.auth_revision &&
        model.auth is DeviceCancelling(current, _) &&
        current == id else {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => {
          guard status.request_id == id else { return (model, @rabbita.none) }
          // An expired account identity stays available for draft recovery.
          let (next, command, _) = apply_auth_status(
            model,
            status.status,
            false,
            emit,
          )
          (next, command)
        }
        Err(_) =>
          (
            with_auth(
              model,
              DeviceCancelling(
                id, "Cancellation could not be confirmed. Retry cancellation.",
              ),
            ),
            @rabbita.none,
          )
      }
    }
    CopyDeviceCode => {
      guard model.auth is Authorizing(flow, _) && !flow.user_code.is_empty() else {
        return (model, @rabbita.none)
      }
      (
        model,
        @cmd.custom_cmd(scheduler => {
          copy_device_code(flow.user_code, ok => {
            scheduler.add(
              emit(Auth(DeviceCodeCopied(model.auth_revision, flow.id, ok))),
            )
          })
        }),
      )
    }
    DeviceCodeCopied(revision, id, ok) => {
      guard revision == model.auth_revision &&
        model.auth is Authorizing(flow, _) &&
        flow.id == id else {
        return (model, @rabbita.none)
      }
      (
        with_auth(
          model,
          Authorizing(
            flow,
            if ok {
              "Code copied."
            } else {
              "Select and copy the code manually."
            },
          ),
        ),
        @rabbita.none,
      )
    }
    Logout => {
      let next = with_auth(
        {
          ..model,
          auth_revision: model.auth_revision + 1,
          restore_pending: false,
        },
        AuthChecking,
      )
      (next, auth_logout_request(next.auth_revision, emit))
    }
    AuthLogoutFinished(revision, result) => {
      guard revision == model.auth_revision else {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => {
          let (next, command, _) = apply_auth_status(model, status, true, emit)
          (next, command)
        }
        Err(error) =>
          (
            with_auth(model, AuthFailed(comment_failure_message(error))),
            @rabbita.none,
          )
      }
    }
  }
}

///|
extern "js" fn new_auth_attempt_id() -> String = "() => crypto.randomUUID()"

///|
extern "js" fn copy_device_code(
  code : String,
  completed : (Bool) -> Unit,
) -> Unit =
  #| (code, completed) => {
  #|   if (!navigator.clipboard?.writeText) { completed(false); return; }
  #|   navigator.clipboard.writeText(code).then(() => completed(true), () => completed(false));
  #| }
