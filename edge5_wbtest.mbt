///|
test "lww set add-wins tie with three concurrent writers" {
  let history = parse_history({
    "model": "lww_set",
    "initial": { "adds": {}, "rems": {} },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "element": "e", "at": 5 },
        "output": "ok",
      },
      {
        "id": "r1",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "remove", "element": "e", "at": 5 },
        "output": "ok",
      },
      {
        "id": "r2",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "remove", "element": "e", "at": 3 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "d",
        "call": 7,
        "return": 8,
        "input": { "type": "contains", "element": "e" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwSet, state, op) {
      Some(next) => state = next
      None => abort("lww three-writer replay failed")
    }
  }
  assert_eq(state, from_json({ "adds": { "e": 5 }, "rems": { "e": 5 } }))
}

///|
test "two-phase set remove from empty reports false" {
  let history = parse_history({
    "model": "two_phase_set",
    "initial": { "added": [], "removed": [] },
    "operations": [
      {
        "id": "r",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "remove", "value": 1 },
        "output": false,
      },
    ],
  })
  assert_eq(
    transition(TwoPhaseSet, history.initial, history.operations[0]),
    Some(history.initial),
  )
}

///|
test "counter decrement below zero is verifiable" {
  let history = parse_history({
    "model": "counter",
    "initial": 0,
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "decrement" },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "read" },
        "output": -1,
      },
    ],
  })
  assert_eq(
    transition(Counter, history.initial, history.operations[0]),
    Some(Number(-1)),
  )
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
