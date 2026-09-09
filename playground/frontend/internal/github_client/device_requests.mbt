///|
pub(all) enum DeviceAction {
  Start
  Poll
  Retry
  Cancel
}

///|
fn Client::send_device(
  self : Client,
  action : DeviceAction,
  id : String,
  completed : (Result[@protocol.DeviceResponse, Error]) -> Unit,
  poll? : Bool = false,
) -> Unit {
  let (path, body) = match action {
    Start | Retry =>
      (
        "/api/auth/device/start",
        @protocol.DeviceStart::{ attempt_id: id, }.to_json(),
      )
    Poll =>
      (
        "/api/auth/device/poll",
        @protocol.DeviceAuthorization::{ authorization_id: id, }.to_json(),
      )
    Cancel =>
      (
        "/api/auth/device/cancel",
        @protocol.DeviceAuthorization::{ authorization_id: id, }.to_json(),
      )
  }
  self.send(
    path,
    body.stringify(),
    (result : Result[@protocol.DeviceResponse, Error]) => {
      let result : Result[@protocol.DeviceResponse, Error] = match result {
        Ok(response) =>
          if response.request_id != id ||
            (
              action is Poll &&
              response.status.device_flow.map(flow => flow.id) != Some(id)
            ) {
            Err(
              invalid_response("The server returned a different authorization."),
            )
          } else {
            self.status_sequence += 1
            self.adopt_status(response.status, poll)
            Ok(response)
          }
        Err(error) => Err(error)
      }
      completed(result)
    },
    auth=true,
    poll~,
  )
}

///|
fn Client::start(
  self : Client,
  id : String,
  completed : (Result[@protocol.DeviceResponse, Error]) -> Unit,
  poll? : Bool = false,
) -> Unit {
  let revision = self.auth_revision
  self.pending_start_id = Some(id)
  self.status(
    result => {
      if revision != self.auth_revision || self.pending_start_id != Some(id) {
        completed(Err(Cancelled))
        return
      }
      match result {
        Err(error) => completed(Err(error))
        Ok(_) =>
          self.send_device(
            Start,
            id,
            result => {
              if revision != self.auth_revision ||
                self.pending_start_id != Some(id) {
                completed(Err(Cancelled))
                return
              }
              if result is Ok(_) {
                self.pending_start_id = None
              }
              completed(result)
            },
            poll~,
          )
      }
    },
    poll~,
  )
}

///|
fn Client::schedule_poll(
  self : Client,
  action : DeviceAction,
  id : String,
  delay : Int,
  completed : (Result[@protocol.DeviceResponse, Error]) -> Unit,
) -> Unit {
  let owns = () => {
    self.device_id == Some(id) ||
    (action is Retry && self.pending_start_id == Some(id))
  }
  if !owns() {
    completed(Err(Cancelled))
    return
  }
  if self.poll_task is Some(task) {
    task.waiters.push(completed)
    return
  }
  self.sequence += 1
  let task : PollTask = {
    token: self.sequence,
    waiters: [completed],
    cancel_timer: () => (),
  }
  self.poll_task = Some(task)
  let revision = self.auth_revision
  let finish = result => {
    if self.poll_task is Some(current) && current.token == task.token {
      self.poll_task = None
      for waiter in task.waiters {
        waiter(result)
      }
    }
  }
  task.cancel_timer = (self.transport.delay)(
    Int::min(86400, Int::max(0, delay)) * 1000,
    () => {
      if revision != self.auth_revision || !owns() {
        finish(Err(Cancelled))
        return
      }
      if action is Retry {
        self.start(id, finish, poll=true)
      } else {
        self.send_device(Poll, id, finish, poll=true)
      }
    },
  )
}

///|
fn Client::device(
  self : Client,
  action : DeviceAction,
  id : String,
  delay : Int,
  completed : (Result[@protocol.DeviceResponse, Error]) -> Unit,
) -> Unit {
  match action {
    Poll | Retry => self.schedule_poll(action, id, delay, completed)
    Start => {
      self.invalidate_auth(false)
      self.start(id, completed)
    }
    Cancel => {
      self.invalidate_auth(false)
      let revision = self.auth_revision
      if self.csrf.is_empty() {
        self.status(result => {
          if revision != self.auth_revision {
            completed(Err(Cancelled))
            return
          }
          match result {
            Ok(_) => self.send_device(Cancel, id, completed)
            Err(error) => completed(Err(error))
          }
        })
      } else {
        self.send_device(Cancel, id, completed)
      }
    }
  }
}

///|
fn Client::logout(
  self : Client,
  completed : (Result[@protocol.ApiAuthStatus, Error]) -> Unit,
) -> Unit {
  self.invalidate_auth(true)
  let revision = self.auth_revision
  let send_logout = () => {
    self.send(
      "/api/auth/logout",
      "{}",
      result => {
        let result : Result[Unit, Error] = result
        if revision != self.auth_revision {
          completed(Err(Cancelled))
          return
        }
        match result {
          Err(error) => completed(Err(error))
          Ok(_) => {
            self.csrf = ""
            self.status(completed)
          }
        }
      },
      auth=true,
    )
  }
  if self.csrf.is_empty() {
    self.status(result => {
      if revision != self.auth_revision {
        completed(Err(Cancelled))
        return
      }
      match result {
        Err(error) => completed(Err(error))
        Ok(_) => send_logout()
      }
    })
  } else {
    send_logout()
  }
}
