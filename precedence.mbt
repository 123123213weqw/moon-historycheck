///|
fn predecessors(history : History) -> Array[Array[Int32]] {
  let result : Array[Array[Int32]] = []
  for later in history.operations {
    let incoming : Array[Int32] = []
    for i, earlier in history.operations {
      match earlier.returned {
        Some(end) => if end < later.call { incoming.push(i) }
        None => ()
      }
    }
    result.push(incoming)
  }
  result
}

///|
fn ready(incoming : Array[Int32], selected : Array[Bool]) -> Bool {
  for i in incoming {
    if !selected[i] {
      return false
    }
  }
  true
}

///|
fn pending_ids(history : History) -> Array[String] {
  history.operations.filter(fn(op) { !op.complete }).map(fn(op) { op.id })
}

///|
pub fn analyze(request : Json) -> Json raise HistoryError {
  let history = parse_history(request)
  analyze_history(history).to_json()
}

///|
fn analyze_history(history : History) -> Value {
  let incoming = predecessors(history)
  let edges : Array[Value] = []
  let mut overlaps = 0
  let times : Array[(Double, Int32)] = []
  for j, op in history.operations {
    for i in incoming[j] {
      edges.push(
        record([
          ("before", String(history.operations[i].id)),
          ("after", String(op.id)),
          ("basis", String("return_before_call")),
        ]),
      )
    }
    for i in 0..<j {
      if !incoming[j].contains(i) && !incoming[i].contains(j) {
        overlaps += 1
      }
    }
    times.push((op.call, 1))
    match op.returned {
      Some(end) => times.push((end, -1))
      None => ()
    }
  }
  times.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut active = 0
  let mut peak = 0
  for (_, delta) in times {
    active += delta
    if active > peak {
      peak = active
    }
  }
  record([
    ("model", String(model_name(history.model))),
    ("operation_count", Number(history.operations.length().to_double())),
    ("precedence_edges", Array(edges)),
    ("edge_count", Number(edges.length().to_double())),
    ("overlap_pairs", Number(overlaps.to_double())),
    ("max_in_flight", Number(peak.to_double())),
    ("pending", strings(pending_ids(history))),
    (
      "ordering_basis",
      String("unique recorder ordinals; not unsynchronized wall clocks"),
    ),
  ])
}
