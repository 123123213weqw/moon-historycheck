///|
priv struct ClosureNode {
  selected : Array[Bool]
  state : Value
  path : Array[String]
  edges : Array[Value]
}

///|
fn certificate_unknown(reason : String, expanded : Int32) -> Value {
  record([
    ("verdict", String("unknown")),
    ("reason", String(reason)),
    ("complete_search", Bool(false)),
    ("expanded_states", Number(expanded.to_double())),
  ])
}

///|
fn selected_ids(history : History, selected : Array[Bool]) -> Value {
  let ids : Array[String] = []
  for i, op in history.operations {
    if selected[i] {
      ids.push(op.id)
    }
  }
  strings(ids)
}

///|
fn certify_history(
  history : History,
  limits : SearchLimits,
) -> Value raise HistoryError {
  if !pending_ids(history).is_empty() {
    return check_verified(history, limits)
  }
  let first = Array::make(history.operations.length(), false)
  let root_key = state_key(first, history.initial)
  if root_key.length() > limits.units {
    return certificate_unknown("max_memo_units", 0)
  }
  let nodes : Array[ClosureNode] = [
    { selected: first, state: history.initial, path: [], edges: [], },
  ]
  let indexes : Map[String, Int32] = Map([(root_key, 0)])
  let incoming = predecessors(history)
  let mut units = root_key.length()
  let mut cursor = 0
  while cursor < nodes.length() {
    let node = nodes[cursor]
    if node.path.length() == history.operations.length() {
      let verified = verify_history(history, node.path)
      if field(verified, "valid") != Bool(true) {
        abort("closure search returned invalid witness")
      }
      return record([
        ("verdict", String("linearizable")),
        ("witness", strings(node.path)),
        ("witness_verified", Bool(true)),
        ("final_state", node.state),
        ("expanded_states", Number(cursor.to_double())),
        ("complete_search", Bool(false)),
      ])
    }
    if cursor >= limits.states {
      return certificate_unknown("max_states", cursor)
    }
    for i, op in history.operations {
      if node.selected[i] || !ready(incoming[i], node.selected) {
        continue
      }
      match transition(history.model, node.state, op) {
        None => ()
        Some(next) => {
          let selected = node.selected.copy()
          selected[i] = true
          let key = state_key(selected, next)
          let target = match indexes.get(key) {
            Some(index) => index
            None => {
              if nodes.length() >= limits.entries || nodes.length() >= 4096 {
                return certificate_unknown("certificate_node_budget", cursor)
              }
              if key.length() > limits.units - units {
                return certificate_unknown("max_memo_units", cursor)
              }
              units += key.length()
              let index = nodes.length()
              indexes[key] = index
              let path = node.path.copy()
              path.push(op.id)
              nodes.push({ selected, state: next, path, edges: [], })
              index
            }
          }
          node.edges.push(
            record([
              ("operation", String(op.id)),
              ("target", Number(target.to_double())),
            ]),
          )
        }
      }
    }
    cursor += 1
  }
  let records = nodes.map(fn(node) {
    record([
      ("selected", selected_ids(history, node.selected)),
      ("state", node.state),
      ("edges", Array(node.edges)),
    ])
  })
  let certificate = record([
    ("schema_version", Number(1)),
    ("history_canonical", String(history_value(history).canonical())),
    ("nodes", Array(records)),
  ])
  let verified = verify_certificate(history, certificate)
  if field(verified, "valid") != Bool(true) {
    abort("internal closed-state certificate failed verification")
  }
  record([
    ("verdict", String("non_linearizable")),
    ("complete_search", Bool(true)),
    ("certificate", certificate),
    ("certificate_verified", Bool(true)),
    ("expanded_states", Number(cursor.to_double())),
    ("memo_units", Number(units.to_double())),
  ])
}

///|
fn bad_certificate(reason : String) -> Value {
  record([
    ("verdict", String("invalid_certificate")),
    ("valid", Bool(false)),
    ("reason", String(reason)),
  ])
}

///|
fn verify_certificate(
  history : History,
  certificate : Value,
) -> Value raise HistoryError {
  if !pending_ids(history).is_empty() {
    return certificate_unknown("incomplete_operations", 0)
  }
  fields_only(certificate, ["schema_version", "history_canonical", "nodes"])
  if required(certificate, "schema_version") != Number(1) {
    return bad_certificate("unsupported schema version")
  }
  if string(required(certificate, "history_canonical")) !=
    history_value(history).canonical() {
    return bad_certificate("certificate belongs to a different history")
  }
  let raw = array(required(certificate, "nodes"))
  if raw.is_empty() || raw.length() > 4096 {
    return bad_certificate("certificate requires 1..4096 nodes")
  }
  let ids : Map[String, Int32] = Map([])
  for i, op in history.operations {
    ids[op.id] = i
  }
  let masks : Array[Array[Bool]] = []
  let states : Array[Value] = []
  let arcs : Array[Map[String, Int32]] = []
  let mut units = 0
  for entry in raw {
    fields_only(entry, ["selected", "state", "edges"])
    let mask = Array::make(history.operations.length(), false)
    let chosen = witness_ids(required(entry, "selected"))
    for id in chosen {
      match ids.get(id) {
        None => return bad_certificate("selected unknown operation: " + id)
        Some(i) => {
          if mask[i] {
            return bad_certificate("duplicate selected operation")
          }
          mask[i] = true
        }
      }
    }
    if chosen.length() == history.operations.length() {
      return bad_certificate("certificate contains a terminal candidate")
    }
    let state = required(entry, "state")
    validate_value(state, 0, Ref(0))
    units += state_key(mask, state).length()
    if units > 16000000 {
      return bad_certificate("certificate exceeds state-key unit limit")
    }
    let edges = array(required(entry, "edges"))
    if edges.length() > history.operations.length() {
      return bad_certificate("too many outgoing edges")
    }
    let edge_map : Map[String, Int32] = Map([])
    for edge in edges {
      fields_only(edge, ["operation", "target"])
      let id = identifier(required(edge, "operation"))
      if edge_map.contains(id) {
        return bad_certificate("duplicate outgoing operation")
      }
      let target = ordinal(required(edge, "target"))
      if target >= raw.length().to_double() {
        return bad_certificate("edge target outside certificate")
      }
      edge_map[id] = target.to_int()
    }
    masks.push(mask)
    states.push(state)
    arcs.push(edge_map)
  }
  if masks[0].contains(true) || states[0] != history.initial {
    return bad_certificate("invalid initial certificate node")
  }
  let reached = Array::make(raw.length(), false)
  let queue : Array[Int32] = [0]
  reached[0] = true
  let mut cursor = 0
  while cursor < queue.length() {
    let index = queue[cursor]
    cursor += 1
    let mask = masks[index]
    let mut expected_edges = 0
    for i, op in history.operations {
      if mask[i] {
        continue
      }
      let mut enabled = true
      // Direct obligations; do not use the generator's predecessor graph.
      for j, earlier in history.operations {
        match earlier.returned {
          Some(end) => if end < op.call && !mask[j] { enabled = false }
          None => ()
        }
      }
      if !enabled {
        continue
      }
      match transition(history.model, states[index], op) {
        None =>
          if arcs[index].contains(op.id) {
            return bad_certificate("edge for model-rejected output")
          }
        Some(next) => {
          expected_edges += 1
          let target = match arcs[index].get(op.id) {
            None => return bad_certificate("missing legal branch: " + op.id)
            Some(target) => target
          }
          let expected_mask = mask.copy()
          expected_mask[i] = true
          if masks[target] != expected_mask || states[target] != next {
            return bad_certificate("edge has wrong successor state")
          }
          if !reached[target] {
            reached[target] = true
            queue.push(target)
          }
        }
      }
    }
    if arcs[index].length() != expected_edges {
      return bad_certificate("edge for disabled or selected operation")
    }
  }
  if reached.contains(false) {
    return bad_certificate("unreachable certificate nodes")
  }
  record([
    ("verdict", String("valid_certificate")),
    ("valid", Bool(true)),
    ("proved_verdict", String("non_linearizable")),
    ("verified_nodes", Number(raw.length().to_double())),
  ])
}
