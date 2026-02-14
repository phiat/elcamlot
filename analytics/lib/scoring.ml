(** Deal scoring — rates a price against market data.

    Score 0-100:
    - 90-100: Exceptional deal (well below market)
    - 70-89:  Good deal (below average)
    - 40-69:  Fair price (around market)
    - 20-39:  Above market
    - 0-19:   Overpriced
*)

let float_of_json = function
  | `Int n -> Float.of_int n
  | `Float f -> f
  | _ -> 0.0

let deal_score json =
  match json with
  | `Assoc fields ->
    let price = match List.assoc_opt "price" fields with
      | Some v -> float_of_json v
      | None -> 0.0
    in
    let market_prices = match List.assoc_opt "market_prices" fields with
      | Some (`List ps) -> List.map float_of_json ps
      | _ -> []
    in
    if price <= 0.0 || market_prices = [] then
      `Assoc [("error", `String "Need price and market_prices")]
    else
      let sorted = List.sort Float.compare market_prices in
      let n = List.length sorted in
      let mean =
        List.fold_left ( +. ) 0.0 sorted /. Float.of_int n
      in
      (* How many market prices are above this price? *)
      let cheaper_count =
        List.length (List.filter (fun p -> p >= price) sorted)
      in
      let percentile_rank =
        Float.of_int cheaper_count /. Float.of_int n *. 100.0
      in
      (* Blend: percentile rank (how you compare to market)
         weighted with distance from mean *)
      let distance_factor =
        if Float.abs mean < 1.0 then 0.0
        else if price < mean then
          Float.min 1.0 ((mean -. price) /. mean *. 2.0)
        else
          Float.max (-1.0) ((mean -. price) /. mean *. 2.0)
      in
      let raw_score = percentile_rank *. 0.7 +. (distance_factor *. 30.0 +. 50.0) *. 0.3 in
      let score = Float.max 0.0 (Float.min 100.0 raw_score) in
      let label =
        if score >= 90.0 then "exceptional"
        else if score >= 70.0 then "good"
        else if score >= 40.0 then "fair"
        else if score >= 20.0 then "above_market"
        else "overpriced"
      in
      `Assoc [
        ("score", `Float (Float.round score));
        ("label", `String label);
        ("market_mean", `Float mean);
        ("market_count", `Int n);
        ("percentile_rank", `Float (Float.round percentile_rank));
      ]
  | _ ->
    `Assoc [("error", `String "Expected JSON object")]
