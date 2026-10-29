///|
fn check_partitioned(
  history : History,
  limits : SearchLimits,
) -> Value raise HistoryError {
  if history.model != KeyValue && history.model != Mapping {
    raise HistoryError("partition is only supported by kv_register and map")
  }
  if !pending_ids(history).is_empty() {
    return check_verified(history, limits)
  }
  // kv_register strips the key and checks each object as a plain register;
  // map keeps the key because its commands name it and missing keys read null.
  let strip_key = history.model == KeyValue
  let groups : Map[String, Array[Operation]] = Map([])
  let initial = object(history.initial)
  for op in history.operations {
    let key = string(field(op.input, "key"))
    let input = object(op.input).copy()
    if strip_key {
      ignore(input.remove("key"))
    }
    let item : Operation = { ..op, input: Object(input), }
    match groups.get(key) {
      Some(items) => items.push(item)
      None => groups[key] = [item]
    }
  }
  let keys = groups.keys().collect()
  keys.sort_by(lexical_compare)
  let parts : Array[Value] = []
  let chains : Array[Array[String]] = []
  let mut explored = 0
  for key in keys {
    if explored >= limits.states {
      return record([
        ("verdict", String("unknown")),
        ("reason", String("max_states")),
        ("partitioned", Bool(true)),
        ("partitions", Array(parts)),
        ("expanded_states", Number(explored.to_double())),
      ])
    }
    let sub_initial = if strip_key {
      initial.get(key).unwrap_or(Null)
    } else {
      let seed : Map[String, Value] = Map([])
      match initial.get(key) {
        Some(value) => seed[key] = value
        None => ()
      }
      Object(seed)
    }
    let sub : History = {
      model: if strip_key {
        Register
      } else {
        Mapping
      },
      initial: sub_initial,
      operations: groups[key],
    }
    let result = check_verified(sub, {
      ..limits,
      states: limits.states - explored,
    })
    match field(field(result, "stats"), "expanded_states") {
      Number(n) => explored += n.to_int()
      _ => ()
    }
    parts.push(record([("key", String(key)), ("result", result)]))
    match field(result, "verdict") {
      String("non_linearizable") =>
        return record([
          ("verdict", String("non_linearizable")),
          ("failed_key", String(key)),
          ("partitioned", Bool(true)),
          ("partitions", Array(parts)),
          ("expanded_states", Number(explored.to_double())),
          ("complete_search", Bool(true)),
          (
            "proof_scope",
            String("one independent object exhaustively rejected"),
          ),
        ])
      String("unknown") =>
        return record([
          ("verdict", String("unknown")),
          ("reason", field(result, "reason")),
          ("partitioned", Bool(true)),
          ("partitions", Array(parts)),
          ("expanded_states", Number(explored.to_double())),
          ("complete_search", Bool(false)),
        ])
      _ => chains.push(witness_ids(field(result, "witness")))
    }
  }
  // Merge local witness chains while retaining every global return-before-call edge.
  let incoming = predecessors(history)
  let indexes : Map[String, Int32] = Map([])
  for i, op in history.operations {
    indexes[op.id] = i
  }
  let positions = Array::make(chains.length(), 0)
  let selected = Array::make(history.operations.length(), false)
  let witness : Array[String] = []
  while witness.length() < history.operations.length() {
    let mut advanced = false
    for i, chain in chains {
      if positions[i] >= chain.length() {
        continue
      }
      let id = chain[positions[i]]
      let index = indexes[id]
      if ready(incoming[index], selected) {
        selected[index] = true
        positions[i] += 1
        witness.push(id)
        advanced = true
        break
      }
    }
    if !advanced {
      return record([
        ("verdict", String("unknown")),
        ("reason", String("partition_witness_merge")),
        ("partitions", Array(parts)),
      ])
    }
  }
  let verified = verify_history(history, witness)
  if field(verified, "valid") != Bool(true) {
    abort("partition witness failed full-history verification")
  }
  record([
    ("verdict", String("linearizable")),
    ("partitioned", Bool(true)),
    ("partitions", Array(parts)),
    ("witness", strings(witness)),
    ("witness_verified", Bool(true)),
    ("final_state", field(verified, "final_state")),
    ("expanded_states", Number(explored.to_double())),
    ("complete_search", Bool(false)),
  ])
}
