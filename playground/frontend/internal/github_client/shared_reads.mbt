///|
fn shared_request(request : @protocol.GitHubRequest) -> Bool {
  request is (PullGet(_) | CompareGet(_) | PullFiles(_) | ContentGet(_))
}

///|
fn Client::cancel_reads(self : Client, owner : (Int32) -> Bool) -> Unit {
  let entries = self.workspace.reads.iter().collect()
  for (key, pending) in entries {
    let remaining : Array[ReadWaiter] = []
    let cancelled : Array[ReadWaiter] = []
    for waiter in pending.waiters {
      if owner(waiter.owner) {
        cancelled.push(waiter)
      } else {
        remaining.push(waiter)
      }
    }
    pending.waiters = remaining
    if remaining.is_empty() {
      pending.active = false
      self.workspace.reads.remove(key)
      self.cancel_pending(p => p.generation == pending.wire_owner)
      // Anonymous reads live in the public transport's own subscription map.
      self.cancel_public_owner(pending.wire_owner)
    }
    for waiter in cancelled {
      (waiter.done)(Err(Cancelled))
    }
  }
}

///|
fn Client::read(
  self : Client,
  request : @protocol.GitHubRequest,
  owner : Int32,
  done : (Result[@protocol.RpcValue, Error]) -> Unit,
  fresh~ : Bool = false,
  background~ : Bool = false,
) -> Unit {
  self.cancel_before(Int32::max(0, owner))
  if owner > 0 && owner < self.generation {
    done(Err(Cancelled))
    return
  }
  let w = self.workspace
  let encoded = request.encode().stringify()
  if request is ContentGet(args) &&
    full_sha(args.revision) &&
    !fresh &&
    w.cached(encoded, @browser.date_now()) is Some(Source(source)) {
    @metrics.counter("source_cache_hits", 1)
    done(Ok(Content(source)))
    return
  }
  w.serial += 1
  let key = if fresh {
    "\{w.epoch}:verify:\{w.serial}:\{encoded}"
  } else {
    "\{w.epoch}:read:\{encoded}"
  }
  let waiter = { owner, done, }
  if w.reads.get(key) is Some(pending) {
    pending.waiters.push(waiter)
    @metrics.counter("shared_read_joins", 1)
    return
  }
  let epoch = w.epoch
  let pending : SharedRead = {
    wire_owner: -w.serial,
    active: true,
    waiters: [waiter],
  }
  w.reads[key] = pending
  self.rpc_network(
    request,
    pending.wire_owner,
    value => value,
    result => {
      guard pending.active && w.epoch == epoch else { return }
      // Visibility can change before the reducer receives its DOM event.
      // Release only background subscriptions before adopting a source blob.
      if !(self.transport.visible)() {
        self.stop_prefetch()
        guard pending.active else { return }
      }
      pending.active = false
      w.reads.remove(key)
      if result is Ok(Content(source)) &&
        request is ContentGet(args) &&
        full_sha(args.revision) &&
        source.size <= @github.MAX_SOURCE_BYTES {
        self.cache_payload(encoded, Source(source), @browser.date_now())
      }
      let waiters = pending.waiters
      pending.waiters = []
      for waiter in waiters {
        if waiter.owner <= 0 || waiter.owner >= self.generation {
          (waiter.done)(result)
        }
      }
    },
    background~,
    fresh~,
  )
}

///|
fn[T] Client::rpc(
  self : Client,
  request : @protocol.GitHubRequest,
  generation : Int32,
  select : (@protocol.RpcValue) -> T raise,
  done : (Result[T, Error]) -> Unit,
) -> Unit {
  let writing = request
    is (IssueCommentCreate(_)
    | ReviewCommentCreate(_)
    | CommitCommentCreate(_)
    | ReviewReplyCreate(_)
    | IssueCommentDelete(_)
    | ReviewCommentDelete(_)
    | CommitCommentDelete(_)
    | PullFileViewedSet(_)
    | PullRebaseMerge(_))
  if writing && self.authenticated {
    if self.workspace.checking {
      let epoch = self.workspace.epoch
      self.workspace.deferred.push({
        resolve: () => {
          if epoch == self.workspace.epoch {
            self.rpc(request, generation, select, done)
          }
        },
        reject: error => {
          if epoch == self.workspace.epoch && generation >= self.generation {
            done(Err(error))
          }
        },
      })
      return
    } else if self.workspace.identity_error is Some(error) {
      done(Err(error))
      return
    }
  }
  if shared_request(request) {
    self.read(request, generation, result => {
      done(
        match result {
          Err(error) => Err(error)
          Ok(value) =>
            Ok(select(value)) catch {
              _ => Err(invalid_response("Unexpected RPC result kind."))
            }
        },
      )
    })
  } else {
    self.rpc_network(request, generation, select, done)
  }
}

///|
pub fn get_pull_fresh(
  args : @protocol.PullGet,
  generation : Int32,
  emit : @rabbita.Emit[Result[@protocol.ApiPull, Error]],
) -> @rabbita.Cmd {
  command(
    done => {
      client.read(
        PullGet(args),
        generation,
        result => {
          done(
            match result {
              Ok(Pull(pull)) => Ok(pull)
              Err(error) => Err(error)
              _ => Err(invalid_response("Unexpected pull metadata result."))
            },
          )
        },
        fresh=true,
      )
    },
    emit,
  )
}
