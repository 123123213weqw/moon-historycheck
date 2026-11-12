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
  }
  assert_eq(failed, String("swap-op: unsupported register operation: swap"))
}

///|
test "models operation lists all 24 with partition flags" {
  let result = run(record([("operation", String("models"))]))
  let items = match result {
    Array(list) => list
    _ => abort("models did not answer an array")
  }
  assert_eq(items.length(), 24)
  // Partition-capable models are exactly the three.
  let partitionable = items.filter(entry => {
    match field(entry, "supports_partition") {
      Bool(true) => true
      _ => false
    }
  })
  assert_eq(partitionable.length(), 3)
  // Every name is unique.
  let seen : Map[String, Bool] = Map([])
  for entry in items {
    let name = match field(entry, "name") {
      String(n) => n
      _ => "bad"
    }
    assert_eq(seen.contains(name), false)
    seen[name] = true
  }
}

///|
test "models catalog matches the enum's model_name spellings" {
  let catalog = list_models().map(info => info.name)
  // The enum's own spellings are the ground truth; spot-check both ends
  // and the partition-marked ones.
  assert_eq(catalog[0], "register")
  assert_eq(catalog[23], "flag")
  assert_eq(catalog.contains("kv_register"), true)
  assert_eq(catalog.contains("lww_map"), true)
  assert_eq(catalog.contains("map"), true)
}
