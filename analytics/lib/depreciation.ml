(** Depreciation curve fitting.

    Given price history (time, price) pairs, fits exponential and linear
    models, selects the best fit via R², and predicts future prices.

    Exponential: price(t) = P0 * e^(-lambda * t)
    Linear:      price(t) = a + b * t
*)

let float_of_json = function
  | `Int n -> Float.of_int n
  | `Float f -> f
  | _ -> 0.0

(** Parse ISO 8601 timestamp to approximate day number (simplified) *)
let parse_time s =
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

let sort_history data =
  List.sort (fun (t1, _) (t2, _) -> Float.compare t1 t2) data

(** Normalize time to years from first observation *)
let normalize_time data =
  let t0 = List.fold_left (fun acc (t, _) -> Float.min acc t) Float.infinity data in
  List.map (fun (t, p) -> ((t -. t0) /. 365.0, p)) data

(** R² coefficient of determination *)
let r_squared data predict_fn =
  let y_values = List.map snd data in
  let n = Float.of_int (List.length y_values) in
  let mean_y = List.fold_left ( +. ) 0.0 y_values /. n in
  let ss_tot = List.fold_left (fun acc y -> acc +. (y -. mean_y) ** 2.0) 0.0 y_values in
  if Float.abs ss_tot < 1e-10 then 0.0
  else
    let ss_res = List.fold_left (fun acc (x, y) ->
      let pred = predict_fn x in
      acc +. (y -. pred) ** 2.0
    ) 0.0 data in
    Float.max 0.0 (1.0 -. ss_res /. ss_tot)

(** Exponential fit via log-linear regression:
    ln(price) = ln(P0) - lambda * t *)
let fit_exponential data =
  let n = Float.of_int (List.length data) in
  if n < 2.0 then None
  else
    let norm = normalize_time data in
    let log_data = List.filter_map (fun (t, p) ->
      if p > 0.0 then Some (t, Float.log p) else None
    ) norm in
    if List.length log_data < 2 then None
    else
      let ln = Float.of_int (List.length log_data) in
      let sum_x = List.fold_left (fun acc (x, _) -> acc +. x) 0.0 log_data in
      let sum_y = List.fold_left (fun acc (_, y) -> acc +. y) 0.0 log_data in
      let sum_xy = List.fold_left (fun acc (x, y) -> acc +. x *. y) 0.0 log_data in
      let sum_xx = List.fold_left (fun acc (x, _) -> acc +. x *. x) 0.0 log_data in
      let denom = ln *. sum_xx -. sum_x *. sum_x in
      if Float.abs denom < 1e-10 then None
      else
        let b = (ln *. sum_xy -. sum_x *. sum_y) /. denom in
        let a = (sum_y -. b *. sum_x) /. ln in
        let p0 = Float.exp a in
        let lambda = -. b in
        let predict t = p0 *. Float.exp (-. lambda *. t) in
        let r2 = r_squared norm predict in
        Some (p0, lambda, r2)

(** Linear regression: price = a + b * t *)
let fit_linear data =
  let n = Float.of_int (List.length data) in
  if n < 2.0 then None
  else
    let norm = normalize_time data in
    let sum_x = List.fold_left (fun acc (x, _) -> acc +. x) 0.0 norm in
    let sum_y = List.fold_left (fun acc (_, y) -> acc +. y) 0.0 norm in
    let sum_xy = List.fold_left (fun acc (x, y) -> acc +. x *. y) 0.0 norm in
    let sum_xx = List.fold_left (fun acc (x, _) -> acc +. x *. x) 0.0 norm in
    let denom = n *. sum_xx -. sum_x *. sum_x in
    if Float.abs denom < 1e-10 then None
    else
      let b = (n *. sum_xy -. sum_x *. sum_y) /. denom in
      let a = (sum_y -. b *. sum_x) /. n in
      let predict t = a +. b *. t in
      let r2 = r_squared norm predict in
      Some (a, b, r2)

let make_predictions predict_fn =
  List.map (fun years ->
    let predicted = Float.max 0.0 (predict_fn (Float.of_int years)) in
    `Assoc [
      ("years_from_now", `Int years);
      ("predicted_price", `Float (Float.round predicted));
    ]
  ) [1; 2; 3; 5]

let analyze json =
  let history = extract_history json in
  match history with
  | [] | [_] ->
    `Assoc [("error", `String "Need at least 2 data points")]
  | data ->
    let sorted_data = sort_history data in
    let n_pts = List.length sorted_data in
    match fit_exponential sorted_data, fit_linear sorted_data with
    | None, None ->
      `Assoc [("error", `String "Could not fit depreciation curve")]
    | Some (p0, lambda, exp_r2), None ->
      let predict t = p0 *. Float.exp (-. lambda *. t) in
      let annual_pct = (1.0 -. Float.exp (-. lambda)) *. 100.0 in
      `Assoc [
        ("model", `String "exponential");
        ("initial_price", `Float (Float.round p0));
        ("decay_rate", `Float lambda);
        ("annual_depreciation_pct", `Float (Float.round (annual_pct *. 10.0) /. 10.0));
        ("r_squared", `Float (Float.round (exp_r2 *. 1000.0) /. 1000.0));
        ("predictions", `List (make_predictions predict));
        ("data_points", `Int n_pts);
      ]
    | None, Some (a, b, lin_r2) ->
      let predict t = a +. b *. t in
      `Assoc [
        ("model", `String "linear");
        ("initial_price", `Float (Float.round a));
        ("annual_change", `Float (Float.round b));
        ("r_squared", `Float (Float.round (lin_r2 *. 1000.0) /. 1000.0));
        ("predictions", `List (make_predictions predict));
        ("data_points", `Int n_pts);
      ]
    | Some (p0, lambda, exp_r2), Some (a, b, lin_r2) ->
      if exp_r2 >= lin_r2 then
        let predict t = p0 *. Float.exp (-. lambda *. t) in
        let annual_pct = (1.0 -. Float.exp (-. lambda)) *. 100.0 in
        `Assoc [
          ("model", `String "exponential");
          ("initial_price", `Float (Float.round p0));
          ("decay_rate", `Float lambda);
          ("annual_depreciation_pct", `Float (Float.round (annual_pct *. 10.0) /. 10.0));
          ("r_squared", `Float (Float.round (exp_r2 *. 1000.0) /. 1000.0));
          ("predictions", `List (make_predictions predict));
          ("data_points", `Int n_pts);
          ("alt_r_squared", `Float (Float.round (lin_r2 *. 1000.0) /. 1000.0));
        ]
      else
        let predict t = a +. b *. t in
        `Assoc [
          ("model", `String "linear");
          ("initial_price", `Float (Float.round a));
          ("annual_change", `Float (Float.round b));
          ("r_squared", `Float (Float.round (lin_r2 *. 1000.0) /. 1000.0));
          ("predictions", `List (make_predictions predict));
          ("data_points", `Int n_pts);
          ("alt_r_squared", `Float (Float.round (exp_r2 *. 1000.0) /. 1000.0));
        ]
