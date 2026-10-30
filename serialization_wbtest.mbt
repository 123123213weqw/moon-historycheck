///|
/// These spellings are asserted in a white-box test so all four backends check
/// them on every build: byte-identical output across backends is what makes a
/// witness portable, and the constants were read off the JS CLI rather than
/// copied back from the implementation under test.
test "number spellings are pinned" {
  assert_eq(Number(420).to_json().stringify(), "420")
  assert_eq(from_json(@json.parse("1e21")).to_json().stringify(), "1e+21")
  assert_eq(Number(-0.0).to_json().stringify(), "0")
  assert_eq(Number(0.1).to_json().stringify(), "0.1")
  assert_eq(
    Number(9007199254740992.0).to_json().stringify(),
    "9007199254740992",
  )
}

///|
test "string escapes are pinned" {
  assert_eq(String("q\"b\\c\nd").to_json().stringify(), "\"q\\\"b\\\\c\\nd\"")
  assert_eq(String("é😀").to_json().stringify(), "\"é😀\"")
}

///|
test "canonical sorts object keys" {
  let value = record([
    ("b", Number(2)),
    ("a", record([("z", Number(1)), ("y", Number(2))])),
  ])
  assert_eq(value.canonical(), "{\"a\":{\"y\":2,\"z\":1},\"b\":2}")
}

///|
test "the canonical history body is pinned" {
  // The checksum and certificate binding both hash this canonical form, so its
  // exact spelling is part of the format.
  let history = parse_history({
    "model": "register",
    "initial": 0,
    "operations": [
      {
        "id": "a",
        "client": "c",
        "call": 1,
        "return": 2,
        "input": { "type": "read" },
        "output": 0,
      },
    ],
  })
  assert_eq(
    history_value(history).canonical(),
    "{\"initial\":0,\"model\":\"register\",\"operations\":[{\"call\":1,\"client\":\"c\",\"id\":\"a\",\"input\":{\"type\":\"read\"},\"output\":0,\"return\":2}]}",
  )
}
