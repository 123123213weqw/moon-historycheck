///|
test "CAS success and failure validate observed result and preserve state" {
  assert_eq(
    register_transition(
      Number(1),
      from_json({ "type": "cas", "expected": 1, "value": 2 }),
      Bool(true),
    ),
    Some(Number(2)),
  )
  assert_eq(
    register_transition(
      Number(1),
      from_json({ "type": "cas", "expected": 0, "value": 2 }),
      Bool(false),
    ),
    Some(Number(1)),
  )
  assert_eq(
    register_transition(
      Number(1),
      from_json({ "type": "cas", "expected": 0, "value": 2 }),
      Bool(true),
    ),
    None,
  )
}

///|
test "FIFO empty result is distinct from enqueued null" {
  let history = parse_history({
    "model": "queue",
    "initial": [null],
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "dequeue" },
        "output": { "value": null },
      },
    ],
  })
  assert_eq(
    transition(Queue, history.initial, history.operations[0]),
    Some(Array([])),
  )
  assert_eq(transition(Queue, Array([]), history.operations[0]), None)
}

///|
test "stack pops the most recent push first" {
  let history = parse_history({
    "model": "stack",
    "initial": [],
    "operations": [
      {
        "id": "p1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push", "value": 1 },
        "output": "ok",
      },
      {
        "id": "p2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "push", "value": 2 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Stack, history.initial, history.operations[1]),
    Some(Array([Number(2)])),
  )
  let pop_history = parse_history({
    "model": "stack",
    "initial": [1, 2],
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop" },
        "output": { "value": 2 },
      },
    ],
  })
  assert_eq(
    transition(Stack, pop_history.initial, pop_history.operations[0]),
    Some(Array([Number(1)])),
  )
  assert_eq(transition(Stack, Array([]), pop_history.operations[0]), None)
}

///|
test "lock acquire reports the holder and release requires holding" {
  let acquire = parse_history({
    "model": "lock",
    "initial": false,
    "operations": [
      {
        "id": "a",
        "client": "ca",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(Lock, acquire.initial, acquire.operations[0]),
    Some(Bool(true)),
  )
  assert_eq(transition(Lock, Bool(true), acquire.operations[0]), None)
  let denied = parse_history({
    "model": "lock",
    "initial": true,
    "operations": [
      {
        "id": "a",
        "client": "ca",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire" },
        "output": false,
      },
    ],
  })
  assert_eq(
    transition(Lock, denied.initial, denied.operations[0]),
    Some(Bool(true)),
  )
  let release = parse_history({
    "model": "lock",
    "initial": true,
    "operations": [
      {
        "id": "r",
        "client": "cr",
        "call": 1,
        "return": 2,
        "input": { "type": "release" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Lock, release.initial, release.operations[0]),
    Some(Bool(false)),
  )
  assert_eq(transition(Lock, Bool(false), release.operations[0]), None)
}

///|
test "set membership and removal use structural equality" {
  let add = parse_history({
    "model": "set",
    "initial": [1],
    "operations": [
      {
        "id": "a",
        "client": "ca",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": 1 },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(Set, add.initial, add.operations[0]), Some(add.initial))
  let add_true = parse_history({
    "model": "set",
    "initial": [1],
    "operations": [
      {
        "id": "a",
        "client": "ca",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": true },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Set, add_true.initial, add_true.operations[0]),
    Some(Array([Number(1), Bool(true)])),
  )
  let remove = parse_history({
    "model": "set",
    "initial": [1, true],
    "operations": [
      {
        "id": "r",
        "client": "cr",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": true },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(Set, remove.initial, remove.operations[0]),
    Some(Array([Number(1)])),
  )
  assert_eq(transition(Set, Array([]), remove.operations[0]), None)
  let contains = parse_history({
    "model": "set",
    "initial": [1],
    "operations": [
      {
        "id": "c",
        "client": "cc",
        "call": 1,
        "return": 2,
        "input": { "type": "contains", "value": true },
        "output": true,
      },
    ],
  })
  assert_eq(transition(Set, contains.initial, contains.operations[0]), None)
}

///|
test "key updates do not mutate other branches" {
  let history = parse_history({
    "model": "kv_register",
    "initial": { "a": 0 },
    "operations": [
      {
        "id": "w",
        "client": "c",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "key": "a", "value": 2 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(KeyValue, history.initial, history.operations[0]),
    Some(from_json({ "a": 2 })),
  )
  assert_eq(history.initial, from_json({ "a": 0 }))
}

///|
test "counter increments decrements and reads exactly" {
  let increment = parse_history({
    "model": "counter",
    "initial": 5,
    "operations": [
      {
        "id": "i",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Counter, increment.initial, increment.operations[0]),
    Some(Number(6)),
  )
  let decrement = parse_history({
    "model": "counter",
    "initial": 5,
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "decrement" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Counter, decrement.initial, decrement.operations[0]),
    Some(Number(4)),
  )
  let read = parse_history({
    "model": "counter",
    "initial": 5,
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "read" },
        "output": 5,
      },
    ],
  })
  assert_eq(
    transition(Counter, read.initial, read.operations[0]),
    Some(Number(5)),
  )
  // An increment whose observed output is not "ok" cannot replay anywhere.
  let misreported = parse_history({
    "model": "counter",
    "initial": 5,
    "operations": [
      {
        "id": "i",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment" },
        "output": "wrong",
      },
    ],
  })
  assert_eq(
    transition(Counter, misreported.initial, misreported.operations[0]),
    None,
  )
}

///|
test "map puts gets and removes keys with membership outputs" {
  let put = parse_history({
    "model": "map",
    "initial": {},
    "operations": [
      {
        "id": "p",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "put", "key": "k", "value": 1 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Mapping, put.initial, put.operations[0]),
    Some(from_json({ "k": 1 })),
  )
  let get = parse_history({
    "model": "map",
    "initial": { "k": 1 },
    "operations": [
      {
        "id": "g",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "get", "key": "k" },
        "output": 1,
      },
    ],
  })
  assert_eq(
    transition(Mapping, get.initial, get.operations[0]),
    Some(from_json({ "k": 1 })),
  )
  let missing = parse_history({
    "model": "map",
    "initial": {},
    "operations": [
      {
        "id": "g",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "get", "key": "k" },
        "output": null,
      },
    ],
  })
  assert_eq(
    transition(Mapping, missing.initial, missing.operations[0]),
    Some(from_json({})),
  )
  let remove = parse_history({
    "model": "map",
    "initial": { "k": 1 },
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "key": "k" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(Mapping, remove.initial, remove.operations[0]),
    Some(from_json({})),
  )
  let absent = parse_history({
    "model": "map",
    "initial": { "k": 1 },
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "key": "x" },
        "output": false,
      },
    ],
  })
  assert_eq(
    transition(Mapping, absent.initial, absent.operations[0]),
    Some(from_json({ "k": 1 })),
  )
  // A get observing a stale value is rejected.
  assert_eq(transition(Mapping, absent.initial, missing.operations[0]), None)
}

///|
test "lww set resolves ties add-wins and honors later removes" {
  let tie = parse_history({
    "model": "lww_set",
    "initial": { "adds": {}, "rems": {} },
    "operations": [
      {
        "id": "a",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "element": "e", "at": 5 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "y",
        "call": 3,
        "return": 4,
        "input": { "type": "remove", "element": "e", "at": 5 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "z",
        "call": 5,
        "return": 6,
        "input": { "type": "contains", "element": "e" },
        "output": true,
      },
    ],
  })
  let mut state = tie.initial
  for op in tie.operations {
    match transition(LwwSet, state, op) {
      Some(next) => state = next
      None => abort("lww tie replay failed")
    }
  }
  assert_eq(state, from_json({ "adds": { "e": 5 }, "rems": { "e": 5 } }))
  let later_remove = parse_history({
    "model": "lww_set",
    "initial": { "adds": { "e": 3 }, "rems": {} },
    "operations": [
      {
        "id": "r",
        "client": "y",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "element": "e", "at": 7 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "z",
        "call": 3,
        "return": 4,
        "input": { "type": "contains", "element": "e" },
        "output": false,
      },
    ],
  })
  let mut second = later_remove.initial
  for op in later_remove.operations {
    match transition(LwwSet, second, op) {
      Some(next) => second = next
      None => abort("lww remove replay failed")
    }
  }
  assert_eq(second, from_json({ "adds": { "e": 3 }, "rems": { "e": 7 } }))
  // An older duplicate add does not regress the recorded timestamp.
  let older = parse_history({
    "model": "lww_set",
    "initial": { "adds": { "e": 5 }, "rems": {} },
    "operations": [
      {
        "id": "a",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "element": "e", "at": 3 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(LwwSet, older.initial, older.operations[0]),
    Some(older.initial),
  )
}

///|
test "grow-only set adds idempotently and never removes" {
  let add = parse_history({
    "model": "grow_only_set",
    "initial": [],
    "operations": [
      {
        "id": "a",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": "e" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(GrowSet, add.initial, add.operations[0]),
    Some(Array([String("e")])),
  )
  let again = parse_history({
    "model": "grow_only_set",
    "initial": ["e"],
    "operations": [
      {
        "id": "a",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": "e" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(GrowSet, again.initial, again.operations[0]),
    Some(Array([String("e")])),
  )
  let contains = parse_history({
    "model": "grow_only_set",
    "initial": ["e"],
    "operations": [
      {
        "id": "c",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "contains", "value": "e" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(GrowSet, contains.initial, contains.operations[0]),
    Some(Array([String("e")])),
  )
  let absent = parse_history({
    "model": "grow_only_set",
    "initial": [],
    "operations": [
      {
        "id": "c",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "contains", "value": "e" },
        "output": true,
      },
    ],
  })
  assert_eq(transition(GrowSet, absent.initial, absent.operations[0]), None)
}

///|
test "two-phase set never resurrects a removed element" {
  let remove = parse_history({
    "model": "two_phase_set",
    "initial": { "added": ["e"], "removed": [] },
    "operations": [
      {
        "id": "r",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": "e" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(TwoPhaseSet, remove.initial, remove.operations[0]),
    Some(from_json({ "added": ["e"], "removed": ["e"] })),
  )
  let readd = parse_history({
    "model": "two_phase_set",
    "initial": { "added": ["e"], "removed": ["e"] },
    "operations": [
      {
        "id": "a",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": "e" },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "x",
        "call": 3,
        "return": 4,
        "input": { "type": "contains", "value": "e" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(TwoPhaseSet, readd.initial, readd.operations[0]),
    Some(readd.initial),
  )
  assert_eq(transition(TwoPhaseSet, readd.initial, readd.operations[1]), None)
  let absent_remove = parse_history({
    "model": "two_phase_set",
    "initial": { "added": [], "removed": [] },
    "operations": [
      {
        "id": "r",
        "client": "x",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": "e" },
        "output": true,
      },
    ],
  })
  assert_eq(
    transition(TwoPhaseSet, absent_remove.initial, absent_remove.operations[0]),
    None,
  )
}

///|
test "min register refuses to move upwards" {
  let grow = parse_history({
    "model": "min_register",
    "initial": 7,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 3 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(MinRegister, grow.initial, grow.operations[0]),
    Some(Number(3)),
  )
  let rise = parse_history({
    "model": "min_register",
    "initial": 3,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 9 },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(MinRegister, rise.initial, rise.operations[0]), None)
}

///|
test "lww register keeps the strictly newest write" {
  let newer = parse_history({
    "model": "lww_register",
    "initial": null,
    "operations": [
      {
        "id": "w1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 1, "at": 5 },
        "output": "ok",
      },
      {
        "id": "w2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "write", "value": 2, "at": 7 },
        "output": "ok",
      },
    ],
  })
  let mut state = newer.initial
  for op in newer.operations {
    match transition(LwwRegister, state, op) {
      Some(next) => state = next
      None => abort("lww register replay failed")
    }
  }
  assert_eq(state, from_json({ "value": 2, "at": 7 }))
  let stale = parse_history({
    "model": "lww_register",
    "initial": { "value": 2, "at": 7 },
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 9, "at": 7 },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(LwwRegister, stale.initial, stale.operations[0]), None)
  let read = parse_history({
    "model": "lww_register",
    "initial": null,
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "read" },
        "output": null,
      },
    ],
  })
  assert_eq(
    transition(LwwRegister, read.initial, read.operations[0]),
    Some(Null),
  )
}

///|
test "bounded queue refuses when full and admits after dequeue" {
  let full = parse_history({
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
    ],
  })
  let mut state = full.initial
  for op in full.operations {
    match transition(BoundedQueue, state, op) {
      Some(next) => state = next
      None => abort("bounded queue replay failed")
    }
  }
  assert_eq(state, from_json([1, 2, 3]))
  let dequeue = parse_history({
    "model": "bounded_queue",
    "initial": [1, 2, 3],
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "dequeue" },
        "output": { "value": 1 },
      },
    ],
  })
  assert_eq(
    transition(BoundedQueue, dequeue.initial, dequeue.operations[0]),
    Some(Array([Number(2), Number(3)])),
  )
}

///|
test "deque pushes and pops at both ends" {
  let history = parse_history({
    "model": "deque",
    "initial": [],
    "operations": [
      {
        "id": "b",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push_back", "value": 1 },
        "output": "ok",
      },
      {
        "id": "f",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "push_front", "value": 2 },
        "output": "ok",
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Deque, state, op) {
      Some(next) => state = next
      None => abort("deque push replay failed")
    }
  }
  assert_eq(state, from_json([2, 1]))
  let front = parse_history({
    "model": "deque",
    "initial": [2, 1],
    "operations": [
      {
        "id": "pf",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop_front" },
        "output": { "value": 2 },
      },
    ],
  })
  assert_eq(
    transition(Deque, front.initial, front.operations[0]),
    Some(Array([Number(1)])),
  )
  let back = parse_history({
    "model": "deque",
    "initial": [1],
    "operations": [
      {
        "id": "pb",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop_back" },
        "output": { "value": 1 },
      },
    ],
  })
  assert_eq(
    transition(Deque, back.initial, back.operations[0]),
    Some(Array([])),
  )
}

///|
test "semaphore admits up to its permits and reports exhaustion" {
  let history = parse_history({
    "model": "semaphore",
    "initial": { "permits": 2, "taken": 0 },
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire" },
        "output": true,
      },
      {
        "id": "a2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "acquire" },
        "output": true,
      },
      {
        "id": "a3",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "acquire" },
        "output": false,
      },
      {
        "id": "r",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "release" },
        "output": "ok",
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Semaphore, state, op) {
      Some(next) => state = next
      None => abort("semaphore replay failed")
    }
  }
  assert_eq(state, from_json({ "permits": 2, "taken": 1 }))
  // Releasing without holding cannot replay.
  let empty = parse_history({
    "model": "semaphore",
    "initial": { "permits": 2, "taken": 0 },
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "release" },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(Semaphore, empty.initial, empty.operations[0]), None)
}

///|
test "rwlock admits many readers or one writer, never both" {
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
        "id": "r2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "acquire_read" },
        "output": true,
      },
      {
        "id": "w",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "acquire_write" },
        "output": false,
      },
      {
        "id": "rr1",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "release_read" },
        "output": "ok",
      },
      {
        "id": "rr2",
        "client": "b",
        "call": 9,
        "return": 10,
        "input": { "type": "release_read" },
        "output": "ok",
      },
      {
        "id": "w2",
        "client": "c",
        "call": 11,
        "return": 12,
        "input": { "type": "acquire_write" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(RwLock, state, op) {
      Some(next) => state = next
      None => abort("rwlock replay failed")
    }
  }
  assert_eq(state, from_json({ "readers": 0, "writer": true }))
  // A reader cannot release what it does not hold.
  let phantom = parse_history({
    "model": "rwlock",
    "initial": { "readers": 0, "writer": false },
    "operations": [
      {
        "id": "rr",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "release_read" },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(RwLock, phantom.initial, phantom.operations[0]), None)
}

///|
test "multiset counts duplicates and removes exactly one" {
  let add = parse_history({
    "model": "multiset",
    "initial": [],
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": 5 },
        "output": "ok",
      },
      {
        "id": "a2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "add", "value": 5 },
        "output": "ok",
      },
    ],
  })
  let mut state = add.initial
  for op in add.operations {
    match transition(MultiSet, state, op) {
      Some(next) => state = next
      None => abort("multiset add replay failed")
    }
  }
  assert_eq(state, from_json([5, 5]))
  let count = parse_history({
    "model": "multiset",
    "initial": [5, 5],
    "operations": [
      {
        "id": "c",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "count", "value": 5 },
        "output": 2,
      },
    ],
  })
  assert_eq(
    transition(MultiSet, count.initial, count.operations[0]),
    Some(Array([Number(5), Number(5)])),
  )
  let remove = parse_history({
    "model": "multiset",
    "initial": [5, 5],
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": 5 },
        "output": 2,
      },
    ],
  })
  assert_eq(
    transition(MultiSet, remove.initial, remove.operations[0]),
    Some(Array([Number(5)])),
  )
  let remove0 = parse_history({
    "model": "multiset",
    "initial": [],
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": 5 },
        "output": 0,
      },
    ],
  })
  assert_eq(
    transition(MultiSet, remove0.initial, remove0.operations[0]),
    Some(Array([])),
  )
}

///|
test "priority queue pops the smallest priority, first among ties" {
  let history = parse_history({
    "model": "priority_queue",
    "initial": [],
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push", "value": "x", "priority": 2 },
        "output": "ok",
      },
      {
        "id": "b",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "push", "value": "y", "priority": 1 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "push", "value": "z", "priority": 2 },
        "output": "ok",
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(PriorityQueue, state, op) {
      Some(next) => state = next
      None => abort("priority queue push replay failed")
    }
  }
  let pop1 = parse_history({
    "model": "priority_queue",
    "initial": state.to_json(),
    "operations": [
      {
        "id": "p",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop_min" },
        "output": { "value": "y" },
      },
    ],
  })
  assert_eq(
    transition(PriorityQueue, pop1.initial, pop1.operations[0]),
    Some(
      from_json([
        { "value": "x", "priority": 2 },
        { "value": "z", "priority": 2 },
      ]),
    ),
  )
  let pop2 = parse_history({
    "model": "priority_queue",
    "initial": [
      { "value": "x", "priority": 2 },
      { "value": "z", "priority": 2 },
    ],
    "operations": [
      {
        "id": "p",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop_min" },
        "output": { "value": "x" },
      },
    ],
  })
  assert_eq(
    transition(PriorityQueue, pop2.initial, pop2.operations[0]),
    Some(from_json([{ "value": "z", "priority": 2 }])),
  )
  let empty = parse_history({
    "model": "priority_queue",
    "initial": [],
    "operations": [
      {
        "id": "p",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "pop_min" },
        "output": { "empty": true },
      },
    ],
  })
  assert_eq(
    transition(PriorityQueue, empty.initial, empty.operations[0]),
    Some(Array([])),
  )
}

///|
test "pncounter merges per-actor increments and decrements" {
  let history = parse_history({
    "model": "pncounter",
    "initial": { "p": {}, "n": {} },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "increment", "who": "a", "by": 2 },
        "output": "ok",
      },
      {
        "id": "b",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "increment", "who": "b", "by": 3 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "decrement", "who": "a", "by": 1 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "c",
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
      None => abort("pncounter replay failed")
    }
  }
  assert_eq(state, from_json({ "p": { "a": 2, "b": 3 }, "n": { "a": 1 } }))
}

///|
test "pncounter rejects zero steps at parse time" {
  let failed : Value = String(
    match
      parse_history({
        "model": "pncounter",
        "initial": { "p": {}, "n": {} },
        "operations": [
          {
            "id": "a",
            "client": "a",
            "call": 1,
            "input": { "type": "increment", "who": "a", "by": 0 },
          },
        ],
      }) {
      _ => "no error raised"
    },
  ) catch {
    HistoryError(message) => String(message)
  }
  assert_eq(failed, String("a: by must be at least 1"))
}

///|
test "lww map keeps the newest write per key and ignores dominated writes" {
  let history = parse_history({
    "model": "lww_map",
    "initial": {},
    "operations": [
      {
        "id": "s1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "set", "key": "k", "value": 1, "at": 5 },
        "output": "ok",
      },
      {
        "id": "s2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "set", "key": "k", "value": 2, "at": 9 },
        "output": "ok",
      },
      {
        "id": "s3",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "set", "key": "k", "value": 3, "at": 7 },
        "output": "ok",
      },
      {
        "id": "g",
        "client": "d",
        "call": 7,
        "return": 8,
        "input": { "type": "get", "key": "k" },
        "output": 2,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwMap, state, op) {
      Some(next) => state = next
      None => abort("lww map replay failed")
    }
  }
  // s3 (at 7) is dominated by s2 (at 9): the state keeps s2, and s3's ok is
  // still legal because the client did get an acknowledgement.
  assert_eq(state, from_json({ "k": { "value": 2, "at": 9 } }))
  let missing = parse_history({
    "model": "lww_map",
    "initial": {},
    "operations": [
      {
        "id": "g",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "get", "key": "nope" },
        "output": null,
      },
    ],
  })
  assert_eq(
    transition(LwwMap, missing.initial, missing.operations[0]),
    Some(Object(Map([]))),
  )
}

///|
test "or set add-wins per tag, remove tombstones the tag it saw" {
  let history = parse_history({
    "model": "or_set",
    "initial": { "adds": [], "removes": [] },
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": "x", "tag": "t1" },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "remove", "value": "x", "tag": "t1" },
        "output": true,
      },
      {
        "id": "c1",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "contains", "value": "x", "tag": "unused" },
        "output": false,
      },
      {
        "id": "a2",
        "client": "d",
        "call": 7,
        "return": 8,
        "input": { "type": "add", "value": "x", "tag": "t2" },
        "output": "ok",
      },
      {
        "id": "c2",
        "client": "e",
        "call": 9,
        "return": 10,
        "input": { "type": "contains", "value": "x", "tag": "unused" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(OrSet, state, op) {
      Some(next) => state = next
      None => abort("or set replay failed")
    }
  }
  assert_eq(
    state,
    from_json({
      "adds": [{ "value": "x", "tag": "t1" }, { "value": "x", "tag": "t2" }],
      "removes": ["t1"],
    }),
  )
}

///|
test "or set concurrent add-wins over a stale remove" {
  // A remove that did not observe this add tag cannot tombstone it.
  let history = parse_history({
    "model": "or_set",
    "initial": { "adds": [], "removes": [] },
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 4,
        "input": { "type": "add", "value": "x", "tag": "t1" },
        "output": "ok",
      },
      {
        "id": "r0",
        "client": "b",
        "call": 2,
        "return": 3,
        "input": { "type": "remove", "value": "x", "tag": "t0" },
        "output": false,
      },
      {
        "id": "c",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "contains", "value": "x", "tag": "unused" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(OrSet, state, op) {
      Some(next) => state = next
      None => abort("or set concurrent replay failed")
    }
  }
  assert_eq(
    state,
    from_json({ "adds": [{ "value": "x", "tag": "t1" }], "removes": [] }),
  )
}

///|
test "flag sets once and stays set" {
  let set = parse_history({
    "model": "flag",
    "initial": false,
    "operations": [
      {
        "id": "s",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "set" },
        "output": "ok",
      },
    ],
  })
  assert_eq(transition(Flag, set.initial, set.operations[0]), Some(Bool(true)))
  let again = parse_history({
    "model": "flag",
    "initial": true,
    "operations": [
      {
        "id": "s",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "set" },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(Flag, again.initial, again.operations[0]),
    Some(Bool(true)),
  )
  let read_true = parse_history({
    "model": "flag",
    "initial": true,
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "read" },
        "output": false,
      },
    ],
  })
  assert_eq(transition(Flag, read_true.initial, read_true.operations[0]), None)
}
