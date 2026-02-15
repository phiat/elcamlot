(** Historical volatility — log-returns, annualized vol, rolling window *)

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

let annualize daily_vol trading_days =
  daily_vol *. Float.sqrt (Float.of_int trading_days)

let rolling_vol returns window =
  let arr = Array.of_list returns in
  let n = Array.length arr in
  if n < window then []
  else
    List.init (n - window + 1) (fun i ->
      let slice = Array.to_list (Array.sub arr i window) in
      Common.std_dev slice
    )

let analyze json =
  let prices = Common.extract_prices json in
  let window = match json with
    | `Assoc fields ->
      (match List.assoc_opt "window" fields with
       | Some v -> (match Common.int_of_json_opt v with Some w -> w | None -> 20)
       | None -> 20)
    | _ -> 20
  in
  let trading_days = match json with
    | `Assoc fields ->
      (match List.assoc_opt "trading_days" fields with
       | Some v -> (match Common.int_of_json_opt v with Some d -> d | None -> 252)
       | None -> 252)
    | _ -> 252
  in
  match prices with
  | [] | [_] ->
    `Assoc [("error", `String "Need at least 2 prices")]
  | _ ->
    let returns = log_returns prices in
    let daily_vol = Common.std_dev returns in
    let annual_vol = annualize daily_vol trading_days in
    let rolling = rolling_vol returns window in
    `Assoc [
      ("daily_vol", `Float (Common.round2 daily_vol));
      ("annualized_vol", `Float (Common.round2 annual_vol));
      ("mean_return", `Float (Common.round2 (Common.mean returns)));
      ("num_returns", `Int (List.length returns));
      ("window", `Int window);
      ("trading_days", `Int trading_days);
      ("rolling_vol", `List (List.map (fun v -> `Float (Common.round2 v)) rolling));
    ]
