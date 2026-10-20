///|
priv struct SearchLimits {
  states : Int32
  entries : Int32
  units : Int32
}

///|
priv struct SearchContext {
  history : History
  incoming : Array[Array[Int32]]
  limits : SearchLimits
  memo : Map[String, Bool]
  mut explored : Int32
  mut hits : Int32
  mut rejected : Int32
  mut memo_units : Int32
}

///|
priv enum SearchOutcome {
  Found(Array[String], Value)
  Exhausted
  Limited(String)
}

///|
fn search_limits(request : Value) -> SearchLimits raise HistoryError {
  {
    states: limit(request, "max_states", 20000, 1000000),
    entries: limit(request, "max_memo_entries", 4096, 200000),
    units: limit(request, "max_memo_units", 1000000, 16000000),
  }
}

///|
fn state_key(selected : Array[Bool], state : Value) -> String {
  selected.map(fn(b) { if b { "1" } else { "0" } }).join("") +
  ":" +
  state.canonical()
}

///|
fn search_dfs(
  ctx : SearchContext,
  state : Value,
  selected : Array[Bool],
  path : Array[String],
) -> SearchOutcome {
  if path.length() == selected.length() {
    return Found(path.copy(), state)
  }
  let key = state_key(selected, state)
  if ctx.memo.contains(key) {
    ctx.hits += 1
    return Exhausted
  }
  if ctx.explored >= ctx.limits.states {
    return Limited("max_states")
  }
  ctx.explored += 1
  for i, op in ctx.history.operations {
    if selected[i] || !ready(ctx.incoming[i], selected) {
      continue
    }
    match transition(ctx.history.model, state, op) {
      None => ctx.rejected += 1
      Some(next) => {
        selected[i] = true
        path.push(op.id)
        let outcome = search_dfs(ctx, next, selected, path)
        ignore(path.pop())
        selected[i] = false
        match outcome {
          Found(_, _) | Limited(_) => return outcome
          Exhausted => ()
        }
      }
    }
  }
  // Memoize only fully exhausted states; a budget cut is never an impossibility proof.
  if ctx.memo.length() >= ctx.limits.entries {
    return Limited("max_memo_entries")
  }
  if key.length() > ctx.limits.units - ctx.memo_units {
    return Limited("max_memo_units")
  }
  ctx.memo[key] = true
  ctx.memo_units += key.length()
  Exhausted
}

///|
fn check_history(history : History, limits : SearchLimits) -> Value {
  let pending = pending_ids(history)
  if !pending.is_empty() {
    return record([
      ("verdict", String("unknown")),
      ("reason", String("incomplete_operations")),
      ("pending", strings(pending)),
      ("witness", Array([])),
      ("complete_search", Bool(false)),
    ])
  }
  let ctx : SearchContext = {
    history,
    incoming: predecessors(history),
    limits,
    memo: Map([]),
    explored: 0,
    hits: 0,
    rejected: 0,
    memo_units: 0,
  }
  let selected = Array::make(history.operations.length(), false)
  let outcome = search_dfs(ctx, history.initial, selected, [])
  let stats = record([
    ("expanded_states", Number(ctx.explored.to_double())),
    ("memo_hits", Number(ctx.hits.to_double())),
    ("memo_entries", Number(ctx.memo.length().to_double())),
    ("memo_units", Number(ctx.memo_units.to_double())),
    ("semantic_rejections", Number(ctx.rejected.to_double())),
    ("max_states", Number(limits.states.to_double())),
    ("max_memo_entries", Number(limits.entries.to_double())),
    ("max_memo_units", Number(limits.units.to_double())),
  ])
  match outcome {
    Found(witness, final_state) =>
      record([
        ("verdict", String("linearizable")),
        ("witness", strings(witness)),
        ("final_state", final_state),
        ("complete_search", Bool(false)),
        ("stats", stats),
      ])
    Exhausted =>
      record([
        ("verdict", String("non_linearizable")),
        ("witness", Array([])),
        ("complete_search", Bool(true)),
        ("stats", stats),
      ])
    Limited(reason) =>
      record([
        ("verdict", String("unknown")),
        ("reason", String(reason)),
        ("witness", Array([])),
        ("complete_search", Bool(false)),
        ("stats", stats),
      ])
  }
}
