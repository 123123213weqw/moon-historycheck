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
          let next = current + 1.0
          if next.is_nan() || next.is_inf() || next.abs() > 9007199254740991.0 {
            None
          } else if op.output == String("ok") {
            Some(Number(next))
          } else {
            None
          }
        }
        (Number(current), String("decrement")) => {
          let next = current - 1.0
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
  }
}
