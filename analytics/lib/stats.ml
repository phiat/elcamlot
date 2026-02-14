(** Price statistics — mean, median, std dev, percentiles, IQR *)

let analyze json =
  let prices = Common.extract_prices json in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | prices ->
    let n = List.length prices in
    `Assoc [
      ("count", `Int n);
      ("mean", `Float (Common.mean prices));
      ("median", `Float (Common.median prices));
      ("std_dev", `Float (Common.std_dev prices));
      ("min", `Float (Common.percentile prices 0.0));
      ("max", `Float (Common.percentile prices 100.0));
      ("p10", `Float (Common.percentile prices 10.0));
      ("p25", `Float (Common.percentile prices 25.0));
      ("p75", `Float (Common.percentile prices 75.0));
      ("p90", `Float (Common.percentile prices 90.0));
      ("iqr", `Float (Common.iqr prices));
    ]
