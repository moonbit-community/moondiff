///|
extern "js" fn fetch_public_text(
  path : String,
  source : Bool,
  sha : Bool,
  completed : (Int, String, Bool) -> Unit,
  failed : (String, String) -> Unit,
) -> () -> Unit =
  #| (path, source, sha, completed, failed) => {
  #|   const controller = new AbortController();
  #|   let timedOut = false;
  #|   const timeout = setTimeout(() => { timedOut = true; controller.abort(); }, 30000);
  #|   (async () => {
  #|     try {
  #|       const response = await fetch('https://api.github.com' + path, {
  #|         method: 'GET', mode: 'cors', credentials: 'omit', cache: 'no-store',
  #|         redirect: 'error', signal: controller.signal,
  #|         headers: { Accept: sha ? 'application/vnd.github.sha' : source ? 'application/vnd.github.raw+json' : 'application/vnd.github+json' },
  #|       });
  #|       const limit = source ? 1048576 : 8388608;
  #|       const chunks = [];
  #|       let size = 0;
  #|       const reader = response.body.getReader();
  #|       while (true) {
  #|         const { done, value } = await reader.read();
  #|         if (done) break;
  #|         size += value.byteLength;
  #|         if (size > limit) {
  #|           await reader.cancel();
  #|           failed(source ? 'source_too_large' : 'response_too_large',
  #|             source ? 'Cannot render: one side is larger than 1 MiB.' : 'GitHub response exceeds 8 MiB.');
  #|           return;
  #|         }
  #|         chunks.push(value);
  #|       }
  #|       const bytes = new Uint8Array(size);
  #|       let offset = 0;
  #|       for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  #|       let text;
  #|       if (sha && response.ok) {
  #|         text = JSON.stringify(new TextDecoder('utf-8', { fatal: true }).decode(bytes).trim());
  #|       } else if (source && response.ok) {
  #|         let binary = '';
  #|         for (let i = 0; i < size; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  #|         text = JSON.stringify({ base64: btoa(binary), size,
  #|           content_type: response.headers.get('Content-Type') || 'application/octet-stream' });
  #|       } else {
  #|         text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  #|       }
  #|       const rateLimited = response.status === 429 ||
  #|         (response.status === 403 && (response.headers.get('X-RateLimit-Remaining') === '0' || response.headers.has('Retry-After')));
  #|       completed(response.status, text, rateLimited);
  #|     } catch (error) {
  #|       if (timedOut) {
  #|         failed('network_error', 'GitHub did not respond within 30 seconds. Try again.');
  #|         return;
  #|       }
  #|       if (controller.signal.aborted) return;
  #|       failed('network_error', 'Could not reach GitHub from this browser (network or CORS policy): ' + (error.message || String(error)));
  #|     } finally {
  #|       clearTimeout(timeout);
  #|     }
  #|   })();
  #|   return () => controller.abort();
  #| }

///|
fn github_response(
  status : Int,
  text : String,
  rate_limited : Bool,
) -> Json raise {
  if status < 200 || status >= 300 {
    let payload = @json.parse(text) catch { _ => Json::null() }
    let message = match payload {
      Object(fields) =>
        match fields.get("message") {
          Some(String(message)) => message
          _ => "GitHub request failed."
        }
      _ => "GitHub request failed."
    }
    let rate_limited = rate_limited ||
      (status == 403 && message.to_lower().contains("rate limit"))
    let (code, detail) = if rate_limited {
      (
        "rate_limit", "GitHub's public API rate limit was reached. Sign in or try again later.",
      )
    } else if status == 404 {
      (
        "not_found_or_not_installed", "GitHub could not find this public resource. Sign in for private repositories.",
      )
    } else if status == 403 {
      ("permission_denied", message)
    } else {
      ("github_http_\{status}", message)
    }
    raise HttpRequestError(status~, code~, detail~)
  }
  @json.parse(text) catch {
    _ =>
      raise HttpRequestError(
        status=502,
        code="invalid_github_response",
        detail="GitHub returned invalid JSON.",
      )
  }
}

///|
fn public_fetch(
  path : String,
  source : Bool,
  done : (Result[Json, Error]) -> Unit,
  sha? : Bool = false,
) -> () -> Unit {
  fetch_public_text(
    path,
    source,
    sha,
    (status, text, rate_limited) => {
      done(
        Ok(github_response(status, text, rate_limited)) catch {
          error => Err(error)
        },
      )
    },
    (code, detail) => done(Err(HttpRequestError(status=0, code~, detail~))),
  )
}
