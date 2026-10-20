///|
test "candidate witness cannot omit duplicate or reorder mandatory operations" {
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
        "output": 1,
      },
    ],
  })
  assert_eq(field(verify_history(h, ["w", "r"]), "valid"), Bool(true))
  assert_eq(field(verify_history(h, ["r", "w"]), "valid"), Bool(false))
  assert_eq(field(verify_history(h, ["w", "w"]), "valid"), Bool(false))
  assert_eq(field(verify_history(h, ["w"]), "valid"), Bool(false))
  assert_eq(field(verify_history(h, ["w", "unknown"]), "valid"), Bool(false))
}

///|
test "model-invalid concurrent witness rejected without a precedence conflict" {
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
  assert_eq(field(verify_history(h, ["w", "r"]), "valid"), Bool(false))
  assert_eq(field(verify_history(h, ["r", "w"]), "valid"), Bool(true))
}
