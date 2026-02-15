(** Moving averages — SMA, EMA, crossover detection *)

let sma prices window =
  let arr = Array.of_list prices in
  let n = Array.length arr in
  if n < window then []
  else
    List.init (n - window + 1) (fun i ->
      let sum = ref 0.0 in
      for j = i to i + window - 1 do
        sum := !sum +. arr.(j)
      done;
      !sum /. Float.of_int window
    )

let ema prices window =
  match prices with
  | [] -> []
  | first :: rest ->
    let alpha = 2.0 /. (Float.of_int window +. 1.0) in
    let _, result = List.fold_left (fun (prev, acc) price ->
      let value = alpha *. price +. (1.0 -. alpha) *. prev in
      (value, value :: acc)
    ) (first, [first]) rest in
    List.rev result

(** Detect crossovers between short and long MA series.
    Returns list of (index, "golden" | "death") *)
let detect_crossovers short_ma long_ma =
  let offset = List.length short_ma - List.length long_ma in
  if offset < 0 then []
  else
    let short_trimmed = List.filteri (fun i _ -> i >= offset) short_ma in
    let pairs = List.combine short_trimmed long_ma in
    let _, signals = List.fold_left (fun (prev_above, acc) (i, (s, l)) ->
      let above = s > l in
      let signal =
        match prev_above with
        | Some was_above when was_above <> above ->
          Some (i, if above then "golden" else "death")
        | _ -> None
      in
      (Some above, match signal with Some s -> s :: acc | None -> acc)
    ) (None, []) (List.mapi (fun i pair -> (i, pair)) pairs) in
    List.rev signals

let analyze json =
  let prices = Common.extract_prices json in
  let short_window = match json with
    | `Assoc fields ->
      (match List.assoc_opt "short_window" fields with
       | Some v -> (match Common.int_of_json_opt v with Some w -> w | None -> 20)
       | None -> 20)
    | _ -> 20
  in
  let long_window = match json with
    | `Assoc fields ->
      (match List.assoc_opt "long_window" fields with
       | Some v -> (match Common.int_of_json_opt v with Some w -> w | None -> 50)
       | None -> 50)
    | _ -> 50
  in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | _ when List.length prices < short_window ->
    `Assoc [("error", `String (Printf.sprintf "Need at least %d prices for short window" short_window))]
  | _ ->
    let short_sma = sma prices short_window in
    let long_sma = sma prices long_window in
    let short_ema = ema prices short_window in
    let crossovers = detect_crossovers short_sma long_sma in
    let n = List.length prices in
    `Assoc [
      ("sma_short", `List (List.map (fun v -> `Float (Common.round2 v)) short_sma));
      ("sma_long", `List (List.map (fun v -> `Float (Common.round2 v)) long_sma));
      ("ema_short", `List (List.map (fun v -> `Float (Common.round2 v)) short_ema));
      ("short_window", `Int short_window);
      ("long_window", `Int long_window);
      ("data_points", `Int n);
      ("crossovers", `List (List.map (fun (i, kind) ->
        `Assoc [
          ("index", `Int i);
          ("type", `String kind);
        ]
      ) crossovers));
      ("current_trend", `String (
        if long_sma = [] then "insufficient_data"
        else
          let last_short = List.nth short_sma (List.length short_sma - 1) in
          let last_long = List.nth long_sma (List.length long_sma - 1) in
          if last_short > last_long then "bullish" else "bearish"
      ));
    ]
