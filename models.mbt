///|
const BOUNDED_QUEUE_CAPACITY : Int32 = 3

///|
/// The two per-actor tables of one multi_pncounter key. A key that no
/// operation has touched yet reads as two empty tables.
fn multi_pncounter_tables(
  entries : Map[String, Value],
  key : String,
) -> (Map[String, Value], Map[String, Value]) {
  match entries.get(key) {
    Some(Object(regs)) =>
      match (regs.get("p"), regs.get("n")) {
        (Some(Object(p)), Some(Object(n))) => (p, n)
        _ => (Map([]), Map([]))
      }
    _ => (Map([]), Map([]))
  }
}

///|
/// Apply one multi_pncounter increment (positive) or decrement to the
/// named key's table, creating the key when absent.
fn multi_pncounter_bump(
  entries : Map[String, Value],
  key : String,
  who : String,
  by : Double,
  positive : Bool,
) -> Value? {
  let (p, n) = multi_pncounter_tables(entries, key)
  if positive {
    let current = match p.get(who) {
      Some(Number(v)) => v
      _ => 0.0
    }
    let next = current + by
    if next.is_nan() || next.is_inf() || next.abs() > 9007199254740991.0 {
      None
    } else {
      let next_p = p.copy()
      next_p[who] = Number(next)
      let result = entries.copy()
      result[key] = record([("p", Object(next_p)), ("n", Object(n))])
      Some(Object(result))
    }
  } else {
    let current = match n.get(who) {
      Some(Number(v)) => v
      _ => 0.0
    }
    let next = current + by
    if next.is_nan() || next.is_inf() || next.abs() > 9007199254740991.0 {
      None
    } else {
      let next_n = n.copy()
      next_n[who] = Number(next)
      let result = entries.copy()
      result[key] = record([("p", Object(p)), ("n", Object(next_n))])
      Some(Object(result))
    }
  }
}

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
    MinRegister =>
      match (state, field(op.input, "type")) {
        (Number(current), String("write")) => {
          // Anti-monotonic: a write above the current value cannot replay,
          // an equal one leaves the state where it was.
          let value = field(op.input, "value")
          match value {
            Number(next) =>
              if op.output != String("ok") || next.is_nan() || next.is_inf() {
                None
              } else if next < current {
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
    LwwRegister =>
      match (state, field(op.input, "type")) {
        (Null, String("write")) => {
          let at = match field(op.input, "at") {
            Number(n) => n
            _ => -1.0
          }
          if op.output == String("ok") && at >= 0.0 {
            Some(
              record([("value", field(op.input, "value")), ("at", Number(at))]),
            )
          } else {
            None
          }
        }
        (Object(reg), String("write")) => {
          let at = match field(op.input, "at") {
            Number(n) => n
            _ => -1.0
          }
          let current_at = match reg["at"] {
            Number(n) => n
            _ => -1.0
          }
          // Strictly newer timestamps move the register; a tie cannot replay.
          if op.output == String("ok") && at > current_at {
            Some(
              record([("value", field(op.input, "value")), ("at", Number(at))]),
            )
          } else {
            None
          }
        }
        (Null, String("read")) =>
          // An unwritten register reads as null.
          if op.output == Null {
            Some(state)
          } else {
            None
          }
        (Object(reg), String("read")) =>
          if op.output == reg["value"] {
            Some(state)
          } else {
            None
          }
        _ => None
      }
    BoundedQueue =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            String("enqueue") =>
              // A full queue refuses the enqueue with false; nothing else can
              // be observed, because the element never entered.
              if items.length() >= BOUNDED_QUEUE_CAPACITY {
                if op.output == Bool(false) {
                  Some(state)
                } else {
                  None
                }
              } else if op.output != String("ok") {
                None
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("dequeue") => {
              let want = if items.is_empty() {
                record([("empty", Bool(true))])
              } else {
                record([("value", items[0])])
              }
              if op.output == want {
                if items.is_empty() {
                  Some(state)
                } else {
                  let next : Array[Value] = []
                  for i in 1..<items.length() {
                    next.push(items[i])
                  }
                  Some(Array(next))
                }
              } else {
                None
              }
            }
            _ => None
          }
        _ => None
      }
    Deque =>
      match state {
        Array(items) => {
          let kind = field(op.input, "type")
          let is_push = kind == String("push_front") ||
            kind == String("push_back")
          if is_push {
            if op.output != String("ok") {
              None
            } else {
              let next = items.copy()
              if kind == String("push_front") {
                next.insert(0, field(op.input, "value"))
              } else {
                next.push(field(op.input, "value"))
              }
              Some(Array(next))
            }
          } else if items.is_empty() {
            if op.output == record([("empty", Bool(true))]) {
              Some(state)
            } else {
              None
            }
          } else if kind == String("pop_front") {
            if op.output == record([("value", items[0])]) {
              let next : Array[Value] = []
              for i in 1..<items.length() {
                next.push(items[i])
              }
              Some(Array(next))
            } else {
              None
            }
          } else if kind == String("pop_back") {
            if op.output == record([("value", items[items.length() - 1])]) {
              let next : Array[Value] = []
              for i in 0..<(items.length() - 1) {
                next.push(items[i])
              }
              Some(Array(next))
            } else {
              None
            }
          } else {
            None
          }
        }
        _ => None
      }
    Semaphore =>
      match (state, field(op.input, "type")) {
        (Object(sets), String("acquire")) => {
          let permits = match sets["permits"] {
            Number(n) => n
            _ => -1.0
          }
          let taken = match sets["taken"] {
            Number(n) => n
            _ => -1.0
          }
          if permits < 0.0 || taken < 0.0 {
            None
          } else if taken < permits {
            if op.output == Bool(true) {
              Some(
                record([
                  ("permits", Number(permits)),
                  ("taken", Number(taken + 1.0)),
                ]),
              )
            } else {
              None
            }
          } else if op.output == Bool(false) {
            Some(state)
          } else {
            None
          }
        }
        (Object(sets), String("release")) => {
          let permits = match sets["permits"] {
            Number(n) => n
            _ => -1.0
          }
          let taken = match sets["taken"] {
            Number(n) => n
            _ => -1.0
          }
          if op.output != String("ok") || taken <= 0.0 || taken > permits {
            None
          } else {
            Some(
              record([
                ("permits", Number(permits)),
                ("taken", Number(taken - 1.0)),
              ]),
            )
          }
        }
        _ => None
      }
    RwLock =>
      match (state, field(op.input, "type")) {
        (Object(sets), String("acquire_read")) => {
          let readers = match sets["readers"] {
            Number(n) => n
            _ => -1.0
          }
          let writer = sets["writer"] == Bool(true)
          // Blocked by the writer: observing false is the legal verdict.
          if writer {
            if op.output == Bool(false) {
              Some(state)
            } else {
              None
            }
          } else if op.output == Bool(true) {
            Some(
              record([
                ("readers", Number(readers + 1.0)),
                ("writer", Bool(false)),
              ]),
            )
          } else {
            None
          }
        }
        (Object(sets), String("release_read")) => {
          let readers = match sets["readers"] {
            Number(n) => n
            _ => -1.0
          }
          if op.output != String("ok") || readers <= 0 {
            None
          } else {
            Some(
              record([
                ("readers", Number(readers - 1.0)),
                ("writer", Bool(sets["writer"] == Bool(true))),
              ]),
            )
          }
        }
        (Object(sets), String("acquire_write")) => {
          let readers = match sets["readers"] {
            Number(n) => n
            _ => -1.0
          }
          let writer = sets["writer"] == Bool(true)
          // Blocked by readers or another writer: observing false is the
          // legal verdict, not a replay failure.
          if readers > 0 || writer {
            if op.output == Bool(false) {
              Some(state)
            } else {
              None
            }
          } else if op.output == Bool(true) {
            Some(record([("readers", Number(0.0)), ("writer", Bool(true))]))
          } else {
            None
          }
        }
        (Object(sets), String("release_write")) => {
          let writer = sets["writer"] == Bool(true)
          if op.output != String("ok") || !writer {
            None
          } else {
            Some(record([("readers", Number(0.0)), ("writer", Bool(false))]))
          }
        }
        _ => None
      }
    MultiSet =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            // A multiset counts duplicates: remove drops exactly one copy
            // and reports whether one existed; count reports the number of
            // copies present.
            String("add") =>
              if op.output != String("ok") {
                None
              } else {
                let next = items.copy()
                next.push(field(op.input, "value"))
                Some(Array(next))
              }
            String("remove") => {
              let target = field(op.input, "value")
              let copies = items.iter().filter(fn(x) { x == target }).count()
              if op.output != Number(copies.to_double()) {
                None
              } else if copies == 0 {
                Some(state)
              } else {
                let next : Array[Value] = []
                let mut skipped = 0
                for item in items {
                  if item == target && skipped < 1 {
                    skipped += 1
                  } else {
                    next.push(item)
                  }
                }
                Some(Array(next))
              }
            }
            String("count") => {
              let target = field(op.input, "value")
              let copies = items.iter().filter(fn(x) { x == target }).count()
              if op.output == Number(copies.to_double()) {
                Some(state)
              } else {
                None
              }
            }
            _ => None
          }
        _ => None
      }
    PriorityQueue =>
      match state {
        Array(items) =>
          match field(op.input, "type") {
            // Push appends in insertion order; pop_min removes the element
            // with the smallest priority, first-inserted among ties.
            String("push") => {
              let priority = match field(op.input, "priority") {
                Number(n) => n
                _ => -1.0
              }
              if op.output != String("ok") || priority < 0.0 {
                None
              } else {
                let next = items.copy()
                next.push(
                  record([
                    ("value", field(op.input, "value")),
                    ("priority", Number(priority)),
                  ]),
                )
                Some(Array(next))
              }
            }
            String("pop_min") =>
              if items.is_empty() {
                if op.output == record([("empty", Bool(true))]) {
                  Some(state)
                } else {
                  None
                }
              } else {
                let mut best = 0
                for i in 1..<items.length() {
                  let best_priority = match field(items[best], "priority") {
                    Number(n) => n
                    _ => 0.0
                  }
                  let this = match field(items[i], "priority") {
                    Number(n) => n
                    _ => 0.0
                  }
                  if this < best_priority {
                    best = i
                  }
                }
                let value = field(items[best], "value")
                if op.output != record([("value", value)]) {
                  None
                } else {
                  let next : Array[Value] = []
                  for i in 0..<items.length() {
                    if i != best {
                      next.push(items[i])
                    }
                  }
                  Some(Array(next))
                }
              }
            _ => None
          }
        _ => None
      }
    PNCounter =>
      match state {
        Object(sets) =>
          match (sets.get("p"), sets.get("n")) {
            (Some(Object(p)), Some(Object(n))) => {
              let who = match field(op.input, "who") {
                String(name) => name
                _ => ""
              }
              match field(op.input, "type") {
                String("increment") => {
                  let by = match field(op.input, "by") {
                    Number(v) => v
                    _ => -1.0
                  }
                  if op.output != String("ok") || by < 1.0 {
                    None
                  } else {
                    let current = match p.get(who) {
                      Some(Number(v)) => v
                      _ => 0.0
                    }
                    let next_p = p.copy()
                    next_p[who] = Number(current + by)
                    Some(record([("p", Object(next_p)), ("n", Object(n))]))
                  }
                }
                String("decrement") => {
                  let by = match field(op.input, "by") {
                    Number(v) => v
                    _ => -1.0
                  }
                  if op.output != String("ok") || by < 1.0 {
                    None
                  } else {
                    let current = match n.get(who) {
                      Some(Number(v)) => v
                      _ => 0.0
                    }
                    let next_n = n.copy()
                    next_n[who] = Number(current + by)
                    Some(record([("p", Object(p)), ("n", Object(next_n))]))
                  }
                }
                String("read") => {
                  let mut total = 0.0
                  for _, v in p {
                    match v {
                      Number(x) => total += x
                      _ => ()
                    }
                  }
                  for _, v in n {
                    match v {
                      Number(x) => total -= x
                      _ => ()
                    }
                  }
                  if op.output == Number(total) {
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
    LwwMap =>
      match state {
        Object(entries) =>
          match field(op.input, "type") {
            // set is "ok" regardless of the timestamp, but only a strictly
            // newer at moves the entry: a dominated write leaves the entry
            // (and the observed ok) intact.
            String("set") => {
              let at = match field(op.input, "at") {
                Number(n) => n
                _ => -1.0
              }
              let key = match field(op.input, "key") {
                String(k) => k
                _ => ""
              }
              if op.output != String("ok") || key == "" || at < 0.0 {
                None
              } else {
                let dominated = match entries.get(key) {
                  Some(existing) =>
                    match field(existing, "at") {
                      Number(current) => at <= current
                      _ => false
                    }
                  None => false
                }
                if dominated {
                  Some(state)
                } else {
                  let next = entries.copy()
                  next[key] = record([
                    ("value", field(op.input, "value")),
                    ("at", Number(at)),
                  ])
                  Some(Object(next))
                }
              }
            }
            String("get") => {
              let key = match field(op.input, "key") {
                String(k) => k
                _ => ""
              }
              let want = match entries.get(key) {
                Some(entry) => field(entry, "value")
                None => Null
              }
              if op.output == want {
                Some(state)
              } else {
                None
              }
            }
            _ => None
          }
        _ => None
      }
    OrSet =>
      match state {
        Object(sets) =>
          match (sets.get("adds"), sets.get("removes")) {
            (Some(Array(adds)), Some(Array(removes))) => {
              let target = field(op.input, "value")
              let tag = field(op.input, "tag")
              // Every add carries a unique tag; a remove names the tag it
              // observed. The element is present iff it has a tag not in
              // the removes set (add-wins per tag).
              let tagged = adds.any(fn(entry) {
                field(entry, "value") == target && field(entry, "tag") == tag
              })
              let tombstoned = removes.contains(tag)
              match field(op.input, "type") {
                String("add") =>
                  if op.output != String("ok") {
                    None
                  } else {
                    let next_adds = adds.copy()
                    next_adds.push(record([("value", target), ("tag", tag)]))
                    Some(
                      record([
                        ("adds", Array(next_adds)),
                        ("removes", Array(removes)),
                      ]),
                    )
                  }
                String("remove") => {
                  let present = tagged && !tombstoned
                  if op.output != Bool(present) {
                    None
                  } else if tagged && !tombstoned {
                    let next_removes = removes.copy()
                    next_removes.push(tag)
                    Some(
                      record([
                        ("adds", Array(adds)),
                        ("removes", Array(next_removes)),
                      ]),
                    )
                  } else {
                    Some(state)
                  }
                }
                String("contains") => {
                  // Present iff any tag for this value is not tombstoned.
                  let present = adds.any(fn(entry) {
                    field(entry, "value") == target &&
                    !removes.contains(field(entry, "tag"))
                  })
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
    Flag =>
      match (state, field(op.input, "type")) {
        // One-way: set moves false to true and is idempotent; read observes.
        (Bool(_), String("set")) =>
          if op.output == String("ok") {
            Some(Bool(true))
          } else {
            None
          }
        (Bool(current), String("read")) =>
          if op.output == Bool(current) {
            Some(state)
          } else {
            None
          }
        _ => None
      }
    TicketLock =>
      match (state, field(op.input, "type")) {
        // Ticket lock: state is the currently-held ticket number (or
        // -1 for free). Acquire(n) succeeds only when free or when n is
        // the next ticket (n == held + 1); release(n) succeeds only
        // from the holder.
        (Number(held), String("acquire")) => {
          let ticket = match field(op.input, "ticket") {
            Number(t) => t
            _ => -999.0
          }
          if op.output == String("ok") {
            if held < 0.0 || ticket == held + 1.0 {
              Some(Number(ticket))
            } else {
              None
            }
          } else if op.output == String("blocked") {
            // Blocked acquire leaves state unchanged.
            Some(state)
          } else {
            None
          }
        }
        (Number(held), String("release")) => {
          let ticket = match field(op.input, "ticket") {
            Number(t) => t
            _ => -999.0
          }
          if op.output == String("ok") && ticket == held {
            Some(Number(-1.0))
          } else {
            None
          }
        }
        _ => None
      }
    Barrier =>
      match (state, field(op.input, "type")) {
        // A closed barrier blocks every waiter: a completed wait can only
        // linearize once the barrier has opened.
        (Bool(opened), String("wait")) =>
          if opened && op.output == String("ok") {
            Some(state)
          } else {
            None
          }
        // Opening is idempotent: an already-open barrier stays open.
        (Bool(_), String("open")) =>
          if op.output == String("ok") {
            Some(Bool(true))
          } else {
            None
          }
        _ => None
      }
    VersionedRegister =>
      match (state, field(op.input, "type")) {
        // Each write claims the next version and reports it; the version
        // sequence is the observable proof that writes serialized.
        (Object(reg), String("write")) => {
          let version = match reg.get("version") {
            Some(Number(n)) => n
            _ => 0.0
          }
          let next = version + 1.0
          if op.output == Number(next) &&
            !next.is_nan() &&
            !next.is_inf() &&
            next <= 9007199254740991.0 {
            Some(
              record([
                ("value", field(op.input, "value")),
                ("version", Number(next)),
              ]),
            )
          } else {
            None
          }
        }
        (Object(reg), String("read")) => {
          let value = reg.get("value").unwrap_or(Null)
          let version = match reg.get("version") {
            Some(Number(n)) => n
            _ => 0.0
          }
          if op.output ==
            record([("value", value), ("version", Number(version))]) {
            Some(state)
          } else {
            None
          }
        }
        _ => None
      }
    RwRegister =>
      match field(op.input, "type") {
        // Reads are pure: any number of them may overlap. A write reports
        // the exact pre-state it replaced, so two writes can never both
        // observe the same pre-state - writer mutual exclusion made
        // observable in the outputs.
        String("read") => if op.output == state { Some(state) } else { None }
        String("write") =>
          if op.output == state {
            Some(field(op.input, "value"))
          } else {
            None
          }
        _ => None
      }
    SetOfSets =>
      match state {
        Array(sets) =>
          match field(op.input, "type") {
            // Membership and removal compare whole subsets with structural
            // equality: adding [1,2] twice keeps one copy.
            String("add_set") =>
              if op.output != String("ok") {
                None
              } else if sets.contains(field(op.input, "set")) {
                Some(state)
              } else {
                let next = sets.copy()
                next.push(field(op.input, "set"))
                Some(Array(next))
              }
            String("remove_set") => {
              let target = field(op.input, "set")
              if op.output != Bool(sets.contains(target)) {
                None
              } else if sets.contains(target) {
                let next : Array[Value] = []
                let mut skipped = false
                for item in sets {
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
            String("contains_set") =>
              if op.output == Bool(sets.contains(field(op.input, "set"))) {
                Some(state)
              } else {
                None
              }
            _ => None
          }
        _ => None
      }
    MultiPNCounter =>
      match state {
        Object(entries) =>
          match field(op.input, "type") {
            String("increment") | String("decrement") => {
              let key = match field(op.input, "key") {
                String(k) => k
                _ => ""
              }
              let who = match field(op.input, "who") {
                String(name) => name
                _ => ""
              }
              let by = match field(op.input, "by") {
                Number(v) => v
                _ => -1.0
              }
              if op.output != String("ok") || key == "" || who == "" || by < 1.0 {
                None
              } else {
                multi_pncounter_bump(
                  entries,
                  key,
                  who,
                  by,
                  field(op.input, "type") == String("increment"),
                )
              }
            }
            String("read") => {
              let key = match field(op.input, "key") {
                String(k) => k
                _ => ""
              }
              if key == "" {
                None
              } else {
                let (p, n) = multi_pncounter_tables(entries, key)
                let mut total = 0.0
                for _, v in p {
                  match v {
                    Number(x) => total += x
                    _ => ()
                  }
                }
                for _, v in n {
                  match v {
                    Number(x) => total -= x
                    _ => ()
                  }
                }
                if op.output == Number(total) {
                  Some(state)
                } else {
                  None
                }
              }
            }
            _ => None
          }
        _ => None
      }
  }
}
