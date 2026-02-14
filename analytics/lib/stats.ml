(** Price statistics — mean, median, std dev, percentiles *)

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
  match prices with
  | [] -> 0.0
  | _ ->
    let sum = List.fold_left ( +. ) 0.0 prices in
    sum /. Float.of_int (List.length prices)

let median prices =
  let sorted = List.sort Float.compare prices in
  let n = List.length sorted in
  if n = 0 then 0.0
  else if n mod 2 = 1 then
    List.nth sorted (n / 2)
  else
    let a = List.nth sorted (n / 2 - 1) in
    let b = List.nth sorted (n / 2) in
    (a +. b) /. 2.0

let std_dev prices =
  match prices with
  | [] | [_] -> 0.0
  | _ ->
    let m = mean prices in
    let n = Float.of_int (List.length prices) in
    let variance =
      List.fold_left (fun acc p -> acc +. (p -. m) ** 2.0) 0.0 prices /. n
    in
    Float.sqrt variance

let percentile prices pct =
  let sorted = List.sort Float.compare prices in
  let n = List.length sorted in
  if n = 0 then 0.0
  else
    let idx = Float.to_int (Float.of_int (n - 1) *. pct /. 100.0) in
    List.nth sorted (min idx (n - 1))

let analyze json =
  let prices = extract_prices json in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | prices ->
    let n = List.length prices in
    `Assoc [
      ("count", `Int n);
      ("mean", `Float (mean prices));
      ("median", `Float (median prices));
      ("std_dev", `Float (std_dev prices));
      ("min", `Float (percentile prices 0.0));
      ("max", `Float (percentile prices 100.0));
      ("p10", `Float (percentile prices 10.0));
      ("p25", `Float (percentile prices 25.0));
      ("p75", `Float (percentile prices 75.0));
      ("p90", `Float (percentile prices 90.0));
    ]
