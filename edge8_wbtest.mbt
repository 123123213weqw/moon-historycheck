///|
test "lww_map per-key dominated writes are independent" {
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
        "id": "s3",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "set", "key": "x", "value": 3, "at": 3 },
        "output": "ok",
      },
      {
        "id": "g1",
        "client": "d",
        "call": 7,
        "return": 8,
        "input": { "type": "get", "key": "x" },
        "output": 1,
      },
      {
        "id": "g2",
        "client": "e",
        "call": 9,
        "return": 10,
        "input": { "type": "get", "key": "y" },
        "output": 2,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwMap, state, op) {
      Some(next) => state = next
      None => abort("lww map per-key dominated replay failed")
    }
  }
  assert_eq(
    state,
    from_json({ "x": { "value": 1, "at": 5 }, "y": { "value": 2, "at": 3 } }),
  )
}

///|
test "pncounter per-actor tables are independent" {
  let history = parse_history({
    "model": "pncounter",
    "initial": { "p": {}, "n": {} },
    "operations": [
      {
        "id": "ia",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment", "who": "a", "by": 5 },
        "output": "ok",
      },
      {
        "id": "ib",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "increment", "who": "b", "by": 3 },
        "output": "ok",
      },
      {
        "id": "db",
        "client": "b",
        "call": 5,
        "return": 6,
        "input": { "type": "decrement", "who": "b", "by": 2 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "c",
        "call": 7,
        "return": 8,
        "input": { "type": "read" },
        "output": 6,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(PNCounter, state, op) {
      Some(next) => state = next
      None => abort("pncounter per-actor replay failed")
    }
  }
  assert_eq(state, from_json({ "p": { "a": 5, "b": 3 }, "n": { "b": 2 } }))
}

///|
test "priority_queue same priority FIFO order" {
  let history = parse_history({
    "model": "priority_queue",
    "initial": [],
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push", "value": "first", "priority": 1 },
        "output": "ok",
      },
      {
        "id": "b",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "push", "value": "second", "priority": 1 },
        "output": "ok",
      },
      {
        "id": "p1",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "pop_min" },
        "output": { "value": "first" },
      },
      {
        "id": "p2",
        "client": "c",
        "call": 7,
        "return": 8,
        "input": { "type": "pop_min" },
        "output": { "value": "second" },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(PriorityQueue, state, op) {
      Some(next) => state = next
      None => abort("priority queue same-priority replay failed")
    }
  }
  assert_eq(state, from_json([]))
}
