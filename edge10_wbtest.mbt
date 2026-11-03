///|
test "all twenty-two models refuse an unknown operation kind" {
  for
    model in [
      "register", "queue", "stack", "lock", "set", "counter", "map", "lww_set", "max_register",
      "grow_only_set", "two_phase_set", "min_register", "lww_register", "bounded_queue",
      "deque", "semaphore", "rwlock", "multiset", "priority_queue", "pncounter",
      "lww_map",
    ] {
    let initial = match model {
      "register" | "counter" | "max_register" | "min_register" => Number(0)
      "queue"
      | "stack"
      | "set"
      | "grow_only_set"
      | "bounded_queue"
      | "deque"
      | "multiset"
      | "priority_queue" => Array([])
      "lock" => Bool(false)
      "lww_set" => from_json({ "adds": {}, "rems": {} })
      "two_phase_set" => from_json({ "added": [], "removed": [] })
      "pncounter" => from_json({ "p": {}, "n": {} })
      "rwlock" => from_json({ "readers": 0, "writer": false })
      _ => from_json({})
    }
    let report = run(
      record([
        ("model", String(model)),
        ("initial", initial),
        (
          "operations",
          Array([
            record([
              ("id", String("x")),
              ("client", String("c")),
              ("call", Number(1)),
              ("return", Number(2)),
              ("input", record([("type", String("nope"))])),
              ("output", String("ok")),
            ]),
          ]),
        ),
      ]),
    )
    let failed = String(
      match report {
        _ => "no error raised"
      },
    ) catch {
      InputError(message) => String(message)
    }
    assert_eq(failed, String("x: unsupported " + model + " operation: nope"))
  }
}
