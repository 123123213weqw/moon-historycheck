///|
test "canonical object keys do not depend on insertion order" {
  assert_eq(from_json({ "b": 2, "a": 1 }).canonical(), "{\"a\":1,\"b\":2}")
}

///|
test "canonical object keys use lexical characters rather than string length" {
  assert_eq(from_json({ "z": 1, "aa": 2 }).canonical(), "{\"aa\":2,\"z\":1}")
}

///|
test "strict parser keeps incomplete operations observable" {
  let history = parse_history({
    "model": "register",
    "initial": null,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "input": { "type": "write", "value": 1 },
      },
    ],
  })
  assert_false(history.operations[0].complete)
  assert_eq(history.initial, Null)
}

///|
test "ambiguous event order is rejected" {
  let rejected = try {
    ignore(
      parse_history({
        "model": "register",
        "initial": 0,
        "operations": [
          {
            "id": "a",
            "client": "c",
            "call": 1,
            "return": 1,
            "input": { "type": "read" },
            "output": 0,
          },
        ],
      }),
    )
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "model refusals name the operation" {
  let failed : Value = String(
    match
      parse_history({
        "model": "register",
        "initial": 0,
        "operations": [
          {
            "id": "swap-op",
            "client": "a",
            "call": 1,
            "input": { "type": "swap" },
          },
        ],
      }) {
      _ => "no error raised"
    },
  ) catch {
    HistoryError(message) => String(message)
    _ => String("wrong error")
  }
  assert_eq(failed, String("swap-op: unsupported register operation: swap"))
}
