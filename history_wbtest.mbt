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
test "models operation lists every model with partition flags" {
  let result = run(record([("operation", String("models"))]))
  let items = match result {
    Array(list) => list
    _ => abort("models did not answer an array")
  }
  assert_eq(items.length(), 26)
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
  assert_eq(catalog[24], "ticket_lock")
  assert_eq(catalog[25], "barrier")
  assert_eq(catalog.contains("kv_register"), true)
  assert_eq(catalog.contains("lww_map"), true)
  assert_eq(catalog.contains("map"), true)
}

///|
test "ticket_lock rejects interleaving and accepts handoff" {
  // Handoff: 0 acquires, 0 releases, 1 acquires (next ticket), 1 releases.
  let handoff = run(
    from_json(
      @json.parse(
        "{\"model\":\"ticket_lock\",\"initial\":-1,\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"c1\",\"call\":1,\"return\":2,\"input\":{\"type\":\"acquire\",\"ticket\":0},\"output\":\"ok\"}," +
        "{\"id\":\"b\",\"client\":\"c1\",\"call\":3,\"return\":4,\"input\":{\"type\":\"release\",\"ticket\":0},\"output\":\"ok\"}," +
        "{\"id\":\"c\",\"client\":\"c1\",\"call\":5,\"return\":6,\"input\":{\"type\":\"acquire\",\"ticket\":1},\"output\":\"ok\"}," +
        "{\"id\":\"d\",\"client\":\"c1\",\"call\":7,\"return\":8,\"input\":{\"type\":\"release\",\"ticket\":1},\"output\":\"ok\"}]}",
      ),
    ),
  )
  let verdict = match field(handoff, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // Non-owner release: 0 acquires, 1 tries to release - must fail.
  let stolen = run(
    from_json(
      @json.parse(
        "{\"model\":\"ticket_lock\",\"initial\":-1,\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"c1\",\"call\":1,\"return\":2,\"input\":{\"type\":\"acquire\",\"ticket\":0},\"output\":\"ok\"}," +
        "{\"id\":\"b\",\"client\":\"c1\",\"call\":3,\"return\":4,\"input\":{\"type\":\"release\",\"ticket\":1},\"output\":\"ok\"}]}",
      ),
    ),
  )
  let verdict2 = match field(stolen, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")
}

///|
test "barrier releases concurrent waiters at open" {
  // Two waiters straddle the open: both return only after it.
  let released = run(
    from_json(
      @json.parse(
        "{\"model\":\"barrier\",\"initial\":false,\"operations\":[" +
        "{\"id\":\"w1\",\"client\":\"c1\",\"call\":1,\"return\":8,\"input\":{\"type\":\"wait\"},\"output\":\"ok\"}," +
        "{\"id\":\"w2\",\"client\":\"c2\",\"call\":2,\"return\":9,\"input\":{\"type\":\"wait\"},\"output\":\"ok\"}," +
        "{\"id\":\"o\",\"client\":\"c3\",\"call\":3,\"return\":4,\"input\":{\"type\":\"open\"},\"output\":\"ok\"}]}",
      ),
    ),
  )
  let verdict = match field(released, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // A waiter that returns before the open was even invoked cannot
  // linearize: the barrier was still closed for its whole interval.
  let early = run(
    from_json(
      @json.parse(
        "{\"model\":\"barrier\",\"initial\":false,\"operations\":[" +
        "{\"id\":\"w\",\"client\":\"c1\",\"call\":1,\"return\":2,\"input\":{\"type\":\"wait\"},\"output\":\"ok\"}," +
        "{\"id\":\"o\",\"client\":\"c2\",\"call\":3,\"return\":4,\"input\":{\"type\":\"open\"},\"output\":\"ok\"}]}",
      ),
    ),
  )
  let verdict2 = match field(early, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")
}
