(** Elcamlot Analytics Service — Dream HTTP server *)

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

    Dream.post "/outliers" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Outliers.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/histogram" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Histogram.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/data-quality" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Quality.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/volatility" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Volatility.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/correlation" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Correlation.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/returns" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Returns.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/moving-averages" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Moving_averages.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/momentum" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Momentum.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/bayesian-estimate" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Bayesian.estimate json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/simulate" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Monte_carlo.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));

    Dream.post "/buy-timing" (fun request ->
      let%lwt body = Dream.body request in
      match Yojson.Safe.from_string body with
      | json ->
        respond_with_result (Buy_timing.analyze json)
      | exception Yojson.Json_error msg ->
        Dream.json ~status:`Bad_Request
          (Printf.sprintf {|{"error":"Invalid JSON: %s"}|} msg));
  ]
