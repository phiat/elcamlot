(** Cross-dataset Pearson correlation *)

let pearson xs ys =
  let n = Float.of_int (List.length xs) in
  if n < 2.0 then None
  else
    let mx = Common.mean xs in
    let my = Common.mean ys in
    let pairs = List.combine xs ys in
    let sum_xy = List.fold_left (fun acc (x, y) ->
      acc +. (x -. mx) *. (y -. my)
    ) 0.0 pairs in
    let sum_xx = List.fold_left (fun acc x ->
      acc +. (x -. mx) ** 2.0
    ) 0.0 xs in
    let sum_yy = List.fold_left (fun acc y ->
      acc +. (y -. my) ** 2.0
    ) 0.0 ys in
    let denom = Float.sqrt (sum_xx *. sum_yy) in
    if denom < 1e-10 then None
    else Some (sum_xy /. denom)

let analyze json =
  let series_a = Common.extract_series json "series_a" in
  let series_b = Common.extract_series json "series_b" in
  let na = List.length series_a in
  let nb = List.length series_b in
  if na < 2 || nb < 2 then
    `Assoc [("error", `String "Need at least 2 values in each series")]
  else
    (* Truncate to the shorter series *)
    let n = min na nb in
    let a = List.filteri (fun i _ -> i < n) series_a in
    let b = List.filteri (fun i _ -> i < n) series_b in
    match pearson a b with
    | None ->
      `Assoc [("error", `String "Cannot compute correlation (zero variance)")]
    | Some r ->
      let strength =
        let ar = Float.abs r in
        if ar >= 0.8 then "strong"
        else if ar >= 0.5 then "moderate"
        else if ar >= 0.3 then "weak"
        else "negligible"
      in
      let direction = if r > 0.0 then "positive" else "negative" in
      `Assoc [
        ("pearson_r", `Float (Common.round3 r));
        ("r_squared", `Float (Common.round3 (r *. r)));
        ("sample_size", `Int n);
        ("strength", `String strength);
        ("direction", `String direction);
      ]
