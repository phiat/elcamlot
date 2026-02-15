(** Seasonal decomposition for optimal vehicle purchase timing.
    Uses ratio-to-moving-average method to identify cheapest months. *)

let month_names = [|
  "January"; "February"; "March"; "April"; "May"; "June";
  "July"; "August"; "September"; "October"; "November"; "December"
|]

(** Extract month (1-12) from an ISO 8601 timestamp string.
    Handles "YYYY-MM-DD...", "YYYY-MM-DDTHH:MM:SS...", etc. *)
let month_of_iso8601 s =
  try
    Scanf.sscanf s "%d-%d" (fun _year month ->
      if month >= 1 && month <= 12 then Some month else None)
  with _ -> None

(** Parse the history array: [{"time": "...", "price": float}, ...] *)
let parse_history json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "history" fields with
     | Some (`List items) ->
       List.filter_map (fun item ->
         match item with
         | `Assoc entry ->
           let time = match List.assoc_opt "time" entry with
             | Some (`String s) -> Some s
             | _ -> None
           in
           let price = match List.assoc_opt "price" entry with
             | Some v -> Some (Common.float_of_json v)
             | None -> None
           in
           (match time, price with
            | Some t, Some p ->
              (match month_of_iso8601 t with
               | Some m -> Some (m, p)
               | None -> None)
            | _ -> None)
         | _ -> None
       ) items
     | _ -> [])
  | _ -> []

(** Centered 12-period moving average using the existing SMA function.
    A centered MA for an even window (12) is computed as the average of
    two consecutive SMA-12 values, which shifts the result to align with
    the midpoint between them. *)
let centered_ma_12 prices =
  let sma12 = Moving_averages.sma prices 12 in
  match sma12 with
  | [] | [_] -> []
  | _ ->
    let arr = Array.of_list sma12 in
    let n = Array.length arr in
    List.init (n - 1) (fun i -> (arr.(i) +. arr.(i + 1)) /. 2.0)

(** Label a seasonal index value *)
let label_of_index idx =
  if idx < 0.95 then "well_below"
  else if idx < 0.98 then "below_average"
  else if idx <= 1.02 then "average"
  else if idx <= 1.05 then "above_average"
  else "well_above"

(** Count distinct months present in the data *)
let count_distinct_months data =
  let seen = Array.make 12 false in
  List.iter (fun (m, _) -> seen.(m - 1) <- true) data;
  Array.fold_left (fun acc b -> if b then acc + 1 else acc) 0 seen

let analyze json =
  let data = parse_history json in
  let n = List.length data in
  if n < 12 then
    `Assoc [("error", `String (Printf.sprintf
      "Need at least 12 data points with valid timestamps, got %d" n))]
  else
    (* Extract just the prices in order *)
    let prices = List.map snd data in
    let months = List.map fst data in

    (* Centered 12-period moving average *)
    let cma = centered_ma_12 prices in
    let cma_len = List.length cma in

    (* The centered MA of window 12 drops 6 from the front and 6 from the back.
       SMA-12 drops 11, then centering drops 1 more = 12 total dropped.
       Offset: first CMA value aligns with index 6 of the original data. *)
    let offset = 6 in

    (* Compute ratio = price / CMA for each aligned point *)
    let cma_arr = Array.of_list cma in
    let prices_arr = Array.of_list prices in
    let months_arr = Array.of_list months in

    (* Collect ratios by month (month 1-12 -> list of ratios) *)
    let month_ratios = Array.make 12 [] in
    for i = 0 to cma_len - 1 do
      let orig_i = i + offset in
      if orig_i < n && cma_arr.(i) > 0.0 then begin
        let ratio = prices_arr.(orig_i) /. cma_arr.(i) in
        let m = months_arr.(orig_i) in
        month_ratios.(m - 1) <- ratio :: month_ratios.(m - 1)
      end
    done;

    (* Average ratios per month = raw seasonal index *)
    let raw_indices = Array.map (fun ratios ->
      match ratios with
      | [] -> 1.0  (* no data for this month; default to neutral *)
      | _ -> Common.mean ratios
    ) month_ratios in

    (* Normalize so indices average to 1.0 *)
    let raw_mean = Common.mean (Array.to_list raw_indices) in
    let seasonal = Array.map (fun idx ->
      if raw_mean > 0.0 then idx /. raw_mean else idx
    ) raw_indices in

    (* Build indexed list for sorting: (month 1-12, index) *)
    let indexed = List.init 12 (fun i -> (i + 1, seasonal.(i))) in
    let sorted_asc = List.sort (fun (_, a) (_, b) -> Float.compare a b) indexed in
    let sorted_desc = List.sort (fun (_, a) (_, b) -> Float.compare b a) indexed in

    (* Best months: lowest 2 seasonal indices *)
    let best = List.filteri (fun i _ -> i < 2) sorted_asc in
    let best_names = List.map (fun (m, _) -> month_names.(m - 1)) best in

    (* Worst months: highest 2 seasonal indices *)
    let worst = List.filteri (fun i _ -> i < 2) sorted_desc in
    let worst_names = List.map (fun (m, _) -> month_names.(m - 1)) worst in

    (* Recommendation text *)
    let best_discount =
      match best with
      | (_, idx) :: _ -> Float.abs (1.0 -. idx) *. 100.0
      | [] -> 0.0
    in
    let recommendation =
      match best_names with
      | [a; b] ->
        Printf.sprintf "Best time to buy is %s-%s when prices are %.0f%% below average"
          a b best_discount
      | [a] ->
        Printf.sprintf "Best time to buy is %s when prices are %.0f%% below average"
          a best_discount
      | _ -> "Insufficient seasonal variation detected"
    in

    let months_covered = count_distinct_months data in

    `Assoc [
      ("seasonal_index", `List (List.init 12 (fun i ->
        let idx = Common.round3 seasonal.(i) in
        `Assoc [
          ("month", `Int (i + 1));
          ("month_name", `String month_names.(i));
          ("index", `Float idx);
          ("label", `String (label_of_index idx));
        ]
      )));
      ("best_months", `List (List.map (fun s -> `String s) best_names));
      ("worst_months", `List (List.map (fun s -> `String s) worst_names));
      ("recommendation", `String recommendation);
      ("data_points", `Int n);
      ("months_covered", `Int months_covered);
    ]
