///|
test "shrinker preserves failure and verifies a single-deletion fixed point" {
  let result = from_json(
    execute({
      "operation": "reduce",
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "noise",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "w",
          "client": "a",
          "call": 3,
          "return": 4,
          "input": { "type": "write", "value": 1 },
          "output": "ok",
        },
        {
          "id": "stale",
          "client": "b",
          "call": 5,
          "return": 6,
          "input": { "type": "read" },
          "output": 0,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("non_linearizable"))
  assert_eq(field(result, "remaining_operation_count"), Number(2))
  assert_eq(field(result, "reduction_complete"), Bool(true))
  assert_eq(
    field(run(field(result, "history")), "verdict"),
    String("non_linearizable"),
  )
}

///|
test "chunked shrinker removes grouped noise in few solver checks" {
  let result = from_json(
    execute({
      "operation": "reduce",
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "n0",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "n1",
          "client": "a",
          "call": 3,
          "return": 4,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "n2",
          "client": "a",
          "call": 5,
          "return": 6,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "n3",
          "client": "a",
          "call": 7,
          "return": 8,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "n4",
          "client": "a",
          "call": 9,
          "return": 10,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "w",
          "client": "a",
          "call": 11,
          "return": 12,
          "input": { "type": "write", "value": 1 },
          "output": "ok",
        },
        {
          "id": "stale",
          "client": "b",
          "call": 13,
          "return": 14,
          "input": { "type": "read" },
          "output": 0,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("non_linearizable"))
  assert_eq(field(result, "remaining_operation_count"), Number(2))
  assert_eq(field(result, "reduction_complete"), Bool(true))
  assert_eq(field(result, "solver_checks"), Number(5))
}

///|
test "bounded reduction never pretends an unchecked history is minimal" {
  let result = from_json(
    execute({
      "operation": "reduce",
      "max_checks": 1,
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
          "id": "stale",
          "client": "b",
          "call": 3,
          "return": 4,
          "input": { "type": "read" },
          "output": 0,
        },
      ],
    }),
  )
  assert_eq(field(result, "reduction_complete"), Bool(false))
  assert_eq(field(result, "minimality"), String("not_proven"))
}
