///|
test "stale read after completed write is impossible" {
  let result = execute({
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
  assert_eq(field(from_json(result), "verdict"), String("non_linearizable"))
  assert_eq(field(from_json(result), "complete_search"), Bool(true))
}

///|
test "search backtracks from call order to a legal concurrent order" {
  let result = from_json(
    execute({
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
    }),
  )
  assert_eq(field(result, "verdict"), String("linearizable"))
  assert_eq(field(result, "witness"), strings(["r", "w"]))
}

///|
test "budget cut is unknown and not a counterexample" {
  let result = from_json(
    execute({
      "max_states": 1,
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
          "output": 1,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("unknown"))
  assert_eq(field(result, "reason"), String("max_states"))
}

///|
test "earliest-return candidates are explored before call order" {
  let result = from_json(
    execute({
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "slow_write",
          "client": "a",
          "call": 1,
          "return": 8,
          "input": { "type": "write", "value": 1 },
          "output": "ok",
        },
        {
          "id": "quick_write",
          "client": "b",
          "call": 2,
          "return": 3,
          "input": { "type": "write", "value": 2 },
          "output": "ok",
        },
        {
          "id": "read_one",
          "client": "c",
          "call": 4,
          "return": 5,
          "input": { "type": "read" },
          "output": 1,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("linearizable"))
  assert_eq(
    field(result, "witness"),
    strings(["quick_write", "slow_write", "read_one"]),
  )
  assert_eq(field(field(result, "stats"), "expanded_states"), Number(3))
}

///|
test "malformed and pending requests are different outcomes" {
  assert_eq(
    field(
      from_json(
        execute({
          "model": "register",
          "initial": 0,
          "operations": [],
          "max_states": 0,
        }),
      ),
      "verdict",
    ),
    String("invalid_input"),
  )
  assert_eq(
    field(
      from_json(
        execute({
          "model": "register",
          "initial": 0,
          "operations": [
            {
              "id": "w",
              "client": "a",
              "call": 1,
              "input": { "type": "write", "value": 1 },
            },
          ],
        }),
      ),
      "verdict",
    ),
    String("unknown"),
  )
}
