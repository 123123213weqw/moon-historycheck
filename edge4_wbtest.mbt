///|
test "lww map dominated write leaves entry intact but acknowledges" {
  let history = parse_history({
    "model": "lww_map",
    "initial": { "k": { "value": 2, "at": 9 } },
    "operations": [
      {
        "id": "s",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "set", "key": "k", "value": 3, "at": 7 },
        "output": "ok",
      },
      {
        "id": "g",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "get", "key": "k" },
        "output": 2,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwMap, state, op) {
      Some(next) => state = next
      None => abort("lww map dominated write failed")
    }
  }
  assert_eq(state, from_json({ "k": { "value": 2, "at": 9 } }))
}

///|
test "pncounter with a single actor is equivalent to a signed counter" {
  let history = parse_history({
    "model": "pncounter",
    "initial": { "p": {}, "n": {} },
    "operations": [
      {
        "id": "i1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment", "who": "a", "by": 5 },
        "output": "ok",
      },
      {
        "id": "i2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "increment", "who": "a", "by": 3 },
        "output": "ok",
      },
      {
        "id": "d",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "decrement", "who": "a", "by": 4 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 7,
        "return": 8,
        "input": { "type": "read" },
        "output": 4,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(PNCounter, state, op) {
      Some(next) => state = next
      None => abort("pncounter single-actor replay failed")
    }
  }
  assert_eq(state, from_json({ "p": { "a": 8 }, "n": { "a": 4 } }))
}

///|
test "priority queue with equal priorities pops in insertion order" {
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
        "client": "a",
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
      None => abort("priority queue tie replay failed")
    }
  }
  assert_eq(state, from_json([]))
}

///|
test "deque push_front and pop_front is a stack" {
  let history = parse_history({
    "model": "deque",
    "initial": [],
    "operations": [
      {
        "id": "pf1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push_front", "value": 1 },
        "output": "ok",
      },
      {
        "id": "pf2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "push_front", "value": 2 },
        "output": "ok",
      },
      {
        "id": "pf3",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "push_front", "value": 3 },
        "output": "ok",
      },
      {
        "id": "pf4",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "pop_front" },
        "output": { "value": 3 },
      },
      {
        "id": "pf5",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "pop_front" },
        "output": { "value": 2 },
      },
      {
        "id": "pf6",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "pop_front" },
        "output": { "value": 1 },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Deque, state, op) {
      Some(next) => state = next
      None => abort("deque stack replay failed")
    }
  }
  assert_eq(state, from_json([]))
}
