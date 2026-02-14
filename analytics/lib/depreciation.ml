(** Depreciation curve fitting.

    Given price history (time, price) pairs, fits an exponential
    decay curve: price(t) = P0 * e^(-lambda * t)

    where t is time in years from first observation.
*)

let float_of_json = function
  | `Int n -> Float.of_int n
  | `Float f -> f
  | _ -> 0.0

(** Parse ISO 8601 timestamp to Unix epoch seconds (simplified) *)
let parse_time s =
  (* Simplified: just extract year-month-day and convert to days *)
  try
    Scanf.sscanf s "%d-%d-%dT" (fun y m d ->
      Float.of_int (y * 365 + m * 30 + d))
  with _ -> 0.0

let extract_history json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "history" fields with
     | Some (`List items) ->
       List.filter_map (fun item ->
         match item with
         | `Assoc fs ->
           let time = match List.assoc_opt "time" fs with
             | Some (`String s) -> parse_time s
             | _ -> 0.0
           in
           let price = match List.assoc_opt "price" fs with
             | Some v -> float_of_json v
             | None -> 0.0
           in
           if time > 0.0 && price > 0.0 then Some (time, price) else None
         | _ -> None
       ) items
     | _ -> [])
  | _ -> []

(** Simple linear regression on log-transformed prices.
    ln(price) = ln(P0) - lambda * t
    This gives us the exponential decay parameters. *)
let fit_exponential data =
  let n = Float.of_int (List.length data) in
  if n < 2.0 then None
  else
    (* Normalize time to years from first observation *)
    let t0 = List.fold_left (fun acc (t, _) -> Float.min acc t) Float.infinity data in
    let data = List.map (fun (t, p) -> ((t -. t0) /. 365.0, p)) data in
    (* Log-transform prices *)
    let log_data = List.map (fun (t, p) -> (t, Float.log p)) data in
    (* Linear regression: y = a + b*x where y=ln(price), x=time *)
    let sum_x = List.fold_left (fun acc (x, _) -> acc +. x) 0.0 log_data in
    let sum_y = List.fold_left (fun acc (_, y) -> acc +. y) 0.0 log_data in
    let sum_xy = List.fold_left (fun acc (x, y) -> acc +. x *. y) 0.0 log_data in
    let sum_xx = List.fold_left (fun acc (x, _) -> acc +. x *. x) 0.0 log_data in
    let denom = n *. sum_xx -. sum_x *. sum_x in
    if Float.abs denom < 1e-10 then None
    else
      let b = (n *. sum_xy -. sum_x *. sum_y) /. denom in
      let a = (sum_y -. b *. sum_x) /. n in
      let p0 = Float.exp a in
      let lambda = -. b in (* positive lambda = depreciation *)
      Some (p0, lambda)

let analyze json =
  let history = extract_history json in
  match history with
  | [] | [_] ->
    `Assoc [("error", `String "Need at least 2 data points")]
  | data ->
    match fit_exponential data with
    | None ->
      `Assoc [("error", `String "Could not fit depreciation curve")]
    | Some (p0, lambda) ->
      let annual_depreciation_pct = (1.0 -. Float.exp (-. lambda)) *. 100.0 in
      (* Predict future values *)
      let predictions = List.map (fun years ->
        let predicted = p0 *. Float.exp (-. lambda *. Float.of_int years) in
        `Assoc [
          ("years_from_now", `Int years);
          ("predicted_price", `Float (Float.round predicted));
        ]
      ) [1; 2; 3; 5] in
      `Assoc [
        ("initial_price", `Float (Float.round p0));
        ("decay_rate", `Float lambda);
        ("annual_depreciation_pct", `Float (Float.round (annual_depreciation_pct *. 10.0) /. 10.0));
        ("predictions", `List predictions);
        ("data_points", `Int (List.length data));
      ]
