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
  assert_eq(items.length(), 31)
  // Partition-capable models are exactly the four.
  let partitionable = items.filter(entry => {
    match field(entry, "supports_partition") {
      Bool(true) => true
      _ => false
    }
  })
  assert_eq(partitionable.length(), 4)
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
  assert_eq(catalog[26], "versioned_register")
  assert_eq(catalog[27], "rw_register")
  assert_eq(catalog[28], "set_of_sets")
  assert_eq(catalog[29], "multi_pncounter")
  assert_eq(catalog[30], "register_with_expiry")
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

///|
test "versioned_register hands out each version exactly once" {
  // A read racing the write observes the old pair; the later read the new.
  let raced = run(
    from_json(
      @json.parse(
        "{\"model\":\"versioned_register\",\"initial\":{\"value\":0,\"version\":0},\"operations\":[" +
        "{\"id\":\"w\",\"client\":\"a\",\"call\":1,\"return\":4,\"input\":{\"type\":\"write\",\"value\":1},\"output\":1}," +
        "{\"id\":\"r1\",\"client\":\"b\",\"call\":2,\"return\":3,\"input\":{\"type\":\"read\"},\"output\":{\"value\":0,\"version\":0}}," +
        "{\"id\":\"r2\",\"client\":\"c\",\"call\":5,\"return\":6,\"input\":{\"type\":\"read\"},\"output\":{\"value\":1,\"version\":1}}]}",
      ),
    ),
  )
  let verdict = match field(raced, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // A read that finishes before the write starts cannot claim version 1.
  let premature = run(
    from_json(
      @json.parse(
        "{\"model\":\"versioned_register\",\"initial\":{\"value\":0,\"version\":0},\"operations\":[" +
        "{\"id\":\"r\",\"client\":\"b\",\"call\":1,\"return\":2,\"input\":{\"type\":\"read\"},\"output\":{\"value\":1,\"version\":1}}," +
        "{\"id\":\"w\",\"client\":\"a\",\"call\":3,\"return\":4,\"input\":{\"type\":\"write\",\"value\":1},\"output\":1}]}",
      ),
    ),
  )
  let verdict2 = match field(premature, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")

  // Two writes cannot both claim version 1: versions are exclusive.
  let duplicated = run(
    from_json(
      @json.parse(
        "{\"model\":\"versioned_register\",\"initial\":{\"value\":0,\"version\":0},\"operations\":[" +
        "{\"id\":\"w1\",\"client\":\"a\",\"call\":1,\"return\":2,\"input\":{\"type\":\"write\",\"value\":5},\"output\":1}," +
        "{\"id\":\"w2\",\"client\":\"b\",\"call\":3,\"return\":4,\"input\":{\"type\":\"write\",\"value\":7},\"output\":1}]}",
      ),
    ),
  )
  let verdict3 = match field(duplicated, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict3, "non_linearizable")
}

///|
test "rw_register allows concurrent reads but exclusive writes" {
  // Two reads straddle a write and both observe the old value: reads
  // never change state, so any number of them may overlap.
  let shared = run(
    from_json(
      @json.parse(
        "{\"model\":\"rw_register\",\"initial\":0,\"operations\":[" +
        "{\"id\":\"r1\",\"client\":\"a\",\"call\":1,\"return\":5,\"input\":{\"type\":\"read\"},\"output\":0}," +
        "{\"id\":\"r2\",\"client\":\"b\",\"call\":2,\"return\":6,\"input\":{\"type\":\"read\"},\"output\":0}," +
        "{\"id\":\"w\",\"client\":\"c\",\"call\":3,\"return\":4,\"input\":{\"type\":\"write\",\"value\":5},\"output\":0}]}",
      ),
    ),
  )
  let verdict = match field(shared, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // Two overlapping writes that both report the same pre-state cannot
  // serialize: whoever goes second must observe the first one's value.
  let collided = run(
    from_json(
      @json.parse(
        "{\"model\":\"rw_register\",\"initial\":0,\"operations\":[" +
        "{\"id\":\"w1\",\"client\":\"a\",\"call\":1,\"return\":10,\"input\":{\"type\":\"write\",\"value\":5},\"output\":0}," +
        "{\"id\":\"w2\",\"client\":\"b\",\"call\":2,\"return\":9,\"input\":{\"type\":\"write\",\"value\":7},\"output\":0}]}",
      ),
    ),
  )
  let verdict2 = match field(collided, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")

  // The same overlap is legal when the second writer observes the first.
  let serialized = run(
    from_json(
      @json.parse(
        "{\"model\":\"rw_register\",\"initial\":0,\"operations\":[" +
        "{\"id\":\"w1\",\"client\":\"a\",\"call\":1,\"return\":10,\"input\":{\"type\":\"write\",\"value\":5},\"output\":0}," +
        "{\"id\":\"w2\",\"client\":\"b\",\"call\":2,\"return\":9,\"input\":{\"type\":\"write\",\"value\":7},\"output\":5}]}",
      ),
    ),
  )
  let verdict3 = match field(serialized, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict3, "linearizable")
}

///|
test "set_of_sets admits whole subsets and rejects phantom members" {
  // A contains racing an add of the same subset may linearize after it;
  // the later remove then applies to the added subset.
  let admitted = run(
    from_json(
      @json.parse(
        "{\"model\":\"set_of_sets\",\"initial\":[],\"operations\":[" +
        "{\"id\":\"a1\",\"client\":\"a\",\"call\":1,\"return\":4,\"input\":{\"type\":\"add_set\",\"set\":[1,2]},\"output\":\"ok\"}," +
        "{\"id\":\"c1\",\"client\":\"b\",\"call\":2,\"return\":3,\"input\":{\"type\":\"contains_set\",\"set\":[1,2]},\"output\":true}," +
        "{\"id\":\"r1\",\"client\":\"a\",\"call\":5,\"return\":6,\"input\":{\"type\":\"remove_set\",\"set\":[1,2]},\"output\":true}]}",
      ),
    ),
  )
  let verdict = match field(admitted, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // A removal reporting success for a subset that was never added cannot
  // replay: no linearization point holds [7].
  let phantom_removal = run(
    from_json(
      @json.parse(
        "{\"model\":\"set_of_sets\",\"initial\":[],\"operations\":[" +
        "{\"id\":\"r\",\"client\":\"a\",\"call\":1,\"return\":2,\"input\":{\"type\":\"remove_set\",\"set\":[7]},\"output\":true}]}",
      ),
    ),
  )
  let verdict2 = match field(phantom_removal, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")

  // Membership of a different subset returning true is likewise impossible:
  // only [1] was ever added, and subsets compare structurally.
  let phantom_member = run(
    from_json(
      @json.parse(
        "{\"model\":\"set_of_sets\",\"initial\":[],\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"a\",\"call\":1,\"return\":4,\"input\":{\"type\":\"add_set\",\"set\":[1]},\"output\":\"ok\"}," +
        "{\"id\":\"c\",\"client\":\"b\",\"call\":2,\"return\":3,\"input\":{\"type\":\"contains_set\",\"set\":[2]},\"output\":true}]}",
      ),
    ),
  )
  let verdict3 = match field(phantom_member, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict3, "non_linearizable")
}

///|
test "multi_pncounter totals per key from merged actor tables" {
  // Two actors race increments on one key while a second key decays below
  // zero; each read observes its own key's merged total.
  let merged = run(
    from_json(
      @json.parse(
        "{\"model\":\"multi_pncounter\",\"initial\":{},\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"c1\",\"call\":1,\"return\":6,\"input\":{\"type\":\"increment\",\"key\":\"orders\",\"who\":\"alice\",\"by\":2},\"output\":\"ok\"}," +
        "{\"id\":\"b\",\"client\":\"c2\",\"call\":2,\"return\":5,\"input\":{\"type\":\"increment\",\"key\":\"orders\",\"who\":\"bob\",\"by\":3},\"output\":\"ok\"}," +
        "{\"id\":\"c\",\"client\":\"c1\",\"call\":7,\"return\":8,\"input\":{\"type\":\"read\",\"key\":\"orders\"},\"output\":5}," +
        "{\"id\":\"d\",\"client\":\"c3\",\"call\":9,\"return\":10,\"input\":{\"type\":\"decrement\",\"key\":\"returns\",\"who\":\"alice\",\"by\":1},\"output\":\"ok\"}," +
        "{\"id\":\"e\",\"client\":\"c3\",\"call\":11,\"return\":12,\"input\":{\"type\":\"read\",\"key\":\"returns\"},\"output\":-1}]}",
      ),
    ),
  )
  let verdict = match field(merged, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // No linearization of one increment of 2 and one of 3 can answer 4:
  // the reachable totals are 0, 2, 3 and 5.
  let phantom_total = run(
    from_json(
      @json.parse(
        "{\"model\":\"multi_pncounter\",\"initial\":{},\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"c1\",\"call\":1,\"return\":4,\"input\":{\"type\":\"increment\",\"key\":\"orders\",\"who\":\"alice\",\"by\":2},\"output\":\"ok\"}," +
        "{\"id\":\"b\",\"client\":\"c2\",\"call\":2,\"return\":5,\"input\":{\"type\":\"increment\",\"key\":\"orders\",\"who\":\"bob\",\"by\":3},\"output\":\"ok\"}," +
        "{\"id\":\"c\",\"client\":\"c1\",\"call\":6,\"return\":7,\"input\":{\"type\":\"read\",\"key\":\"orders\"},\"output\":4}]}",
      ),
    ),
  )
  let verdict2 = match field(phantom_total, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")

  // Keys are independent: a read of an untouched key cannot observe the
  // other key's total.
  let cross_key = run(
    from_json(
      @json.parse(
        "{\"model\":\"multi_pncounter\",\"initial\":{},\"operations\":[" +
        "{\"id\":\"a\",\"client\":\"c1\",\"call\":1,\"return\":2,\"input\":{\"type\":\"increment\",\"key\":\"orders\",\"who\":\"alice\",\"by\":2},\"output\":\"ok\"}," +
        "{\"id\":\"c\",\"client\":\"c2\",\"call\":3,\"return\":4,\"input\":{\"type\":\"read\",\"key\":\"returns\"},\"output\":2}]}",
      ),
    ),
  )
  let verdict3 = match field(cross_key, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict3, "non_linearizable")
}

///|
test "register_with_expiry blinds readers at the expiry instant" {
  // A read racing the write linearizes after it and observes the live
  // value; a later read at the expiry instant itself observes expiration.
  let expiring = run(
    from_json(
      @json.parse(
        "{\"model\":\"register_with_expiry\",\"initial\":null,\"operations\":[" +
        "{\"id\":\"w\",\"client\":\"a\",\"call\":1,\"return\":4,\"input\":{\"type\":\"write\",\"value\":1,\"expires_at\":10},\"output\":\"ok\"}," +
        "{\"id\":\"r1\",\"client\":\"b\",\"call\":2,\"return\":3,\"input\":{\"type\":\"read\",\"at\":5},\"output\":1}," +
        "{\"id\":\"r2\",\"client\":\"b\",\"call\":5,\"return\":6,\"input\":{\"type\":\"read\",\"at\":10},\"output\":null}]}",
      ),
    ),
  )
  let verdict = match field(expiring, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict, "linearizable")

  // A read that completes before any write starts cannot observe a value:
  // the register was null for its whole interval.
  let premature = run(
    from_json(
      @json.parse(
        "{\"model\":\"register_with_expiry\",\"initial\":null,\"operations\":[" +
        "{\"id\":\"r\",\"client\":\"b\",\"call\":1,\"return\":2,\"input\":{\"type\":\"read\",\"at\":5},\"output\":1}," +
        "{\"id\":\"w\",\"client\":\"a\",\"call\":3,\"return\":4,\"input\":{\"type\":\"write\",\"value\":1,\"expires_at\":10},\"output\":\"ok\"}]}",
      ),
    ),
  )
  let verdict2 = match field(premature, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict2, "non_linearizable")

  // A read at the expiry instant claiming the value ignores expiration:
  // at == expires_at is already expired, in every linearization.
  let stale = run(
    from_json(
      @json.parse(
        "{\"model\":\"register_with_expiry\",\"initial\":null,\"operations\":[" +
        "{\"id\":\"w\",\"client\":\"a\",\"call\":1,\"return\":2,\"input\":{\"type\":\"write\",\"value\":1,\"expires_at\":10},\"output\":\"ok\"}," +
        "{\"id\":\"r\",\"client\":\"b\",\"call\":3,\"return\":4,\"input\":{\"type\":\"read\",\"at\":10},\"output\":1}]}",
      ),
    ),
  )
  let verdict3 = match field(stale, "verdict") {
    String(s) => s
    _ => "bad"
  }
  assert_eq(verdict3, "non_linearizable")
}
