(** Histogram / binned distribution — configurable buckets with density *)

let float_of_json = function
  | `Int n -> Float.of_int n
  | `Float f -> f
  | _ -> 0.0

let int_of_json_opt = function
  | `Int n -> Some n
  | `Float f -> Some (Float.to_int f)
  | _ -> None

let extract_prices json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "prices" fields with
     | Some (`List prices) -> List.map float_of_json prices
     | _ -> [])
  | _ -> []

let extract_bins json =
  match json with
  | `Assoc fields ->
    (match List.assoc_opt "bins" fields with
     | Some v -> int_of_json_opt v
     | None -> None)
  | _ -> None

(** Sturges' rule for default bin count *)
let default_bins n =
  let k = Float.to_int (Float.ceil (Float.log (Float.of_int n) /. Float.log 2.0 +. 1.0)) in
  max k 5

let analyze json =
  let prices = extract_prices json in
  match prices with
  | [] ->
    `Assoc [("error", `String "No prices provided")]
  | prices ->
    let sorted = List.sort Float.compare prices in
    let n = List.length sorted in
    let min_val = List.hd sorted in
    let max_val = List.nth sorted (n - 1) in

    let num_bins = match extract_bins json with
      | Some b when b > 0 && b <= 100 -> b
      | _ -> default_bins n
    in

    let range = max_val -. min_val in
    let bin_width = if range < 0.001 then 1.0 else range /. Float.of_int num_bins in

    (* Build bin edges and counts *)
    let bins = Array.make num_bins 0 in
    List.iter (fun price ->
      let idx = Float.to_int ((price -. min_val) /. bin_width) in
      let idx = min idx (num_bins - 1) in
      bins.(idx) <- bins.(idx) + 1
    ) prices;

    let fn_float = Float.of_int in

    (* Find mode bin *)
    let mode_idx = ref 0 in
    let mode_count = ref 0 in
    Array.iteri (fun i c ->
      if c > !mode_count then begin
        mode_count := c;
        mode_idx := i
      end
    ) bins;

    (* Check for multimodal: any bin with count >= 80% of mode that's not adjacent *)
    let threshold = Float.to_int (fn_float !mode_count *. 0.8) in
    let multimodal = Array.to_list bins
      |> List.mapi (fun i c -> (i, c))
      |> List.exists (fun (i, c) ->
        c >= threshold && abs (i - !mode_idx) > 1
      )
    in

    (* Build response *)
    let bin_data = List.init num_bins (fun i ->
      let low = min_val +. fn_float i *. bin_width in
      let high = low +. bin_width in
      let count = bins.(i) in
      let density = fn_float count /. (fn_float n *. bin_width) in
      `Assoc [
        ("bin_low", `Float (Float.round (low *. 100.0) /. 100.0));
        ("bin_high", `Float (Float.round (high *. 100.0) /. 100.0));
        ("count", `Int count);
        ("density", `Float density);
      ]
    ) in

    (* Cumulative counts *)
    let cumulative = List.init num_bins (fun i ->
      let cum = ref 0 in
      for j = 0 to i do cum := !cum + bins.(j) done;
      `Float (fn_float !cum /. fn_float n)
    ) in

    let mode_low = min_val +. fn_float !mode_idx *. bin_width in
    let mode_high = mode_low +. bin_width in

    `Assoc [
      ("bins", `List bin_data);
      ("cumulative", `List cumulative);
      ("bin_width", `Float (Float.round (bin_width *. 100.0) /. 100.0));
      ("num_bins", `Int num_bins);
      ("mode_bin", `Assoc [
        ("low", `Float (Float.round (mode_low *. 100.0) /. 100.0));
        ("high", `Float (Float.round (mode_high *. 100.0) /. 100.0));
        ("count", `Int !mode_count);
      ]);
      ("multimodal", `Bool multimodal);
      ("total", `Int n);
    ]
