///|
pub fn[A : ToJson, T : FromJson] extension_rpc_request(
  operation : String,
  args : A,
  generation : Int,
  msg : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  extension_rpc_json(
    operation,
    ToJson::to_json(args).stringify(),
    generation,
    msg,
  )
}

///|
pub fn[T : FromJson] extension_rpc_json(
  operation : String,
  args_json : String,
  generation : Int,
  msg : @rabbita.Emit[Result[T, Error]],
) -> @rabbita.Cmd {
  @cmd.custom_cmd(scheduler => {
    send_extension_rpc(
      operation,
      args_json,
      generation,
      completed=(ok, status, code, detail, response_body) => {
        let result : Result[T, Error] = if ok {
          try @json.from_json(@json.parse(response_body)) catch {
            error =>
              Err(
                ExtensionRequestError(
                  status=200,
                  code="invalid_extension_response",
                  detail=error.to_string(),
                ),
              )
          } noraise {
            value => Ok(value)
          }
        } else {
          Err(ExtensionRequestError(status~, code~, detail~))
        }
        scheduler.add(msg(result))
      },
      failed=detail => {
        scheduler.add(
          msg(
            Err(
              ExtensionRequestError(
                status=0,
                code="extension_bridge_error",
                detail~,
              ),
            ),
          ),
        )
      },
    )
  })
}

///|
extern "js" fn send_extension_rpc(
  operation : String,
  args_json : String,
  generation : Int,
  completed~ : (Bool, Int, String, String, String) -> Unit,
  failed~ : (String) -> Unit,
) =
  #| (operation, argsJson, generation, completed, failed) => {
  #|   const host = globalThis.__MOONDIFF_EXTENSION_HOST__;
  #|   if (!host?.request) {
  #|     failed("Commenting is only available in the Moondiff extension.");
  #|     return;
  #|   }
  #|   let args;
  #|   try { args = JSON.parse(argsJson); } catch (error) {
  #|     failed(error?.message || String(error));
  #|     return;
  #|   }
  #|   host.request(operation, args, { generation })
  #|     .then((value) => completed(true, 200, "", "", JSON.stringify(value)))
  #|     .catch((error) => completed(
  #|       false,
  #|       Number.isInteger(error?.status) ? error.status : 0,
  #|       typeof error?.code === "string" ? error.code : "extension_error",
  #|       error?.message || String(error),
  #|       "",
  #|     ));
  #| }
