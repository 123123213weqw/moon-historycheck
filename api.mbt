///|
pub fn execute(request : Json) -> Json {
  run(from_json(request)).to_json()
}

///|
pub fn run(request : Value) -> Value {
  try {
    validate_api_fields(request)
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
    let partitionable = history.model == KeyValue || history.model == Mapping
    if partitioned && (!partitionable || operation != "check") {
      raise HistoryError("partition requires check on kv_register or map")
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
      "certify" => certify_history(history, limits)
      "verify_certificate" =>
        verify_certificate(history, required(request, "certificate"))
      "reduce" =>
        reduce_history(history, limits, limit(request, "max_checks", 200, 2000))
      _ => raise HistoryError("unsupported API operation: " + operation)
    }
  } catch {
    HistoryError(message) =>
      record([("verdict", String("invalid_input")), ("reason", String(message))])
  }
}

///|
fn validate_api_fields(request : Value) -> Unit raise HistoryError {
  let operation = if has(request, "operation") {
    string(field(request, "operation"))
  } else {
    "check"
  }
  let allowed = ["operation", "model", "initial", "operations"]
  match operation {
    "check" => {
      allowed.push("partition")
      allowed.push("max_states")
      allowed.push("max_memo_entries")
      allowed.push("max_memo_units")
    }
    "reduce" | "certify" => {
      if operation == "reduce" {
        allowed.push("max_checks")
      }
      allowed.push("max_states")
      allowed.push("max_memo_entries")
      allowed.push("max_memo_units")
    }
    "verify" => allowed.push("witness")
    "verify_certificate" => allowed.push("certificate")
    "analyze" => ()
    _ => raise HistoryError("unsupported API operation: " + operation)
  }
  allowed.push("max_operations")
  fields_only(request, allowed)
}
