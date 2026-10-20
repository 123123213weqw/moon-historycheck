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
