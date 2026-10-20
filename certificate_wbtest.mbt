///|
test "closed-state certificate validates every legal successor" {
  let source = from_json({
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
        "output": 0,
      },
    ],
  })
  let history = parse_history_value(source)
  let result = certify_history(history, search_limits(source))
  assert_eq(field(result, "certificate_verified"), Bool(true))
  assert_eq(
    field(verify_certificate(history, field(result, "certificate")), "valid"),
    Bool(true),
  )
  let certificate = object(field(result, "certificate"))
  let nodes = array(certificate["nodes"])
  let root = object(nodes[0])
  root["edges"] = Array([])
  assert_eq(
    field(verify_certificate(history, Object(certificate)), "valid"),
    Bool(false),
  )
}

///|
test "positive closure search yields independently verified witness" {
  let result = from_json(
    execute({
      "operation": "certify",
      "model": "register",
      "initial": 0,
      "operations": [
        {
          "id": "r",
          "client": "a",
          "call": 1,
          "return": 2,
          "input": { "type": "read" },
          "output": 0,
        },
      ],
    }),
  )
  assert_eq(field(result, "verdict"), String("linearizable"))
  assert_eq(field(result, "witness_verified"), Bool(true))
}
