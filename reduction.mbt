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
  let mut uncertain = false
  let mut stop = "fixed_point"
  // Delta debugging: try deleting contiguous chunks of operations, refine the
  // granularity after each accepted chunk, and stop only once every single
  // operation has failed to delete. Unknown subresults never justify deletion.
  let mut granularity = 2
  while stop == "fixed_point" {
    if checks >= max_checks {
      stop = "max_checks"
      break
    }
    if expanded >= limits.states {
      stop = "max_states"
      break
    }
    if granularity > current.operations.length() {
      granularity = current.operations.length()
    }
    let count = current.operations.length()
    let mut chunk = 0
    let mut accepted = false
    while chunk < granularity && stop == "fixed_point" {
      if checks >= max_checks {
        stop = "max_checks"
        break
      }
      if expanded >= limits.states {
        stop = "max_states"
        break
      }
      let start = chunk * count / granularity
      let end = (chunk + 1) * count / granularity
      if start >= end {
        chunk += 1
        continue
      }
      let candidate_ops : Array[Operation] = []
      let chunk_ids : Array[String] = []
      for i, op in current.operations {
        if i < start || i >= end {
          candidate_ops.push(op)
        } else {
          chunk_ids.push(op.id)
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
          ("removed_candidates", strings(chunk_ids)),
          ("verdict", field(result, "verdict")),
          ("reason", field(result, "reason")),
        ]),
      )
      match field(result, "verdict") {
        String("non_linearizable") => {
          for id in chunk_ids {
            removed.push(id)
          }
          current = candidate
          accepted = true
          // Restart: a deletion checked in the larger history proves nothing about this one.
          break
        }
        String("unknown") => {
          uncertain = true
          chunk += 1
        }
        _ => chunk += 1
      }
    }
    if stop != "fixed_point" {
      break
    }
    if accepted {
      uncertain = false
      if granularity > 2 {
        granularity -= 1
      }
      continue
    }
    if granularity >= count {
      break
    }
    granularity = if granularity * 2 > count { count } else { granularity * 2 }
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
