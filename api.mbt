///|
pub fn execute(request : Json) -> Json {
  run(from_json(request)).to_json()
}

///|
pub fn run(request : Value) -> Value {
  try {
    let history = parse_history_value(request)
    let limits = search_limits(request)
    let operation = if has(request, "operation") {
      string(field(request, "operation"))
    } else {
      "check"
    }
    let partitioned = if has(request, "partition") {
      match field(request, "partition") {
        Bool(b) => b
        _ => raise HistoryError("partition must be boolean")
      }
    } else {
      false
    }
    if partitioned && (history.model != KeyValue || operation != "check") {
      raise HistoryError("partition requires check on kv_register")
    }
    match operation {
      "check" =>
        if partitioned {
          check_partitioned(history, limits)
        } else {
          check_verified(history, limits)
        }
      "verify" =>
        verify_history(history, witness_ids(required(request, "witness")))
      "analyze" => analyze_history(history)
      _ => raise HistoryError("unsupported API operation: " + operation)
    }
  } catch {
    HistoryError(message) =>
      record([("verdict", String("invalid_input")), ("reason", String(message))])
  }
}
