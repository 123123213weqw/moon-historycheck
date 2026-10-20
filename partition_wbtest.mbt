///|
test "independent key witnesses merge with global real-time constraints" {
  let result = from_json(
    execute({
      "model": "kv_register",
      "partition": true,
      "initial": { "x": 0, "y": 0 },
      "operations": [
        {
          "id": "wx",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "write", "key": "x", "value": 1 },
          "output": "ok",
        },
        {
          "id": "wy",
          "client": "b",
          "call": 3,
          "return": 4,
          "input": { "type": "write", "key": "y", "value": 2 },
          "output": "ok",
        },
        {
          "id": "rx",
          "client": "a",
          "call": 5,
          "return": 6,
          "input": { "type": "read", "key": "x" },
          "output": 1,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("linearizable"))
  assert_eq(field(result, "witness"), strings(["wx", "wy", "rx"]))
  assert_eq(field(result, "witness_verified"), Bool(true))
}

///|
test "unsafe model partition request is rejected" {
  assert_eq(
    field(
      from_json(
        execute({
          "model": "queue",
          "partition": true,
          "initial": [],
          "operations": [],
        }),
      ),
      "verdict",
    ),
    String("invalid_input"),
  )
}
