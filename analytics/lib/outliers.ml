(** Outlier detection — IQR fencing and modified Z-score (MAD) *)

(** Median Absolute Deviation *)
let mad prices =
  let sorted = List.sort Float.compare prices in
  let med = Common.median sorted in
  let deviations = List.map (fun p -> Float.abs (p -. med)) prices in
  let sorted_devs = List.sort Float.compare deviations in
  Common.median sorted_devs

(** Modified Z-score using MAD (more robust than mean-based Z-score) *)
let modified_z_scores prices =
  let sorted = List.sort Float.compare prices in
  let med = Common.median sorted in
  let m = mad prices in
  if m < 0.001 then
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
  let prices = Common.extract_prices json in
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
            ("z_score", `Float (Common.round2 z));
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
        ("iqr_lower", `Float (Common.round2 lower));
        ("iqr_upper", `Float (Common.round2 upper));
        ("z_score_threshold", `Float threshold);
      ]);
      ("mad", `Float (Common.round2 (mad prices)));
    ]
