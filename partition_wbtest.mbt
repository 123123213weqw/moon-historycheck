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

///|
test "multi_pncounter partitions into per-key sub-histories" {
  let result = from_json(
    execute({
      "model": "multi_pncounter",
      "partition": true,
      "initial": {},
      "operations": [
        {
          "id": "ax",
          "client": "a",
          "call": 1,
          "return": 4,
          "input": { "type": "increment", "key": "x", "who": "alice", "by": 2 },
          "output": "ok",
        },
        {
          "id": "by",
          "client": "b",
          "call": 2,
          "return": 3,
          "input": { "type": "increment", "key": "y", "who": "bob", "by": 5 },
          "output": "ok",
        },
        {
          "id": "rx",
          "client": "a",
          "call": 5,
          "return": 6,
          "input": { "type": "read", "key": "x" },
          "output": 2,
        },
        {
          "id": "ry",
          "client": "b",
          "call": 7,
          "return": 8,
          "input": { "type": "read", "key": "y" },
          "output": 5,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("linearizable"))
  assert_eq(field(result, "partitioned"), Bool(true))
  assert_eq(field(result, "witness_verified"), Bool(true))
}
