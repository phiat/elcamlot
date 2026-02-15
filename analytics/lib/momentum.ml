(** Momentum indicators — ROC, momentum values, RSI, trend signal *)

(** Rate of Change: (price - price_n_ago) / price_n_ago * 100 *)
let roc prices period =
  let arr = Array.of_list prices in
  let n = Array.length arr in
  if n <= period then []
  else
    List.init (n - period) (fun i ->
      let prev = arr.(i) in
      let curr = arr.(i + period) in
      if prev <> 0.0 then (curr -. prev) /. prev *. 100.0
      else 0.0
    )

(** Momentum values: price - price_n_periods_ago *)
let momentum_values prices period =
  let arr = Array.of_list prices in
  let n = Array.length arr in
  if n <= period then []
  else
    List.init (n - period) (fun i ->
      arr.(i + period) -. arr.(i)
    )

(** RSI — classic Wilder's smoothed RSI *)
let rsi prices period =
  let arr = Array.of_list prices in
  let n = Array.length arr in
  if n < period + 1 then None
  else begin
    (* Calculate initial average gain and loss over first period *)
    let init_gain = ref 0.0 in
    let init_loss = ref 0.0 in
    for i = 1 to period do
      let change = arr.(i) -. arr.(i - 1) in
      if change > 0.0 then init_gain := !init_gain +. change
      else init_loss := !init_loss +. Float.abs change
    done;
    let avg_gain = ref (!init_gain /. Float.of_int period) in
    let avg_loss = ref (!init_loss /. Float.of_int period) in
    (* Smooth using Wilder's method for remaining data *)
    let fp = Float.of_int period in
    for i = period + 1 to n - 1 do
      let change = arr.(i) -. arr.(i - 1) in
      let gain = if change > 0.0 then change else 0.0 in
      let loss = if change < 0.0 then Float.abs change else 0.0 in
      avg_gain := (!avg_gain *. (fp -. 1.0) +. gain) /. fp;
      avg_loss := (!avg_loss *. (fp -. 1.0) +. loss) /. fp;
    done;
    if !avg_loss = 0.0 then Some 100.0
    else
      let rs = !avg_gain /. !avg_loss in
      Some (100.0 -. 100.0 /. (1.0 +. rs))
  end

(** Determine trend signal based on recent ROC values and volatility *)
let trend_signal roc_values =
  match roc_values with
  | [] -> "insufficient_data"
  | _ ->
    let recent = if List.length roc_values > 5 then
      let arr = Array.of_list roc_values in
      let n = Array.length arr in
      Array.to_list (Array.sub arr (n - 5) 5)
    else roc_values
    in
    let avg = Common.mean recent in
    let vol = Common.std_dev recent in
    if vol > Float.abs avg *. 2.0 && vol > 1.0 then "volatile"
    else if avg > 1.0 then "rising"
    else if avg < -1.0 then "falling"
    else "stable"

let analyze json =
  let prices = Common.extract_prices json in
  let period = match json with
    | `Assoc fields ->
      (match List.assoc_opt "period" fields with
       | Some v -> (match Common.int_of_json_opt v with Some p -> p | None -> 14)
       | None -> 14)
    | _ -> 14
  in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | _ when List.length prices <= period ->
    `Assoc [("error", `String (Printf.sprintf "Need more than %d prices for period %d" period period))]
  | _ ->
    let mom_vals = momentum_values prices period in
    let roc_vals = roc prices period in
    let rsi_val = rsi prices period in
    let signal = trend_signal roc_vals in
    let avg_roc = Common.mean roc_vals in
    let vol_index = Common.std_dev roc_vals in
    `Assoc [
      ("momentum_values", `List (List.map (fun v -> `Float (Common.round2 v)) mom_vals));
      ("roc_values", `List (List.map (fun v -> `Float (Common.round2 v)) roc_vals));
      ("rsi", (match rsi_val with
        | Some v -> `Float (Common.round2 v)
        | None -> `Null));
      ("trend_signal", `String signal);
      ("avg_roc", `Float (Common.round2 avg_roc));
      ("volatility_index", `Float (Common.round2 vol_index));
      ("period", `Int period);
      ("data_points", `Int (List.length prices));
    ]
