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
