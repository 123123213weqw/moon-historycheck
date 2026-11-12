///|
pub fn execute(request : Json) -> Json {
  run(from_json(request)).to_json()
}

///|
/// The model catalog: one entry per sequential model the checker
/// knows, with its string name and a one-line description of what it
/// models. `supports_partition` marks the models whose histories can
/// be keyed into independent subhistories.
#derive(@debug.Debug)
pub(all) struct ModelInfo {
  name : String
  description : String
  supports_partition : Bool
}

///|
pub extend ModelInfo with @debug.Debug::{to_repr}

///|
/// List every sequential model the checker supports: 24 entries in a
/// stable order, with the partition-capable models marked. This is the
/// machine-readable form of the README's model table - a caller does
/// not need to read documentation to know what `model` strings the
/// check operation accepts.
pub fn list_models() -> Array[ModelInfo] {
  [
    {
      name: "register",
      description: "read/CAS register",
      supports_partition: false,
    },
    {
      name: "kv_register",
      description: "independent keyed registers",
      supports_partition: true,
    },
    { name: "queue", description: "FIFO queue", supports_partition: false, },
    { name: "stack", description: "LIFO stack", supports_partition: false, },
    {
      name: "lock",
      description: "mutual-exclusion lock",
      supports_partition: false,
    },
    { name: "set", description: "membership set", supports_partition: false, },
    {
      name: "counter",
      description: "integer counter",
      supports_partition: false,
    },
    { name: "map", description: "key-value map", supports_partition: true, },
    {
      name: "lww_set",
      description: "last-writer-wins set",
      supports_partition: false,
    },
    {
      name: "max_register",
      description: "monotone max-register",
      supports_partition: false,
    },
    {
      name: "grow_only_set",
      description: "grow-only set",
      supports_partition: false,
    },
    {
      name: "two_phase_set",
      description: "two-phase set with tombstones",
      supports_partition: false,
    },
    {
      name: "min_register",
      description: "monotone min-register",
      supports_partition: false,
    },
    {
      name: "lww_register",
      description: "last-writer-wins register",
      supports_partition: false,
    },
    {
      name: "bounded_queue",
      description: "capacity-bounded FIFO queue",
      supports_partition: false,
    },
    {
      name: "deque",
      description: "double-ended queue",
      supports_partition: false,
    },
    {
      name: "semaphore",
      description: "counting semaphore",
      supports_partition: false,
    },
    {
      name: "rwlock",
      description: "reader-writer lock",
      supports_partition: false,
    },
    {
      name: "multiset",
      description: "multiset (bag)",
      supports_partition: false,
    },
    {
      name: "priority_queue",
      description: "priority queue with min-extract",
      supports_partition: false,
    },
    {
      name: "pncounter",
      description: "positive-negative counter",
      supports_partition: false,
    },
    {
      name: "lww_map",
      description: "last-writer-wins map",
      supports_partition: true,
    },
    {
      name: "or_set",
      description: "observed-remove set",
      supports_partition: false,
    },
    {
      name: "flag",
      description: "one-way boolean flag",
      supports_partition: false,
    },
  ]
}

///|
pub fn run(request : Value) -> Value {
  // The models catalog answers without parsing a history - it needs
  // no model field, no entries, and nothing else the check path wants.
  if has(request, "operation") {
    match field(request, "operation") {
      String("models") =>
        return Array(
          list_models().map(info => {
            record([
              ("name", String(info.name)),
              ("description", String(info.description)),
              ("supports_partition", Bool(info.supports_partition)),
            ])
          }),
        )
      _ => ()
    }
  }
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
    let partitionable = history.model == KeyValue ||
      history.model == Mapping ||
      history.model == LwwMap
    if partitioned && (!partitionable || operation != "check") {
      raise HistoryError(
        "partition requires check on kv_register, map or lww_map",
      )
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
