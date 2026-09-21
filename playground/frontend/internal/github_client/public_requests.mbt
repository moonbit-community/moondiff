///|
fn full_sha(value : String) -> Bool {
  (value.length() == 40 || value.length() == 64) && @protocol.valid_sha(value)
}

///|
fn immutable_public_request(request : @protocol.GitHubRequest) -> Bool {
  match request {
    CommitGet(p) => full_sha(p.sha)
    CompareGet(p) => full_sha(p.base) && full_sha(p.head)
    ContentGet(p) => full_sha(p.revision)
    _ => false
  }
}

///|
fn public_decode(
  request : @protocol.GitHubRequest,
  raw : Json,
) -> @protocol.RpcValue raise {
  let value = @protocol.normalize_github(raw)
  try {
    match request {
      CommitGet(_) => Commit(@protocol.decode_github(value))
      PullGet(_) => Pull(@protocol.decode_github(value))
      CompareGet(_) => Compare(@protocol.decode_github(value))
      PullFiles(_) => Files(@protocol.decode_github(value))
      ContentGet(_) => {
        let source : @protocol.ApiSource = @protocol.decode_github(value)
        guard source.size <= 1048576 else {
          raise HttpRequestError(
            status=413,
            code="source_too_large",
            detail="Cannot render: one side is larger than 1 MiB.",
          )
        }
        ignore(source.decode())
        Content(source)
      }
      _ =>
        raise HttpRequestError(
          status=400,
          code="operation_not_allowed",
          detail="This request cannot be read from the public GitHub API.",
        )
    }
  } catch {
    @protocol.ProtocolError(_, detail) =>
      raise HttpRequestError(
        status=502,
        code="invalid_github_response",
        detail~,
      )
    error => raise error
  }
}

///|
fn public_comments_decode(
  target : @protocol.CommentTarget,
  first : Array[Json],
  second : Array[Json],
) -> @protocol.RpcValue raise {
  try {
    match target {
      Pull(_) =>
        Comments({
          issue_comments: @protocol.decode_github(Json::array(first)),
          review_comments: @protocol.decode_github(Json::array(second)),
          commit_comments: [],
        })
      Commit(_) | PullCommit(..) =>
        Comments({
          issue_comments: [],
          review_comments: [],
          commit_comments: @protocol.decode_github(Json::array(first)),
        })
    }
  } catch {
    @protocol.ProtocolError(_, detail) =>
      raise HttpRequestError(
        status=502,
        code="invalid_github_response",
        detail~,
      )
    error => raise error
  }
}

///|
fn Client::cancel_public(self : Client, all : Bool) -> Unit {
  let entries = self.public_pending.iter().collect()
  for (key, pending) in entries {
    if pending.active {
      let remaining : Array[PublicWaiter] = []
      for waiter in pending.waiters {
        if all || (waiter.generation > 0 && waiter.generation < self.generation) {
          (waiter.done)(Err(Cancelled))
        } else {
          remaining.push(waiter)
        }
      }
      pending.waiters = remaining
      if remaining.is_empty() {
        pending.active = false
        self.public_pending.remove(key)
        (pending.abort)()
      }
    }
  }
}

///|
fn Client::cache_public(
  self : Client,
  key : String,
  value : @protocol.RpcValue,
) -> Unit {
  let bytes = @utf8.encode(ToJson::to_json(value).stringify()).length()
  if bytes > 4 * 1048576 {
    return
  }
  while self.public_cache.length() >= 8 ||
        self.public_cache_bytes + bytes > 16 * 1048576 {
    let old = self.public_cache[0]
    self.public_cache_bytes -= old.bytes
    self.public_cache = self.public_cache[1:].to_owned()
  }
  self.public_cache.push({ key, value, bytes, })
  self.public_cache_bytes += bytes
}

///|
fn Client::finish_public(
  self : Client,
  key : String,
  request : @protocol.GitHubRequest,
  pending : PublicPending,
  result : Result[@protocol.RpcValue, Error],
) -> Unit {
  if !pending.active {
    return
  }
  pending.active = false
  self.public_pending.remove(key)
  if result is Ok(value) && immutable_public_request(request) {
    self.cache_public(key, value)
  }
  for waiter in pending.waiters {
    if waiter.generation == 0 || waiter.generation >= self.generation {
      (waiter.done)(result)
    } else {
      (waiter.done)(Err(Cancelled))
    }
  }
}

///|
fn Client::comment_pages(
  self : Client,
  pending : PublicPending,
  path : String,
  page : Int,
  accumulated : Array[Json],
  done : (Result[Array[Json], Error]) -> Unit,
) -> Unit {
  if !pending.active {
    return
  }
  pending.abort = public_fetch("\{path}?per_page=100&page=\{page}", false, result => {
    if !pending.active {
      return
    }
    match result {
      Err(error) => done(Err(error))
      Ok(Array(values)) => {
        if values.length() > 100 {
          done(
            Err(
              HttpRequestError(
                status=502,
                code="invalid_github_response",
                detail="GitHub returned an invalid comment page.",
              ),
            ),
          )
          return
        }
        let normalized : Result[Array[Json], Error] = Ok(
          values.map(value => @protocol.comment_for_protocol(value)),
        ) catch {
          @protocol.ProtocolError(_, detail) =>
            Err(
              HttpRequestError(
                status=502,
                code="invalid_github_response",
                detail~,
              ),
            )
          error => Err(error)
        }
        match normalized {
          Err(error) => done(Err(error))
          Ok(values) => {
            for value in values {
              accumulated.push(value)
            }
            if values.length() == 100 {
              if page == 100 {
                done(
                  Err(
                    HttpRequestError(
                      status=422,
                      code="pagination_limit",
                      detail="GitHub returned more comment pages than Moondiff can safely load.",
                    ),
                  ),
                )
              } else {
                self.comment_pages(pending, path, page + 1, accumulated, done)
              }
            } else {
              done(Ok(accumulated))
            }
          }
        }
      }
      Ok(_) =>
        done(
          Err(
            HttpRequestError(
              status=502,
              code="invalid_github_response",
              detail="GitHub returned an invalid comment page.",
            ),
          ),
        )
    }
  })
}

///|
fn Client::perform_public(
  self : Client,
  request : @protocol.GitHubRequest,
  pending : PublicPending,
  done : (Result[@protocol.RpcValue, Error]) -> Unit,
) -> Unit {
  match request {
    CommentsList(args) => {
      let paths = args.public_paths()
      self.comment_pages(pending, paths[0], 1, [], first => {
        match first {
          Err(error) => done(Err(error))
          Ok(first) =>
            if paths.length() == 1 {
              done(
                Ok(public_comments_decode(args.target, first, [])) catch {
                  error => Err(error)
                },
              )
            } else {
              self.comment_pages(pending, paths[1], 1, [], second => {
                match second {
                  Err(error) => done(Err(error))
                  Ok(second) =>
                    done(
                      Ok(public_comments_decode(args.target, first, second)) catch {
                        error => Err(error)
                      },
                    )
                }
              })
            }
        }
      })
    }
    _ => {
      let path = request.public_path().unwrap()
      pending.abort = public_fetch(path, request is ContentGet(_), result => {
        done(
          match result {
            Err(error) => Err(error)
            Ok(raw) =>
              Ok(public_decode(request, raw)) catch {
                error => Err(error)
              }
          },
        )
      })
    }
  }
}

///|
fn Client::public_rpc(
  self : Client,
  request : @protocol.GitHubRequest,
  generation : Int,
  done : (Result[@protocol.RpcValue, Error]) -> Unit,
) -> Unit {
  self.cancel_before(generation)
  if generation > 0 && generation < self.generation {
    done(Err(Cancelled))
    return
  }
  let key = request.encode().stringify()
  if immutable_public_request(request) {
    for entry in self.public_cache {
      if entry.key == key {
        done(Ok(entry.value))
        return
      }
    }
  }
  let waiter : PublicWaiter = { generation, done, }
  if self.public_pending.get(key) is Some(pending) {
    pending.waiters.push(waiter)
    return
  }
  let pending : PublicPending = {
    waiters: [waiter],
    abort: () => (),
    active: true,
  }
  self.public_pending[key] = pending
  self.perform_public(request, pending, result => {
    self.finish_public(key, request, pending, result)
  })
}
