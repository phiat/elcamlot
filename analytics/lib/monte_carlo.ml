(** Monte Carlo price simulation via geometric Brownian motion.

    Fits drift from price history (linear depreciation rate),
    calibrates volatility from log-return residuals, then runs
    N simulations of GBM to produce percentile bands at each horizon. *)

(** Box-Muller transform: generate a standard normal variate from two U(0,1) *)
let box_muller () =
  let u1 = Random.float 1.0 in
  let u2 = Random.float 1.0 in
  Float.sqrt (-2.0 *. Float.log u1) *. Float.cos (2.0 *. Float.pi *. u2)

(** Compute log-returns from a price series *)
let log_returns prices =
  let rec aux acc = function
    | [] | [_] -> List.rev acc
    | p1 :: (p2 :: _ as rest) ->
      if p1 > 0.0 && p2 > 0.0 then
        aux (Float.log (p2 /. p1) :: acc) rest
      else
        aux acc rest
  in
  aux [] prices

(** Estimate annualized drift from a linear fit on prices.
    Treats each price as one "period" apart, fits slope,
    then converts to an annual rate assuming ~252 trading days. *)
let estimate_drift prices =
  let n = List.length prices in
  let nf = Float.of_int n in
  (* Simple linear regression: price = a + b * t *)
  let sum_x = ref 0.0 in
  let sum_y = ref 0.0 in
  let sum_xy = ref 0.0 in
  let sum_xx = ref 0.0 in
  List.iteri (fun i p ->
    let x = Float.of_int i in
    sum_x := !sum_x +. x;
    sum_y := !sum_y +. p;
    sum_xy := !sum_xy +. x *. p;
    sum_xx := !sum_xx +. x *. x;
  ) prices;
  let denom = nf *. !sum_xx -. !sum_x *. !sum_x in
  if Float.abs denom < 1e-10 then 0.0
  else
    let b = (nf *. !sum_xy -. !sum_x *. !sum_y) /. denom in
    let p0 = Common.mean prices in
    if Float.abs p0 < 1e-10 then 0.0
    else
      (* daily fractional change, annualized *)
      let daily_rate = b /. p0 in
      daily_rate *. 365.0

(** Estimate annualized volatility from log-returns *)
let estimate_volatility prices =
  let returns = log_returns prices in
  match returns with
  | [] | [_] -> 0.0
  | _ ->
    let daily_vol = Common.std_dev returns in
    daily_vol *. Float.sqrt 365.0

(** Run a single GBM path and collect the price at each horizon day.
    dt = 1/365 (one day step in years). *)
let simulate_path ~current_price ~drift ~vol ~horizons =
  let dt = 1.0 /. 365.0 in
  let max_horizon = List.fold_left max 0 horizons in
  let horizon_set = Array.make (max_horizon + 1) false in
  List.iter (fun h -> if h >= 0 && h <= max_horizon then horizon_set.(h) <- true) horizons;
  let results = Array.make (max_horizon + 1) 0.0 in
  let price = ref current_price in
  for day = 1 to max_horizon do
    let z = box_muller () in
    price := !price *. Float.exp ((drift -. 0.5 *. vol *. vol) *. dt +. vol *. Float.sqrt dt *. z);
    if horizon_set.(day) then
      results.(day) <- !price
  done;
  List.map (fun h -> (h, results.(h))) horizons

(** Extract optional int list for horizons *)
let extract_horizons json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "horizons" fields with
     | Some (`List items) ->
       let hs = List.filter_map (fun v ->
         match Common.int_of_json_opt v with
         | Some h when h > 0 -> Some h
         | _ -> None
       ) items in
       if hs = [] then None else Some hs
     | _ -> None)
  | _ -> None

(** Extract optional simulation count *)
let extract_simulations json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "simulations" fields with
     | Some v -> Common.int_of_json_opt v
     | None -> None)
  | _ -> None

(** Collect simulated prices at each horizon, compute percentile bands *)
let compute_bands ~all_results ~horizons =
  List.map (fun h ->
    let prices_at_h = List.filter_map (fun sim_result ->
      match List.assoc_opt h sim_result with
      | Some p -> Some p
      | None -> None
    ) all_results in
    let p10 = Common.percentile prices_at_h 10.0 in
    let p25 = Common.percentile prices_at_h 25.0 in
    let p50 = Common.percentile prices_at_h 50.0 in
    let p75 = Common.percentile prices_at_h 75.0 in
    let p90 = Common.percentile prices_at_h 90.0 in
    `Assoc [
      ("days", `Int h);
      ("p10", `Float (Common.round2 p10));
      ("p25", `Float (Common.round2 p25));
      ("p50", `Float (Common.round2 p50));
      ("p75", `Float (Common.round2 p75));
      ("p90", `Float (Common.round2 p90));
    ]
  ) horizons

let analyze json =
  let prices = Common.extract_prices json in
  let n = List.length prices in
  if n < 5 then
    `Assoc [("error", `String "Need at least 5 prices for simulation")]
  else
    let horizons = match extract_horizons json with
      | Some hs -> hs
      | None -> [30; 90; 180; 365]
    in
    let num_sims = match extract_simulations json with
      | Some s -> min s 50000
      | None -> 10000
    in
    let num_sims = max 1 num_sims in
    let current_price = List.nth prices (n - 1) in
    if current_price <= 0.0 then
      `Assoc [("error", `String "Current price must be positive")]
    else
      let drift = estimate_drift prices in
      let vol = estimate_volatility prices in
      (* Seed RNG for reproducibility within a request *)
      Random.self_init ();
      (* Run all simulations *)
      let all_results = List.init num_sims (fun _ ->
        simulate_path ~current_price ~drift ~vol ~horizons
      ) in
      let horizon_bands = compute_bands ~all_results ~horizons in
      `Assoc [
        ("current_price", `Float (Common.round2 current_price));
        ("horizons", `List horizon_bands);
        ("drift_annual", `Float (Common.round3 drift));
        ("volatility_annual", `Float (Common.round3 vol));
        ("simulations", `Int num_sims);
        ("data_points", `Int n);
      ]
