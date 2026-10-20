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
    match operation {
      "check" => check_history(history, limits)
      "analyze" => analyze_history(history)
      _ => raise HistoryError("unsupported API operation: " + operation)
    }
  } catch {
    HistoryError(message) =>
      record([("verdict", String("invalid_input")), ("reason", String(message))])
  }
}
