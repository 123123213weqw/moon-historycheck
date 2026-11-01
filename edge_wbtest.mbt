///|
/// Boundary values that only show at the edges of the numeric contracts:
/// 2^53-1 (the largest exact double integer), 0, and negative extremes for
/// the monotonic models.
test "counter steps to the 2^53 boundary and stops replaying beyond it" {
  let history = parse_history({
    "model": "counter",
    "initial": 9007199254740990.0,
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
  // +1 lands exactly on 2^53-1, still exact.
  assert_eq(
    transition(Counter, history.initial, history.operations[0]),
    Some(Number(9007199254740991.0)),
  )
  // One more increment would leave the exact range: unverifiable, replaying
  // it as ok must fail.
  let beyond = parse_history({
    "model": "counter",
    "initial": 9007199254740991.0,
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
  assert_eq(transition(Counter, beyond.initial, beyond.operations[0]), None)
}

///|
test "max and min registers accept the extreme exact values" {
  let max_top = parse_history({
    "model": "max_register",
    "initial": 0,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 9007199254740991.0 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(MaxRegister, max_top.initial, max_top.operations[0]),
    Some(Number(9007199254740991.0)),
  )
  let min_floor = parse_history({
    "model": "min_register",
    "initial": 0,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": -9007199254740991.0 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(MinRegister, min_floor.initial, min_floor.operations[0]),
    Some(Number(-9007199254740991.0)),
  )
}

///|
test "lww register accepts timestamp zero as a real write" {
  let history = parse_history({
    "model": "lww_set",
    "initial": { "adds": {}, "rems": {} },
    "operations": [
      {
        "id": "a",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "element": "e", "at": 0 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "contains", "element": "e" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwSet, state, op) {
      Some(next) => state = next
      None => abort("timestamp-zero replay failed")
    }
  }
  assert_eq(state, from_json({ "adds": { "e": 0 }, "rems": {} }))
}

///|
test "overlapping intervals admit either order" {
  // The contract requires globally unique ordinals, so simultaneity is
  // expressed by overlap: both writes run inside [2, 5] and either order is
  // a legal linearization. Equal call ordinals are refused (pinned above in
  // the robustness sweep).
  assert_eq(
    field(
      from_json(
        execute({
          "model": "register",
          "initial": 0,
          "operations": [
            {
              "id": "w1",
              "client": "a",
              "call": 2,
              "return": 5,
              "input": { "type": "write", "value": 1 },
              "output": "ok",
            },
            {
              "id": "w2",
              "client": "b",
              "call": 3,
              "return": 4,
              "input": { "type": "write", "value": 2 },
              "output": "ok",
            },
          ],
        }),
      ),
      "verdict",
    ),
    String("linearizable"),
  )
}

///|
test "equal call ordinals are refused by the identity contract" {
  let failed = try {
    ignore(
      parse_history({
        "model": "register",
        "initial": 0,
        "operations": [
          {
            "id": "w1",
            "client": "a",
            "call": 2,
            "return": 3,
            "input": { "type": "write", "value": 1 },
            "output": "ok",
          },
          {
            "id": "w2",
            "client": "b",
            "call": 2,
            "return": 4,
            "input": { "type": "write", "value": 2 },
            "output": "ok",
          },
        ],
      }),
    )
    false
  } catch {
    HistoryError(message) => message == "event ordinals must be globally unique"
  }
  assert_true(failed)
}
