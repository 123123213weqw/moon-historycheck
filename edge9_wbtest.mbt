///|
test "stack pop after interleaved pushes maintains LIFO" {
  let history = parse_history({
    "model": "stack",
    "initial": [],
    "operations": [
      {
        "id": "p1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "push", "value": 1 },
        "output": "ok",
      },
      {
        "id": "p2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "push", "value": 2 },
        "output": "ok",
      },
      {
        "id": "p3",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "push", "value": 3 },
        "output": "ok",
      },
      {
        "id": "d1",
        "client": "c",
        "call": 7,
        "return": 8,
        "input": { "type": "pop" },
        "output": { "value": 3 },
      },
      {
        "id": "p4",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "push", "value": 4 },
        "output": "ok",
      },
      {
        "id": "d2",
        "client": "c",
        "call": 11,
        "return": 12,
        "input": { "type": "pop" },
        "output": { "value": 4 },
      },
      {
        "id": "d3",
        "client": "c",
        "call": 13,
        "return": 14,
        "input": { "type": "pop" },
        "output": { "value": 2 },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Stack, state, op) {
      Some(next) => state = next
      None => abort("stack interleaved replay failed")
    }
  }
  assert_eq(state, from_json([1]))
}

///|
test "queue interleaved enqueue-dequeue maintains FIFO" {
  let history = parse_history({
    "model": "queue",
    "initial": [],
    "operations": [
      {
        "id": "e1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "enqueue", "value": 1 },
        "output": "ok",
      },
      {
        "id": "e2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "enqueue", "value": 2 },
        "output": "ok",
      },
      {
        "id": "d1",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "dequeue" },
        "output": { "value": 1 },
      },
      {
        "id": "e3",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "enqueue", "value": 3 },
        "output": "ok",
      },
      {
        "id": "d2",
        "client": "c",
        "call": 9,
        "return": 10,
        "input": { "type": "dequeue" },
        "output": { "value": 2 },
      },
      {
        "id": "d3",
        "client": "c",
        "call": 11,
        "return": 12,
        "input": { "type": "dequeue" },
        "output": { "value": 3 },
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Queue, state, op) {
      Some(next) => state = next
      None => abort("queue interleaved replay failed")
    }
  }
  assert_eq(state, from_json([]))
}
