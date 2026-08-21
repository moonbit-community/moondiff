///|
fn extension_host_enabled() -> Bool {
  has_extension_host()
}

///|
extern "js" fn has_extension_host() -> Bool =
  #| () => Boolean(globalThis.__MOONDIFF_EXTENSION_HOST__?.request)

///|
fn[T : FromJson] gateway_json_request(
  operation : String,
  repository : RepositoryRef,
  primary : String,
  secondary : String,
  page : Int,
  generation : Int,
  msg : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    send_gateway_json_request(
      operation,
      repository.owner,
      repository.repo,
      primary,
      secondary,
      page,
      generation,
      completed=(ok, status, code, status_text, response_body) => {
        let result : Result[T, Error] = if ok {
          try @json.from_json(@json.parse(response_body)) catch {
            error => Err(GitHubRequestError(error.to_string()))
          } noraise {
            value => Ok(value)
          }
        } else {
          let suffix = if status_text.trim().is_empty() {
            ""
          } else {
            " \{status_text}"
          }
          if code.trim().is_empty() {
            Err(
              GitHubRequestError(
                "GitHub request failed: HTTP \{status}\{suffix}",
              ),
            )
          } else {
            Err(ExtensionRequestError(status~, code~, detail=status_text))
          }
        }
        scheduler.add(msg(result))
      },
      failed=detail => {
        scheduler.add(
          msg(Err(GitHubRequestError("GitHub request failed: \{detail}"))),
        )
      },
    )
  })
}

///|
extern "js" fn send_gateway_json_request(
  operation : String,
  owner : String,
  repo : String,
  primary : String,
  secondary : String,
  page : Int,
  generation : Int,
  completed~ : (Bool, Int, String, String, String) -> Unit,
  failed~ : (String) -> Unit,
) =
  #| (operation, owner, repo, primary, secondary, page, generation, completed, failed) => {
  #|   const args = { owner, repo };
  #|   const withoutNulls = (value) => {
  #|     if (Array.isArray(value)) return value.map(withoutNulls);
  #|     if (!value || typeof value !== "object") return value;
  #|     return Object.fromEntries(Object.entries(value)
  #|       .filter(([, child]) => child !== null && child !== undefined)
  #|       .map(([key, child]) => [key, withoutNulls(child)]));
  #|   };
  #|   let path;
  #|   switch (operation) {
  #|     case "github.commit.get":
  #|       args.sha = primary;
  #|       args.page = page;
  #|       path = `/repos/${owner}/${repo}/commits/${primary}?per_page=100&page=${page}`;
  #|       break;
  #|     case "github.pull.get":
  #|       args.number = primary;
  #|       path = `/repos/${owner}/${repo}/pulls/${primary}`;
  #|       break;
  #|     case "github.compare.get":
  #|       args.base = primary;
  #|       args.head = secondary;
  #|       path = `/repos/${owner}/${repo}/compare/${primary}...${secondary}`;
  #|       break;
  #|     case "github.pull.files":
  #|       args.number = primary;
  #|       args.page = page;
  #|       path = `/repos/${owner}/${repo}/pulls/${primary}/files?per_page=100&page=${page}`;
  #|       break;
  #|     default:
  #|       failed(`Unsupported gateway operation: ${operation}`);
  #|       return;
  #|   }
  #|   const host = globalThis.__MOONDIFF_EXTENSION_HOST__;
  #|   if (host?.request) {
  #|     host.request(operation, args, { generation })
  #|       .then((value) => completed(true, 200, "", "", JSON.stringify(withoutNulls(value))))
  #|       .catch((error) => completed(
  #|         false,
  #|         Number.isInteger(error?.status) ? error.status : 0,
  #|         typeof error?.code === "string" ? error.code : "extension_error",
  #|         error?.message || String(error),
  #|         "",
  #|       ));
  #|     return;
  #|   }
  #|   fetch(`https://api.github.com${path}`, {
  #|     method: "GET",
  #|     cache: "no-cache",
  #|     headers: {
  #|       Accept: "application/vnd.github+json",
  #|       "X-GitHub-Api-Version": "2026-03-10",
  #|     },
  #|   }).then((response) => {
  #|     if (!response.ok) {
  #|       return response.text().catch(() => "").then((body) => {
  #|         let detail = response.statusText || "";
  #|         try { detail = JSON.parse(body)?.message || detail; } catch {}
  #|         completed(false, response.status, "", detail, "");
  #|       });
  #|     }
  #|     return response.text().then((body) => {
  #|       let normalized = body;
  #|       try { normalized = JSON.stringify(withoutNulls(JSON.parse(body))); } catch {}
  #|       completed(true, response.status, "", response.statusText || "", normalized);
  #|     });
  #|   }).catch((error) => failed(error?.message || String(error)));
  #| }

///|
fn gateway_source_request(
  location : SourceLocation,
  generation : Int,
  index : Int,
  side : SourceSide,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    send_gateway_source_request(
      location.repository.owner,
      location.repository.repo,
      location.path,
      location.revision,
      generation,
      completed=(ok, status, code, status_text, content_type, bytes) => {
        let result : Result[(String, Bytes), Error] = if ok {
          Ok((content_type, bytes))
        } else {
          let suffix = if status_text.trim().is_empty() {
            ""
          } else {
            " \{status_text}"
          }
          if code.trim().is_empty() {
            Err(
              GitHubRequestError(
                "GitHub content request failed: HTTP \{status}\{suffix}",
              ),
            )
          } else {
            Err(ExtensionRequestError(status~, code~, detail=status_text))
          }
        }
        scheduler.add(emit(SourceLoaded(generation, index, side, result)))
      },
      failed=detail => {
        scheduler.add(
          emit(
            SourceLoaded(
              generation,
              index,
              side,
              Err(
                GitHubRequestError("GitHub content request failed: \{detail}"),
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
extern "js" fn send_gateway_source_request(
  owner : String,
  repo : String,
  path : String,
  revision : String,
  generation : Int,
  completed~ : (Bool, Int, String, String, String, Bytes) -> Unit,
  failed~ : (String) -> Unit,
) =
  #| (owner, repo, path, revision, generation, completed, failed) => {
  #|   const host = globalThis.__MOONDIFF_EXTENSION_HOST__;
  #|   if (host?.request) {
  #|     host.request("github.content.get", { owner, repo, path, ref: revision }, { generation })
  #|       .then((value) => {
  #|         const binary = atob(value.base64 || "");
  #|         const bytes = new Uint8Array(binary.length);
  #|         for (let index = 0; index < binary.length; index += 1) {
  #|           bytes[index] = binary.charCodeAt(index);
  #|         }
  #|         completed(true, 200, "", "", value.contentType || "application/octet-stream", bytes);
  #|       })
  #|       .catch((error) => completed(
  #|         false,
  #|         Number.isInteger(error?.status) ? error.status : 0,
  #|         typeof error?.code === "string" ? error.code : "extension_error",
  #|         error?.message || String(error),
  #|         "",
  #|         new Uint8Array(),
  #|       ));
  #|     return;
  #|   }
  #|   const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  #|   const url = `https://raw.githubusercontent.com/${owner}/${repo}/${revision}/${encodedPath}`;
  #|   fetch(url, { method: "GET", cache: "no-cache" }).then((response) => {
  #|     if (!response.ok) {
  #|       completed(false, response.status, "", response.statusText || "", "", new Uint8Array());
  #|       return;
  #|     }
  #|     return response.arrayBuffer().then((buffer) => {
  #|       completed(
  #|         true,
  #|         response.status,
  #|         "",
  #|         response.statusText || "",
  #|         response.headers.get("content-type") || "application/octet-stream",
  #|         new Uint8Array(buffer),
  #|       );
  #|     });
  #|   }).catch((error) => failed(error?.message || String(error)));
  #| }
