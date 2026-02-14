(** Outlier detection — IQR fencing and modified Z-score (MAD) *)

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

let median_of sorted =
  let n = List.length sorted in
  if n = 0 then 0.0
  else if n mod 2 = 1 then List.nth sorted (n / 2)
  else
    let a = List.nth sorted (n / 2 - 1) in
    let b = List.nth sorted (n / 2) in
    (a +. b) /. 2.0

(** Median Absolute Deviation *)
let mad prices =
  let sorted = List.sort Float.compare prices in
  let med = median_of sorted in
  let deviations = List.map (fun p -> Float.abs (p -. med)) prices in
  let sorted_devs = List.sort Float.compare deviations in
  median_of sorted_devs

(** Modified Z-score using MAD (more robust than mean-based Z-score) *)
let modified_z_scores prices =
  let sorted = List.sort Float.compare prices in
  let med = median_of sorted in
  let m = mad prices in
  if m < 0.001 then
    (* All values nearly identical, no outliers *)
    List.map (fun _ -> 0.0) prices
  else
    List.map (fun p -> 0.6745 *. (p -. med) /. m) prices

(** IQR fencing: values outside [Q1 - k*IQR, Q3 + k*IQR] are outliers *)
let iqr_fence prices ?(k=1.5) () =
  let sorted = List.sort Float.compare prices in
  let n = List.length sorted in
  let q1_idx = Float.to_int (Float.of_int (n - 1) *. 0.25) in
  let q3_idx = Float.to_int (Float.of_int (n - 1) *. 0.75) in
  let q1 = List.nth sorted (min q1_idx (n - 1)) in
  let q3 = List.nth sorted (min q3_idx (n - 1)) in
  let iqr = q3 -. q1 in
  let lower = q1 -. k *. iqr in
  let upper = q3 +. k *. iqr in
  (lower, upper)

let severity_label z =
  let az = Float.abs z in
  if az > 5.0 then "extreme"
  else if az > 3.5 then "high"
  else if az > 2.5 then "moderate"
  else "mild"

let analyze json =
  let prices = extract_prices json in
  match prices with
  | [] | [_] | [_; _] ->
    `Assoc [("error", `String "Need at least 3 prices for outlier detection")]
  | prices ->
    let z_scores = modified_z_scores prices in
    let (lower, upper) = iqr_fence prices () in
    let threshold = 3.5 in
    let flagged =
      List.mapi (fun idx (price, z) ->
        let iqr_outlier = price < lower || price > upper in
        let z_outlier = Float.abs z > threshold in
        if iqr_outlier || z_outlier then
          Some (`Assoc [
            ("index", `Int idx);
            ("price", `Float price);
            ("z_score", `Float (Float.round (z *. 100.0) /. 100.0));
            ("severity", `String (severity_label z));
            ("method", `String (
              if iqr_outlier && z_outlier then "both"
              else if iqr_outlier then "iqr"
              else "z_score"));
          ])
        else None
      ) (List.combine prices z_scores)
    in
    let flagged = List.filter_map Fun.id flagged in
    let clean_prices =
      List.filter_map (fun (price, z) ->
        let iqr_ok = price >= lower && price <= upper in
        let z_ok = Float.abs z <= threshold in
        if iqr_ok && z_ok then Some price else None
      ) (List.combine prices z_scores)
    in
    `Assoc [
      ("outlier_count", `Int (List.length flagged));
      ("total_count", `Int (List.length prices));
      ("clean_count", `Int (List.length clean_prices));
      ("flagged", `List flagged);
      ("clean_prices", `List (List.map (fun p -> `Float p) clean_prices));
      ("thresholds", `Assoc [
        ("iqr_lower", `Float (Float.round (lower *. 100.0) /. 100.0));
        ("iqr_upper", `Float (Float.round (upper *. 100.0) /. 100.0));
        ("z_score_threshold", `Float threshold);
      ]);
      ("mad", `Float (Float.round (mad prices *. 100.0) /. 100.0));
    ]
