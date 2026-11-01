///|
test "bounded queue overflow then dequeue then overflow again" {
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
        "id": "d",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "dequeue" },
        "output": { "value": 1 },
      },
      {
        "id": "e5",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "enqueue", "value": 4 },
        "output": "ok",
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(BoundedQueue, state, op) {
      Some(next) => state = next
      None => abort("bounded queue overflow cycle failed")
    }
  }
  assert_eq(state, from_json([2, 3, 4]))
}

///|
test "deque empty pop on both ends observes empty" {
  for kind in ["pop_front", "pop_back"] {
    let history = parse_history({
      "model": "deque",
      "initial": [],
      "operations": [
        {
          "id": "p",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": kind },
          "output": { "empty": true },
        },
      ],
    })
    assert_eq(
      transition(Deque, history.initial, history.operations[0]),
      Some(Array([])),
    )
  }
}

///|
test "rwlock interleaved reader-writer cycles" {
  let history = parse_history({
    "model": "rwlock",
    "initial": { "readers": 0, "writer": false },
    "operations": [
      {
        "id": "r1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire_read" },
        "output": true,
      },
      {
        "id": "rr1",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "release_read" },
        "output": "ok",
      },
      {
        "id": "w",
        "client": "b",
        "call": 5,
        "return": 6,
        "input": { "type": "acquire_write" },
        "output": true,
      },
      {
        "id": "r2",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "acquire_read" },
        "output": false,
      },
      {
        "id": "rw",
        "client": "b",
        "call": 9,
        "return": 10,
        "input": { "type": "release_write" },
        "output": "ok",
      },
      {
        "id": "r3",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "acquire_read" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(RwLock, state, op) {
      Some(next) => state = next
      None => abort("rwlock cycle failed")
    }
  }
  assert_eq(state, from_json({ "readers": 1, "writer": false }))
}

///|
test "pncounter zero total reads as zero" {
  let history = parse_history({
    "model": "pncounter",
    "initial": { "p": {}, "n": {} },
    "operations": [
      {
        "id": "i",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment", "who": "a", "by": 3 },
        "output": "ok",
      },
      {
        "id": "d",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "decrement", "who": "a", "by": 3 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 5,
        "return": 6,
        "input": { "type": "read" },
        "output": 0,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(PNCounter, state, op) {
      Some(next) => state = next
      None => abort("pncounter zero replay failed")
    }
  }
  assert_eq(state, from_json({ "p": { "a": 3 }, "n": { "a": 3 } }))
}
