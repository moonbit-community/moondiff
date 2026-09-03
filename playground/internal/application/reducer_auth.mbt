///|
pub(all) enum AuthMsg {
  AuthStatusLoaded(Result[ApiAuthStatus, Error])
  ReactivationAuthStatusLoaded(Int, CommitRef, Result[ApiAuthStatus, Error])
  StartDeviceAuthorization
  DeviceAuthorizationStarted(Result[ApiAuthStatus, Error])
  PollDeviceAuthorization(String)
  DeviceAuthorizationPolled(String, Result[ApiAuthStatus, Error])
  CancelDeviceAuthorization(String)
  DeviceAuthorizationCancelled(String, Result[ApiAuthStatus, Error])
  CopyDeviceCode
  DeviceCodeCopied(String)
  DeviceCodeCopyFailed(String, String)
  Logout
  AuthLogoutFinished(Result[ApiAuthStatus, Error])
}

///|
fn update_auth(
  model : Model,
  msg : AuthMsg,
  emit : @rabbita.Emit[Msg],
) -> (Model, @rabbita.Cmd) {
  match msg {
    AuthStatusLoaded(result) =>
      match result {
        Ok(status) => apply_auth_status(model, status, true, false, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    ReactivationAuthStatusLoaded(generation, reference, result) => {
      guard generation == model.generation && model.route == Some(reference) else {
        return (model, @rabbita.none)
      }
      match result {
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
        Ok(status) => {
          let was_signed_in = model.review.auth is SignedIn(_)
          let (synced, poll_command) = apply_auth_status(
            model, status, true, false, emit,
          )
          if !was_signed_in &&
            status.authenticated &&
            model.phase is LoadFailed(_) {
            let (reloading, load_command) = begin_change_load(
              synced, reference, emit,
            )
            return (reloading, @rabbita.batch([poll_command, load_command]))
          }
          (
            with_review(
              synced,
              review_state_with_comments(synced.review, CommentsLoading),
            ),
            @rabbita.batch([
              poll_command,
              comments_request(reference, generation, emit),
            ]),
          )
        }
      }
    }
    StartDeviceAuthorization =>
      if extension_host_enabled() {
        (
          with_review(model, review_state_with_auth(model.review, AuthChecking)),
          auth_device_start_request(emit),
        )
      } else {
        (model, @rabbita.none)
      }
    DeviceAuthorizationStarted(result) =>
      match result {
        Ok(status) if status.authenticated =>
          finish_device_sign_in(model, status, emit)
        Ok(status) => apply_auth_status(model, status, false, false, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    PollDeviceAuthorization(flow_id) =>
      if extension_host_enabled() && device_flow_is_authorizing(model, flow_id) {
        (model, auth_device_poll_request(flow_id, emit))
      } else {
        (model, @rabbita.none)
      }
    DeviceAuthorizationPolled(flow_id, result) => {
      if !device_flow_is_current(model, flow_id) {
        return (model, @rabbita.none)
      }
      if device_flow_is_cancelling(model, flow_id) {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) if status.authenticated =>
          finish_device_sign_in(model, status, emit)
        Ok(status) => {
          guard status.device_flow is Some(flow) && flow.flow_id == flow_id else {
            return (model, @rabbita.none)
          }
          apply_auth_status(model, status, true, true, emit)
        }
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    }
    CancelDeviceAuthorization(flow_id) => {
      guard extension_host_enabled() &&
        model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(model.review, DeviceCancelling(device)),
        ),
        auth_device_cancel_request(flow_id, emit),
      )
    }
    DeviceAuthorizationCancelled(flow_id, result) => {
      if !device_flow_is_cancelling(model, flow_id) {
        return (model, @rabbita.none)
      }
      match result {
        Ok(status) => apply_auth_status(model, status, false, false, emit)
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
    }
    CopyDeviceCode => {
      guard model.review.auth is DeviceAuthorizing(device) else {
        return (model, @rabbita.none)
      }
      (
        model,
        @clipboard.copy(
          Text(device.user_code),
          copied=emit(Auth(DeviceCodeCopied(device.flow_id))),
          failed=message => {
            emit(Auth(DeviceCodeCopyFailed(device.flow_id, message)))
          },
        ),
      )
    }
    DeviceCodeCopied(flow_id) => {
      guard model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(
            model.review,
            DeviceAuthorizing({ ..device, copy_status: DeviceCodeCopyDone, }),
          ),
        ),
        @rabbita.none,
      )
    }
    DeviceCodeCopyFailed(flow_id, message) => {
      guard model.review.auth is DeviceAuthorizing(device) &&
        device.flow_id == flow_id else {
        return (model, @rabbita.none)
      }
      (
        with_review(
          model,
          review_state_with_auth(
            model.review,
            DeviceAuthorizing({
              ..device,
              copy_status: DeviceCodeCopyError(message),
            }),
          ),
        ),
        @rabbita.none,
      )
    }
    Logout =>
      if extension_host_enabled() {
        (
          with_review(model, review_state_with_auth(model.review, AuthChecking)),
          auth_logout_request(emit),
        )
      } else {
        (model, @rabbita.none)
      }
    AuthLogoutFinished(result) =>
      match result {
        Ok(status) =>
          (
            with_review(model, {
              auth: auth_status_from_api(status),
              comments: model.review.comments,
              draft: None,
            }),
            @rabbita.none,
          )
        Err(error) =>
          (
            with_review(
              model,
              review_state_with_auth(
                model.review,
                AuthFailed(comment_failure_message(error)),
              ),
            ),
            @rabbita.none,
          )
      }
  }
}
