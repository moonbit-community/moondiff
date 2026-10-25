///|
fn ci_check_fixture(state : @protocol.ApiCiState) -> @protocol.ApiCiCheck {
  {
    name: "check",
    state,
    description: "description",
    details_url: None,
    source: CheckRun,
  }
}

///|
async test "CI reads keep results and report recoverable upstream failures" {
  let (checks, warnings) = read_ci_checks(
    () => [ci_check_fixture(Success)],
    "unavailable",
  )
  assert_eq(checks.length(), 1)
  assert_true(checks[0].state is Success)
  assert_true(warnings.is_empty())
  let failures : Array[Error] = [
    @common.RpcError(403, "permission_denied", "CI access denied"),
    @io.ReaderClosed,
  ]
  for error in failures {
    let (checks, warnings) = read_ci_checks(() => raise error, "unavailable")
    assert_true(checks.is_empty())
    assert_eq(warnings, ["unavailable"])
  }
  let (timed_out, warnings) = read_ci_checks(
    () => {
      @async.with_timeout(1, () => {
        @async.sleep(1000)
        [ci_check_fixture(Success)]
      })
    },
    "timed out",
  )
  assert_true(timed_out.is_empty())
  assert_eq(warnings, ["timed out"])
}

///|
priv suberror UnexpectedCiFailure

///|
async test "CI reads propagate unexpected failures" {
  try read_ci_checks(() => raise UnexpectedCiFailure, "unavailable") catch {
    UnexpectedCiFailure => ()
    error => raise error
  } noraise {
    _ => fail("Unexpected CI failure was hidden")
  }
}

///|
test "CI states normalize and summarize with failure then pending priority" {
  assert_true(check_run_state("queued", None) is Pending)
  assert_true(check_run_state("completed", Some("success")) is Success)
  assert_true(check_run_state("completed", Some("neutral")) is Neutral)
  assert_true(check_run_state("completed", Some("timed_out")) is Failure)
  assert_true(commit_status_state("error") is Failure)
  assert_true(ci_summary([]) is None)
  assert_true(ci_summary([ci_check_fixture(Neutral)]) is Some(Neutral))
  assert_true(
    ci_summary([ci_check_fixture(Neutral), ci_check_fixture(Success)])
    is Some(Success),
  )
  assert_true(
    ci_summary([ci_check_fixture(Success), ci_check_fixture(Pending)])
    is Some(Pending),
  )
  assert_true(
    ci_summary([
      ci_check_fixture(Pending),
      ci_check_fixture(Failure),
      ci_check_fixture(Success),
    ])
    is Some(Failure),
  )
  assert_eq(
    external_details_url(Some("https://example.com/check")),
    Some("https://example.com/check"),
  )
  assert_eq(
    external_details_url(Some("http://example.com/check")),
    Some("http://example.com/check"),
  )
  assert_true(external_details_url(Some("javascript:alert(1)")) is None)
}

///|
test "pull merge snapshots preserve unknown mergeability and reject malformed fields" {
  let snapshot = merge_snapshot({
    "base": { "sha": "1111111" },
    "head": { "sha": "aaaaaaa" },
    "state": "open",
    "draft": false,
    "merged": false,
    "mergeable": null,
    "rebaseable": true,
    "mergeable_state": "unknown",
  })
  assert_true(snapshot.mergeable is None)
  assert_true(snapshot.rebaseable is Some(true))
  assert_true(snapshot.open)
  let invalid : Array[Json] = [
    {
      "base": { "sha": "main" },
      "head": { "sha": "aaaaaaa" },
      "state": "open",
      "draft": false,
      "merged": false,
      "mergeable": true,
      "rebaseable": true,
      "mergeable_state": "clean",
    },
    {
      "base": { "sha": "1111111" },
      "head": { "sha": "aaaaaaa" },
      "state": "unknown",
      "draft": false,
      "merged": false,
      "mergeable": true,
      "rebaseable": true,
      "mergeable_state": "clean",
    },
  ]
  for value in invalid {
    try merge_snapshot(value) catch {
      @common.RpcError(502, "invalid_github_response", _) => ()
      error => raise error
    } noraise {
      _ => fail("Accepted malformed merge data")
    }
  }
}
