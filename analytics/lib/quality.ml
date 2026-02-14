(** Data quality score — assess price dataset reliability *)

(** Coefficient of variation: std_dev / mean *)
let cv prices =
  let m = Common.mean prices in
  if Float.abs m < 0.001 then 0.0
  else Common.std_dev prices /. Float.abs m

(** Skewness: measures asymmetry of distribution *)
let skewness prices =
  let n = Float.of_int (List.length prices) in
  let m = Common.mean prices in
  let sd = Common.std_dev prices in
  if sd < 0.001 then 0.0
  else
    let sum_cubed =
      List.fold_left (fun acc p -> acc +. ((p -. m) /. sd) ** 3.0) 0.0 prices
    in
    sum_cubed /. n

(** Kurtosis: measures tail heaviness (excess, normal = 0) *)
let kurtosis prices =
  let n = Float.of_int (List.length prices) in
  let m = Common.mean prices in
  let sd = Common.std_dev prices in
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
  let prices = Common.extract_prices json in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | prices ->
    let n = List.length prices in

    let size_score =
      Float.min 100.0 (Float.of_int (n - 1) *. 100.0 /. 29.0)
    in

    let coefficient = cv prices in
    let spread_score =
      if coefficient < 0.01 then 20.0
      else if coefficient < 0.05 then 60.0
      else if coefficient <= 0.5 then 100.0
      else if coefficient <= 1.0 then 60.0
      else 30.0
    in

    let skew = skewness prices in
    let kurt = kurtosis prices in
    let normality_score =
      let skew_penalty = Float.min 50.0 (Float.abs skew *. 20.0) in
      let kurt_penalty = Float.min 50.0 (Float.abs kurt *. 10.0) in
      Float.max 0.0 (100.0 -. skew_penalty -. kurt_penalty)
    in

    let round_ratio = round_number_ratio prices in
    let round_score =
      if round_ratio > 0.8 then 30.0
      else if round_ratio > 0.5 then 60.0
      else 100.0
    in

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

    `Assoc [
      ("grade", `String grade);
      ("composite_score", `Float (Common.round2 composite));
      ("sample_size", `Int n);
      ("dimensions", `Assoc [
        ("sample_size_score", `Float (Common.round2 size_score));
        ("spread_score", `Float (Common.round2 spread_score));
        ("normality_score", `Float (Common.round2 normality_score));
        ("round_number_score", `Float (Common.round2 round_score));
      ]);
      ("details", `Assoc [
        ("cv", `Float (Common.round2 coefficient));
        ("skewness", `Float (Common.round2 skew));
        ("kurtosis", `Float (Common.round2 kurt));
        ("round_number_ratio", `Float (Common.round2 round_ratio));
      ]);
    ]
