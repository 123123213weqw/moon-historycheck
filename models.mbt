///|
fn register_transition(state : Value, input : Value, output : Value) -> Value? {
  match field(input, "type") {
    String("read") => if output == state { Some(state) } else { None }
    String("write") =>
      if output == String("ok") {
        Some(field(input, "value"))
      } else {
        None
      }
    String("cas") => {
      let succeeds = state == field(input, "expected")
      if output != Bool(succeeds) {
        None
      } else if succeeds {
        Some(field(input, "value"))
      } else {
        Some(state)
      }
    }
    _ => None
  }
}

///|
fn transition(model : Model, state : Value, op : Operation) -> Value? {
  match model {
    Register => register_transition(state, op.input, op.output)
    KeyValue =>
      match (state, field(op.input, "key")) {
        (Object(fields), String(key)) => {
          let current = fields.get(key).unwrap_or(Null)
          match register_transition(current, op.input, op.output) {
            None => None
            Some(next) =>
              // A read or failed CAS must not introduce a previously absent key.
              if current == next {
                Some(state)
              } else {
                let result = fields.copy()
                result[key] = next
                Some(Object(result))
              }
          }
        }
        _ => None
      }
    Queue =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            String("enqueue") =>
              if op.output != String("ok") {
                None
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("dequeue") =>
              if items.is_empty() {
                if op.output == record([("empty", Bool(true))]) {
                  Some(state)
                } else {
                  None
                }
              } else if op.output == record([("value", items[0])]) {
                let next : Array[Value] = []
                for i in 1..<items.length() {
                  next.push(items[i])
                }
                Some(Array(next))
              } else {
                None
              }
            _ => None
          }
        _ => None
      }
    Stack =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            String("push") =>
              if op.output != String("ok") {
                None
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("pop") =>
              if items.is_empty() {
                if op.output == record([("empty", Bool(true))]) {
                  Some(state)
                } else {
                  None
                }
              } else if op.output ==
                record([("value", items[items.length() - 1])]) {
                let next : Array[Value] = []
                for i in 0..<(items.length() - 1) {
                  next.push(items[i])
                }
                Some(Array(next))
              } else {
                None
              }
            _ => None
          }
        _ => None
      }
    Lock =>
      match (state, field(op.input, "type")) {
        // Acquire reports whether it took the lock: only one holder at a time.
        (Bool(locked), String("acquire")) =>
          if op.output == Bool(!locked) {
            Some(Bool(true))
          } else {
            None
          }
        // Releasing requires holding the lock.
        (Bool(true), String("release")) =>
          if op.output == String("ok") {
            Some(Bool(false))
          } else {
            None
          }
        (Bool(false), String("release")) => None
        _ => None
      }
    Set =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            String("add") =>
              if op.output != String("ok") {
                None
              } else if items.contains(field(op.input, "value")) {
                Some(state)
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("remove") => {
              // Membership and removal use structural JSON equality: true is not 1.
              let target = field(op.input, "value")
              if op.output != Bool(items.contains(target)) {
                None
              } else if items.contains(target) {
                let next : Array[Value] = []
                let mut skipped = false
                for item in items {
                  if !skipped && item == target {
                    skipped = true
                  } else {
                    next.push(item)
                  }
                }
                Some(Array(next))
              } else {
                Some(state)
              }
            }
            String("contains") =>
              if op.output == Bool(items.contains(field(op.input, "value"))) {
                Some(state)
              } else {
                None
              }
            _ => None
          }
        _ => None
      }
    Counter =>
      match (state, field(op.input, "type")) {
        (Number(current), String("increment")) => {
          let step = match field(op.input, "by") {
            Number(n) => n
            _ => 1.0
          }
          let next = current + step
          if next.is_nan() || next.is_inf() || next.abs() > 9007199254740991.0 {
            None
          } else if op.output == String("ok") {
            Some(Number(next))
          } else {
            None
          }
        }
        (Number(current), String("decrement")) => {
          let step = match field(op.input, "by") {
            Number(n) => n
            _ => 1.0
          }
          let next = current - step
          if next.is_nan() || next.is_inf() || next.abs() > 9007199254740991.0 {
            None
          } else if op.output == String("ok") {
            Some(Number(next))
          } else {
            None
          }
        }
        (Number(current), String("read")) =>
          if op.output == Number(current) {
            Some(state)
          } else {
            None
          }
        _ => None
      }
    Mapping =>
      match (state, field(op.input, "key")) {
        (Object(fields), String(key)) =>
          match field(op.input, "type") {
            String("put") =>
              if op.output != String("ok") {
                None
              } else {
                let next = fields.copy()
                next[key] = field(op.input, "value")
                Some(Object(next))
              }
            String("get") => {
              let current = fields.get(key).unwrap_or(Null)
              if op.output == current {
                Some(state)
              } else {
                None
              }
            }
            String("remove") => {
              let present = fields.contains(key)
              if op.output != Bool(present) {
                None
              } else if present {
                let next = fields.copy()
                ignore(next.remove(key))
                Some(Object(next))
              } else {
                Some(state)
              }
            }
            _ => None
          }
        _ => None
      }
    LwwSet =>
      match state {
        Object(sets) =>
          match (sets.get("adds"), sets.get("rems")) {
            (Some(Object(adds)), Some(Object(rems))) =>
              match (field(op.input, "type"), field(op.input, "element")) {
                (String(kind), String(element)) =>
                  if kind == "add" || kind == "remove" {
                    let at = match field(op.input, "at") {
                      Number(n) => n
                      _ => -1.0
                    }
                    if at < 0.0 || op.output != String("ok") {
                      None
                    } else {
                      let table = if kind == "add" { adds } else { rems }
                      let newer = match table.get(element) {
                        Some(Number(existing)) => at >= existing
                        _ => true
                      }
                      if !newer {
                        Some(state)
                      } else {
                        let next_table = table.copy()
                        next_table[element] = Number(at)
                        let next : Map[String, Value] = Map([])
                        next["adds"] = Object(
                          if kind == "add" {
                            next_table
                          } else {
                            adds
                          },
                        )
                        next["rems"] = Object(
                          if kind == "add" {
                            rems
                          } else {
                            next_table
                          },
                        )
                        Some(Object(next))
                      }
                    }
                  } else if kind == "contains" {
                    // Add-wins bias: an add tied with the remove keeps the element.
                    let present = match (adds.get(element), rems.get(element)) {
                      (Some(Number(added)), Some(Number(removed))) =>
                        added >= removed
                      (Some(_), None) => true
                      _ => false
                    }
                    if op.output == Bool(present) {
                      Some(state)
                    } else {
                      None
                    }
                  } else {
                    None
                  }
                _ => None
              }
            _ => None
          }
        _ => None
      }
    MaxRegister =>
      match (state, field(op.input, "type")) {
        (Number(current), String("write")) => {
          // Monotonic: a write below the current value cannot replay, and an
          // equal one leaves the state where it was.
          let value = field(op.input, "value")
          match value {
            Number(next) =>
              if op.output != String("ok") || next.is_nan() || next.is_inf() {
                None
              } else if next > current {
                Some(Number(next))
              } else if next == current {
                Some(state)
              } else {
                None
              }
            _ => None
          }
        }
        (Number(current), String("read")) =>
          if op.output == Number(current) {
            Some(state)
          } else {
            None
          }
        _ => None
      }
    GrowSet =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            String("add") =>
              if op.output != String("ok") {
                None
              } else if items.contains(field(op.input, "value")) {
                Some(state)
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("contains") =>
              if op.output == Bool(items.contains(field(op.input, "value"))) {
                Some(state)
              } else {
                None
              }
            _ => None
          }
        _ => None
      }
    TwoPhaseSet =>
      match state {
        Object(sets) =>
          match (sets.get("added"), sets.get("removed")) {
            (Some(Array(added)), Some(Array(removed))) => {
              let target = field(op.input, "value")
              match field(op.input, "type") {
                // Re-adding after a remove cannot resurrect the element: the
                // removed table only ever grows.
                String("add") =>
                  if op.output != String("ok") {
                    None
                  } else if added.contains(target) || removed.contains(target) {
                    Some(state)
                  } else {
                    let next_added = added.copy()
                    next_added.push(target)
                    let next : Map[String, Value] = Map([])
                    next["added"] = Array(next_added)
                    next["removed"] = Array(removed)
                    Some(Object(next))
                  }
                String("remove") => {
                  let present = added.contains(target) &&
                    !removed.contains(target)
                  if op.output != Bool(present) {
                    None
                  } else if !present {
                    Some(state)
                  } else {
                    let next_removed = removed.copy()
                    next_removed.push(target)
                    let next : Map[String, Value] = Map([])
                    next["added"] = Array(added)
                    next["removed"] = Array(next_removed)
                    Some(Object(next))
                  }
                }
                String("contains") => {
                  let present = added.contains(target) &&
                    !removed.contains(target)
                  if op.output == Bool(present) {
                    Some(state)
                  } else {
                    None
                  }
                }
                _ => None
              }
            }
            _ => None
          }
        _ => None
      }
  }
}
