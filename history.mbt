///|
pub(all) enum Model {
  Register
  KeyValue
  Queue
} derive(Eq, @debug.Debug)

///|
pub(all) struct Operation {
  id : String
  client : String
  call : Double
  returned : Double?
  input : Value
  output : Value
  complete : Bool
} derive(Eq, @debug.Debug)

///|
pub(all) struct History {
  model : Model
  initial : Value
  operations : Array[Operation]
} derive(Eq, @debug.Debug)

///|
fn model_name(model : Model) -> String {
  match model {
    Register => "register"
    KeyValue => "kv_register"
    Queue => "queue"
  }
}

///|
fn validate_input(model : Model, input : Value) -> Unit raise HistoryError {
  let kind = string(required(input, "type"))
  match model {
    Register | KeyValue => {
      let allowed = match kind {
        "read" => ["type", "key"]
        "write" => ["type", "key", "value"]
        "cas" => ["type", "key", "value", "expected"]
        _ => raise HistoryError("unsupported register operation: " + kind)
      }
      fields_only(input, allowed)
      if model == KeyValue {
        ignore(identifier(required(input, "key")))
      } else if has(input, "key") {
        raise HistoryError("single register does not accept key")
      }
      if kind != "read" {
        ignore(required(input, "value"))
      }
      if kind == "cas" {
        ignore(required(input, "expected"))
      }
    }
    Queue =>
      match kind {
        "enqueue" => {
          fields_only(input, ["type", "value"])
          ignore(required(input, "value"))
        }
        "dequeue" => fields_only(input, ["type"])
        _ => raise HistoryError("unsupported queue operation: " + kind)
      }
  }
}

///|
pub fn parse_history(request : Json) -> History raise HistoryError {
  parse_history_value(from_json(request))
}

///|
fn parse_history_value(request : Value) -> History raise HistoryError {
  fields_only(request, [
    "operation", "model", "initial", "operations", "max_states", "max_memo_entries",
    "max_memo_units", "partition", "witness", "max_checks", "certificate",
  ])
  let model = match string(required(request, "model")) {
    "register" => Register
    "kv_register" => KeyValue
    "queue" => Queue
    name => raise HistoryError("unsupported model: " + name)
  }
  let initial = required(request, "initial")
  if model == KeyValue {
    ignore(object(initial))
  }
  if model == Queue {
    ignore(array(initial))
  }
  let raw = array(required(request, "operations"))
  if raw.length() > 256 {
    raise HistoryError("history exceeds 256 operations")
  }
  let ids : Map[String, Bool] = Map([])
  let ordinals : Map[String, Bool] = Map([])
  let result : Array[Operation] = []
  let nodes = Ref(0)
  validate_value(initial, 0, nodes)
  for entry in raw {
    fields_only(entry, ["id", "client", "call", "return", "input", "output"])
    let id = identifier(required(entry, "id"))
    if ids.contains(id) {
      raise HistoryError("duplicate operation ID: " + id)
    }
    ids[id] = true
    let client = identifier(required(entry, "client"))
    let call = ordinal(required(entry, "call"))
    let key = if call == 0.0 { "0" } else { Number(call).canonical() }
    if ordinals.contains(key) {
      raise HistoryError("event ordinals must be globally unique")
    }
    ordinals[key] = true
    let returned = if !has(entry, "return") || field(entry, "return") == Null {
      None
    } else {
      Some(ordinal(field(entry, "return")))
    }
    match returned {
      Some(end) => {
        if end <= call {
          raise HistoryError("return must follow call: " + id)
        }
        let key = Number(end).canonical()
        if ordinals.contains(key) {
          raise HistoryError("event ordinals must be globally unique")
        }
        ordinals[key] = true
      }
      None => ()
    }
    if returned is Some(_) && !has(entry, "output") {
      raise HistoryError("completed operation requires output: " + id)
    }
    if returned is None && has(entry, "output") {
      raise HistoryError("pending operation must not supply output: " + id)
    }
    let input = required(entry, "input")
    validate_input(model, input)
    validate_value(input, 0, nodes)
    let output = field(entry, "output")
    validate_value(output, 0, nodes)
    result.push({
      id,
      client,
      call,
      returned,
      input,
      output,
      complete: returned is Some(_),
    })
  }
  result.sort_by(fn(a, b) { a.call.compare(b.call) })
  { model, initial, operations: result, }
}

///|
fn operation_value(op : Operation) -> Value {
  let fields = object(
    record([
      ("id", String(op.id)),
      ("client", String(op.client)),
      ("call", Number(op.call)),
      ("input", op.input),
    ]),
  ) catch {
    _ => abort("internal object")
  }
  match op.returned {
    Some(end) => {
      fields["return"] = Number(end)
      fields["output"] = op.output
    }
    None => ()
  }
  Object(fields)
}

///|
fn history_value(history : History) -> Value {
  record([
    ("model", String(model_name(history.model))),
    ("initial", history.initial),
    ("operations", Array(history.operations.map(operation_value))),
  ])
}
