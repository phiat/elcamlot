(** Data quality score — assess price dataset reliability *)

let float_of_json = function
  | `Int n -> Float.of_int n
  | `Float f -> f
  | _ -> 0.0

let extract_prices json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "prices" fields with
     | Some (`List prices) -> List.map float_of_json prices
     | _ -> [])
  | _ -> []

let mean prices =
  let sum = List.fold_left ( +. ) 0.0 prices in
  sum /. Float.of_int (List.length prices)

let std_dev prices =
  let m = mean prices in
  let n = Float.of_int (List.length prices) in
  let variance =
    List.fold_left (fun acc p -> acc +. (p -. m) ** 2.0) 0.0 prices /. n
  in
  Float.sqrt variance

(** Coefficient of variation: std_dev / mean *)
let cv prices =
  let m = mean prices in
  if Float.abs m < 0.001 then 0.0
  else std_dev prices /. Float.abs m

(** Skewness: measures asymmetry of distribution *)
let skewness prices =
  let n = Float.of_int (List.length prices) in
  let m = mean prices in
  let sd = std_dev prices in
  if sd < 0.001 then 0.0
  else
    let sum_cubed =
      List.fold_left (fun acc p -> acc +. ((p -. m) /. sd) ** 3.0) 0.0 prices
    in
    sum_cubed /. n

(** Kurtosis: measures tail heaviness (excess, normal = 0) *)
let kurtosis prices =
  let n = Float.of_int (List.length prices) in
  let m = mean prices in
  let sd = std_dev prices in
  if sd < 0.001 then 0.0
  else
    let sum_fourth =
      List.fold_left (fun acc p -> acc +. ((p -. m) /. sd) ** 4.0) 0.0 prices
    in
    (sum_fourth /. n) -. 3.0

(** Count suspicious round numbers (divisible by 500 in cents = $5 increments) *)
let round_number_ratio prices =
  let round_count = List.length (List.filter (fun p ->
    let dollars = p /. 100.0 in
    let remainder = Float.rem (Float.abs dollars) 500.0 in
    remainder < 1.0 || remainder > 499.0
  ) prices) in
  Float.of_int round_count /. Float.of_int (List.length prices)

(** Grade each dimension 0-100, then composite *)
let analyze json =
  let prices = extract_prices json in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | prices ->
    let n = List.length prices in

    (* Sample size score: 0 at 1, ramps to 100 at 30+ *)
    let size_score =
      Float.min 100.0 (Float.of_int (n - 1) *. 100.0 /. 29.0)
    in

    (* Spread score: CV between 0.05-0.5 is healthy *)
    let coefficient = cv prices in
    let spread_score =
      if coefficient < 0.01 then 20.0  (* suspiciously uniform *)
      else if coefficient < 0.05 then 60.0
      else if coefficient <= 0.5 then 100.0
      else if coefficient <= 1.0 then 60.0
      else 30.0  (* too much spread *)
    in

    (* Normality score: low skewness and kurtosis = normal-ish *)
    let skew = skewness prices in
    let kurt = kurtosis prices in
    let normality_score =
      let skew_penalty = Float.min 50.0 (Float.abs skew *. 20.0) in
      let kurt_penalty = Float.min 50.0 (Float.abs kurt *. 10.0) in
      Float.max 0.0 (100.0 -. skew_penalty -. kurt_penalty)
    in

    (* Round number penalty *)
    let round_ratio = round_number_ratio prices in
    let round_score =
      if round_ratio > 0.8 then 30.0  (* mostly round numbers = likely estimated *)
      else if round_ratio > 0.5 then 60.0
      else 100.0
    in

    (* Composite: weighted average *)
    let composite =
      size_score *. 0.30
      +. spread_score *. 0.25
      +. normality_score *. 0.25
      +. round_score *. 0.20
    in

    let grade =
      if composite >= 90.0 then "A"
      else if composite >= 80.0 then "B"
      else if composite >= 70.0 then "C"
      else if composite >= 60.0 then "D"
      else "F"
    in

    let round2 f = Float.round (f *. 100.0) /. 100.0 in

    `Assoc [
      ("grade", `String grade);
      ("composite_score", `Float (round2 composite));
      ("sample_size", `Int n);
      ("dimensions", `Assoc [
        ("sample_size_score", `Float (round2 size_score));
        ("spread_score", `Float (round2 spread_score));
        ("normality_score", `Float (round2 normality_score));
        ("round_number_score", `Float (round2 round_score));
      ]);
      ("details", `Assoc [
        ("cv", `Float (round2 coefficient));
        ("skewness", `Float (round2 skew));
        ("kurtosis", `Float (round2 kurt));
        ("round_number_ratio", `Float (round2 round_ratio));
      ]);
    ]
