///|
test "kv_register missing key reads null and does not introduce it" {
  let history = parse_history({
    "model": "kv_register",
    "initial": { "a": 0 },
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "read", "key": "nope" },
        "output": null,
      },
    ],
  })
  assert_eq(
    transition(KeyValue, history.initial, history.operations[0]),
    Some(history.initial),
  )
}

///|
test "queue enqueue null is distinct from empty" {
  let history = parse_history({
    "model": "queue",
    "initial": [],
    "operations": [
      {
        "id": "e",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "enqueue", "value": null },
        "output": "ok",
      },
      {
        "id": "d",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "dequeue" },
        "output": { "value": null },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Queue, state, op) {
      Some(next) => state = next
      None => abort("queue null replay failed")
    }
  }
  assert_eq(state, from_json([]))
}

///|
test "set add null is a real value" {
  let history = parse_history({
    "model": "set",
    "initial": [],
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": null },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "contains", "value": null },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Set, state, op) {
      Some(next) => state = next
      None => abort("set null replay failed")
    }
  }
  assert_eq(state, Array([Null]))
}

///|
test "lww_map per-key independence" {
  let history = parse_history({
    "model": "lww_map",
    "initial": {},
    "operations": [
      {
        "id": "s1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "set", "key": "x", "value": 1, "at": 5 },
        "output": "ok",
      },
      {
        "id": "s2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "set", "key": "y", "value": 2, "at": 3 },
        "output": "ok",
      },
      {
        "id": "g1",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "get", "key": "x" },
        "output": 1,
      },
      {
        "id": "g2",
        "client": "d",
        "call": 7,
        "return": 8,
        "input": { "type": "get", "key": "y" },
        "output": 2,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwMap, state, op) {
      Some(next) => state = next
      None => abort("lww map per-key replay failed")
    }
  }
  assert_eq(
    state,
    from_json({ "x": { "value": 1, "at": 5 }, "y": { "value": 2, "at": 3 } }),
  )
}

///|
test "semaphore zero permits is always exhausted" {
  let history = parse_history({
    "model": "semaphore",
    "initial": { "permits": 0, "taken": 0 },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire" },
        "output": false,
      },
    ],
  })
  assert_eq(
    transition(Semaphore, history.initial, history.operations[0]),
    Some(history.initial),
  )
}
