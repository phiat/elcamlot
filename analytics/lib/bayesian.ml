(** Bayesian estimation — Normal-Normal conjugate updating *)

let float_opt_of_json_field fields key =
  match List.assoc_opt key fields with
  | Some (`Float f) -> Some f
  | Some (`Int n) -> Some (Float.of_int n)
  | _ -> None

let estimate json =
  let prices = Common.extract_prices json in
  match prices with
  | [] | [_] ->
    `Assoc [("error", `String "Need at least 2 prices for Bayesian estimation")]
  | prices ->
    let n = List.length prices in
    let nf = Float.of_int n in
    let sample_mean = Common.mean prices in
    (* Sample variance (unbiased, n-1 denominator) *)
    let sample_variance =
      let m = sample_mean in
      List.fold_left (fun acc p -> acc +. (p -. m) ** 2.0) 0.0 prices
      /. (nf -. 1.0)
    in
    if sample_variance <= 0.0 then
      `Assoc [("error", `String "All prices are identical; variance is zero")]
    else
      (* Extract optional prior parameters *)
      let fields = match json with `Assoc f -> f | _ -> [] in
      let prior_mean =
        match float_opt_of_json_field fields "prior_mean" with
        | Some m -> m
        | None -> List.hd prices
      in
      let prior_variance =
        match float_opt_of_json_field fields "prior_variance" with
        | Some v when v > 0.0 -> v
        | _ ->
          let sorted = List.sort Float.compare prices in
          let lo = List.hd sorted in
          let hi = List.nth sorted (n - 1) in
          let range = hi -. lo in
          (range *. 2.0) ** 2.0
      in
      (* Normal-Normal conjugate update *)
      let prior_precision = 1.0 /. prior_variance in
      let data_precision = nf /. sample_variance in
      let posterior_precision = prior_precision +. data_precision in
      let posterior_mean =
        (prior_precision *. prior_mean +. data_precision *. sample_mean)
        /. posterior_precision
      in
      let posterior_variance = 1.0 /. posterior_precision in
      (* 95% credible interval *)
      let margin = 1.96 *. Float.sqrt posterior_variance in
      let ci_lower = posterior_mean -. margin in
      let ci_upper = posterior_mean +. margin in
      (* Weights: relative influence of prior vs data *)
      let prior_weight = prior_precision /. posterior_precision in
      let data_weight = data_precision /. posterior_precision in
      (* Shrinkage: how much posterior moved toward data (1.0 = data dominates) *)
      let shrinkage = data_weight in
      `Assoc [
        ("posterior_mean", `Float (Common.round2 posterior_mean));
        ("posterior_variance", `Float (Common.round2 posterior_variance));
        ("credible_interval_95", `Assoc [
          ("lower", `Float (Common.round2 ci_lower));
          ("upper", `Float (Common.round2 ci_upper));
        ]);
        ("prior", `Assoc [
          ("mean", `Float (Common.round2 prior_mean));
          ("variance", `Float (Common.round2 prior_variance));
          ("weight", `Float (Common.round3 prior_weight));
        ]);
        ("data", `Assoc [
          ("mean", `Float (Common.round2 sample_mean));
          ("variance", `Float (Common.round2 sample_variance));
          ("weight", `Float (Common.round3 data_weight));
          ("n", `Int n);
        ]);
        ("shrinkage", `Float (Common.round3 shrinkage));
        ("data_points", `Int n);
      ]
