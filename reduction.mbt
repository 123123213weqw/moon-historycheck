///|
fn expanded_states(result : Value) -> Int32 {
  match field(field(result, "stats"), "expanded_states") {
    Number(n) => n.to_int()
    _ => 0
  }
}

///|
fn reduce_history(
  history : History,
  limits : SearchLimits,
  max_checks : Int32,
) -> Value raise HistoryError {
  let original = check_verified(history, limits)
  if field(original, "verdict") != String("non_linearizable") {
    return record([
      ("verdict", field(original, "verdict")),
      ("reason", String("reduction_requires_a_definite_counterexample")),
      ("original_result", original),
      ("reduction_complete", Bool(false)),
    ])
  }
  let mut current = history
  let removed : Array[String] = []
  let trials : Array[Value] = []
  let mut checks = 1
  let mut expanded = expanded_states(original)
  let mut index = 0
  let mut uncertain = false
  let mut stop = "fixed_point"
  while index < current.operations.length() {
    if checks >= max_checks {
      stop = "max_checks"
      break
    }
    if expanded >= limits.states {
      stop = "max_states"
      break
    }
    let candidate_ops : Array[Operation] = []
    for i, op in current.operations {
      if i != index {
        candidate_ops.push(op)
      }
    }
    let candidate : History = { ..current, operations: candidate_ops, }
    let result = check_verified(candidate, {
      ..limits,
      states: limits.states - expanded,
    })
    checks += 1
    expanded += expanded_states(result)
    trials.push(
      record([
        ("removed_candidate", String(current.operations[index].id)),
        ("verdict", field(result, "verdict")),
        ("reason", field(result, "reason")),
      ]),
    )
    match field(result, "verdict") {
      String("non_linearizable") => {
        removed.push(current.operations[index].id)
        current = candidate
        // Restart: a deletion checked in the larger history proves nothing about this one.
        index = 0
        uncertain = false
      }
      String("unknown") => {
        uncertain = true
        index += 1
      }
      _ => index += 1
    }
  }
  let complete = stop == "fixed_point" && !uncertain
  if stop == "fixed_point" && uncertain {
    stop = "unknown_subcheck"
  }
  record([
    ("verdict", String("non_linearizable")),
    (
      "original_operation_count",
      Number(history.operations.length().to_double()),
    ),
    (
      "remaining_operation_count",
      Number(current.operations.length().to_double()),
    ),
    ("history", history_value(current)),
    ("removed", strings(removed)),
    ("solver_checks", Number(checks.to_double())),
    ("total_expanded_states", Number(expanded.to_double())),
    ("trials", Array(trials)),
    ("reduction_complete", Bool(complete)),
    (
      "minimality",
      String(
        if complete {
          "1-minimal_under_single_operation_deletion"
        } else {
          "not_proven"
        },
      ),
    ),
    ("stopping_reason", String(stop)),
  ])
}
