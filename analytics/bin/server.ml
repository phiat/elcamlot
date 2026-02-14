(** CarScope Analytics Service — Dream HTTP server *)

(** Check if result contains a validation error and return appropriate status *)
let respond_with_result result =
  match result with
  | `Assoc fields when List.mem_assoc "error" fields ->
    Dream.json ~status:(`Status 422) (Yojson.Safe.to_string result)
  | _ ->
    Dream.json (Yojson.Safe.to_string result)

let () =
  Dream.run ~port:8080 ~interface:"0.0.0.0"
  @@ Dream.logger
  @@ Dream.router [

    Dream.get "/health" (fun _ ->
      Dream.json {|{"status":"ok"}|});

    Dream.post "/analyze" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Stats.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/deal-score" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Scoring.deal_score json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/depreciation" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Depreciation.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));
  ]
