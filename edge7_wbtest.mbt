///|
test "lww_set dominated add then remove" {
  let history = parse_history({
    "model": "lww_set",
    "initial": { "adds": {}, "rems": {} },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "element": "e", "at": 7 },
        "output": "ok",
      },
      {
        "id": "a2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "add", "element": "e", "at": 3 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "b",
        "call": 5,
        "return": 6,
        "input": { "type": "contains", "element": "e" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwSet, state, op) {
      Some(next) => state = next
      None => abort("lww dominated add replay failed")
    }
  }
  assert_eq(state, from_json({ "adds": { "e": 7 }, "rems": {} }))
}

///|
test "two_phase_set add-remove-add-contains is always false" {
  let history = parse_history({
    "model": "two_phase_set",
    "initial": { "added": [], "removed": [] },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": 1 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "remove", "value": 1 },
        "output": true,
      },
      {
        "id": "a2",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "add", "value": 1 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "contains", "value": 1 },
        "output": false,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(TwoPhaseSet, state, op) {
      Some(next) => state = next
      None => abort("two-phase cycle replay failed")
    }
  }
  assert_eq(state, from_json({ "added": [1], "removed": [1] }))
}

///|
test "deque push_back pop_back is a reverse stack" {
  let history = parse_history({
    "model": "deque",
    "initial": [],
    "operations": [
      {
        "id": "pb1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push_back", "value": 1 },
        "output": "ok",
      },
      {
        "id": "pb2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "push_back", "value": 2 },
        "output": "ok",
      },
      {
        "id": "pb3",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "push_back", "value": 3 },
        "output": "ok",
      },
      {
        "id": "pb4",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "pop_back" },
        "output": { "value": 3 },
      },
      {
        "id": "pb5",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "pop_back" },
        "output": { "value": 2 },
      },
      {
        "id": "pb6",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "pop_back" },
        "output": { "value": 1 },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Deque, state, op) {
      Some(next) => state = next
      None => abort("deque reverse stack replay failed")
    }
  }
  assert_eq(state, from_json([]))
}

///|
test "bounded queue FIFO order with overflow in the middle" {
  let history = parse_history({
    "model": "bounded_queue",
    "initial": [],
    "operations": [
      {
        "id": "e1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "enqueue", "value": 1 },
        "output": "ok",
      },
      {
        "id": "e2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "enqueue", "value": 2 },
        "output": "ok",
      },
      {
        "id": "e3",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "enqueue", "value": 3 },
        "output": "ok",
      },
      {
        "id": "e4",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "enqueue", "value": 4 },
        "output": false,
      },
      {
        "id": "d1",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "dequeue" },
        "output": { "value": 1 },
      },
      {
        "id": "d2",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "dequeue" },
        "output": { "value": 2 },
      },
      {
        "id": "d3",
        "client": "a",
        "call": 13,
        "return": 14,
        "input": { "type": "dequeue" },
        "output": { "value": 3 },
      },
      {
        "id": "d4",
        "client": "a",
        "call": 15,
        "return": 16,
        "input": { "type": "dequeue" },
        "output": { "empty": true },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(BoundedQueue, state, op) {
      Some(next) => state = next
      None => abort("bounded queue FIFO cycle failed")
    }
  }
  assert_eq(state, from_json([]))
}
