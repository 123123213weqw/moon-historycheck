///|
test "memo resource exhaustion is reported as unknown" {
  let result = from_json(
    execute({
      "max_memo_units": 1,
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "r",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "read" },
          "output": 99,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("unknown"))
  assert_eq(field(result, "reason"), String("max_memo_units"))
}

///|
test "JSON boolean and number are different model values" {
  let result = from_json(
    execute({
      "model": "register",
      "initial": true,
      "operations": [
        {
          "id": "r",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "read" },
          "output": 1,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("non_linearizable"))
}

///|
test "irrelevant options are not silently ignored" {
  let result = from_json(
    execute({
      "operation": "analyze",
      "max_states": 5,
      "model": "register",
      "initial": 0,
      "operations": [],
    }),
  )
  assert_eq(field(result, "verdict"), String("invalid_input"))
}

///|
test "numeric zero sign cannot bypass unique recorder ordinals" {
  let result = from_json(
    execute({
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "a",
          "client": "x",
          "call": -0.0,
          "return": 1,
          "input": { "type": "read" },
          "output": 0,
        },
        {
          "id": "b",
          "client": "y",
          "call": 0,
          "return": 2,
          "input": { "type": "read" },
          "output": 0,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("invalid_input"))
}
