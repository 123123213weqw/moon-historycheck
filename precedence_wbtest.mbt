///|
test "overlapping operations have no invented call-order edge" {
  let h = parse_history({
    "model": "register",
    "initial": 0,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 4,
        "input": { "type": "write", "value": 1 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 2,
        "return": 3,
        "input": { "type": "read" },
        "output": 0,
      },
    ],
  })
  let p = predecessors(h)
  assert_true(p[0].is_empty() && p[1].is_empty())
  assert_eq(field(analyze_history(h), "max_in_flight"), Number(2))
}

///|
test "completed-before-call gives a mandatory predecessor" {
  let h = parse_history({
    "model": "register",
    "initial": 0,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 1 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "read" },
        "output": 0,
      },
    ],
  })
  assert_eq(predecessors(h), [[], [0]])
}
