(** CarScope Analytics Service — Dream HTTP server *)

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
        let result = Stats.analyze json in
        Dream.json (Yojson.Safe.to_string result)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/deal-score" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        let result = Scoring.deal_score json in
        Dream.json (Yojson.Safe.to_string result)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/depreciation" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        let result = Depreciation.analyze json in
        Dream.json (Yojson.Safe.to_string result)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));
  ]
