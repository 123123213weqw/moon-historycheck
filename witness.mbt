///|
fn invalid_witness(reason : String) -> Value {
  record([
    ("verdict", String("invalid_witness")),
    ("valid", Bool(false)),
    ("reason", String(reason)),
  ])
}

///|
fn verify_history(history : History, witness : Array[String]) -> Value {
  if !pending_ids(history).is_empty() {
    return record([
      ("verdict", String("unknown")),
      ("valid", Bool(false)),
      ("reason", String("incomplete_operations")),
    ])
  }
  if witness.length() != history.operations.length() {
    return invalid_witness("witness must cover every operation exactly once")
  }
  let positions : Map[String, Int32] = Map::new()
  let by_id : Map[String, Operation] = Map::new()
  for op in history.operations {
    by_id[op.id] = op
  }
  for i, id in witness {
    if !by_id.contains(id) {
      return invalid_witness("unknown operation ID: " + id)
    }
    if positions.contains(id) {
      return invalid_witness("duplicate operation ID: " + id)
    }
    positions[id] = i
  }
  // Recompute all pairwise obligations directly, without the searcher's predecessor arrays.
  for first in history.operations {
    for second in history.operations {
      match first.returned {
        Some(end) =>
          if end < second.call && positions[first.id] >= positions[second.id] {
            return invalid_witness(
              "return-before-call violated: " + first.id + " -> " + second.id,
            )
          }
        None => ()
      }
    }
  }
  let mut state = history.initial
  let trace : Array[Value] = []
  for id in witness {
    let op = by_id[id]
    match transition(history.model, state, op) {
      None => return invalid_witness("observed output violates model at: " + id)
      Some(next) => {
        trace.push(
          record([("id", String(id)), ("before", state), ("after", next)]),
        )
        state = next
      }
    }
  }
  record([
    ("verdict", String("valid_witness")),
    ("valid", Bool(true)),
    ("final_state", state),
    ("trace", Array(trace)),
  ])
}

///|
fn witness_ids(value : Value) -> Array[String] raise HistoryError {
  array(value).map(fn(v) { identifier(v) })
}

///|
fn check_verified(
  history : History,
  limits : SearchLimits,
) -> Value raise HistoryError {
  let result = check_history(history, limits)
  if field(result, "verdict") == String("linearizable") {
    let witness = witness_ids(field(result, "witness"))
    let verified = verify_history(history, witness)
    if field(verified, "valid") != Bool(true) {
      abort("internal solver witness failed independent verification")
    }
    let fields = object(result)
    fields["witness_verified"] = Bool(true)
    return Object(fields)
  }
  result
}
