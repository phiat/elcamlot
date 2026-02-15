(** Returns analysis — period returns, cumulative, Sharpe ratio *)

let period_returns prices =
  let rec aux acc = function
    | [] | [_] -> List.rev acc
    | p1 :: (p2 :: _ as rest) ->
      if p1 > 0.0 then
        aux ((p2 -. p1) /. p1 :: acc) rest
      else
        aux acc rest
  in
  aux [] prices

let cumulative_returns prices =
  match prices with
  | [] | [_] -> []
  | p0 :: rest ->
    if p0 <= 0.0 then []
    else List.map (fun p -> (p -. p0) /. p0) rest

let sharpe_ratio returns risk_free_rate =
  let excess = List.map (fun r -> r -. risk_free_rate) returns in
  let m = Common.mean excess in
  let sd = Common.std_dev excess in
  if sd < 1e-10 then 0.0
  else m /. sd

let analyze json =
  let prices = Common.extract_prices json in
  let risk_free = match json with
    | `Assoc fields ->
      (match List.assoc_opt "risk_free_rate" fields with
       | Some v -> Common.float_of_json v
       | None -> 0.0)
    | _ -> 0.0
  in
  let annualize_factor = match json with
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
    let returns = period_returns prices in
    let cum = cumulative_returns prices in
    let daily_rf = risk_free /. Float.of_int annualize_factor in
    let daily_sharpe = sharpe_ratio returns daily_rf in
    let annualized_sharpe = daily_sharpe *. Float.sqrt (Float.of_int annualize_factor) in
    let total_return = match cum with
      | [] -> 0.0
      | _ -> List.nth cum (List.length cum - 1)
    in
    `Assoc [
      ("total_return", `Float (Common.round3 total_return));
      ("mean_return", `Float (Common.round3 (Common.mean returns)));
      ("std_return", `Float (Common.round3 (Common.std_dev returns)));
      ("sharpe_ratio", `Float (Common.round3 annualized_sharpe));
      ("num_periods", `Int (List.length returns));
      ("cumulative", `List (List.map (fun r -> `Float (Common.round3 r)) cum));
    ]
