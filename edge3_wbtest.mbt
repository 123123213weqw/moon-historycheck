///|
test "lww register null initial and zero timestamp" {
  let history = parse_history({
    "model": "lww_register",
    "initial": null,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": "hello", "at": 0 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "read" },
        "output": "hello",
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(LwwRegister, state, op) {
      Some(next) => state = next
      None => abort("lww register at=0 replay failed")
    }
  }
  assert_eq(state, from_json({ "value": "hello", "at": 0 }))
}

///|
test "min register equal write is a no-op not a refusal" {
  let history = parse_history({
    "model": "min_register",
    "initial": 5,
    "operations": [
      {
        "id": "w",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "write", "value": 5 },
        "output": "ok",
      },
    ],
  })
  assert_eq(
    transition(MinRegister, history.initial, history.operations[0]),
    Some(Number(5)),
  )
}

///|
test "bounded queue dequeue to empty then overflow reports empty and false" {
  let history = parse_history({
    "model": "bounded_queue",
    "initial": [1],
    "operations": [
      {
        "id": "d",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "dequeue" },
        "output": { "value": 1 },
      },
      {
        "id": "d2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "dequeue" },
        "output": { "empty": true },
      },
      {
        "id": "e",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "enqueue", "value": 2 },
        "output": "ok",
      },
      {
        "id": "e2",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "enqueue", "value": 3 },
        "output": "ok",
      },
      {
        "id": "e3",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "enqueue", "value": 4 },
        "output": "ok",
      },
      {
        "id": "e4",
        "client": "a",
        "call": 11,
        "return": 12,
        "input": { "type": "enqueue", "value": 5 },
        "output": false,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(BoundedQueue, state, op) {
      Some(next) => state = next
      None => abort("bounded queue cycle failed")
    }
  }
  assert_eq(state, from_json([2, 3, 4]))
}

///|
test "semaphore exhaust and refill cycle" {
  let history = parse_history({
    "model": "semaphore",
    "initial": { "permits": 2, "taken": 0 },
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "acquire" },
        "output": true,
      },
      {
        "id": "a2",
        "client": "b",
        "call": 3,
        "return": 4,
        "input": { "type": "acquire" },
        "output": true,
      },
      {
        "id": "a3",
        "client": "c",
        "call": 5,
        "return": 6,
        "input": { "type": "acquire" },
        "output": false,
      },
      {
        "id": "r1",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "release" },
        "output": "ok",
      },
      {
        "id": "r2",
        "client": "b",
        "call": 9,
        "return": 10,
        "input": { "type": "release" },
        "output": "ok",
      },
      {
        "id": "a4",
        "client": "c",
        "call": 11,
        "return": 12,
        "input": { "type": "acquire" },
        "output": true,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(Semaphore, state, op) {
      Some(next) => state = next
      None => abort("semaphore cycle failed")
    }
  }
  assert_eq(state, from_json({ "permits": 2, "taken": 1 }))
}

///|
test "multiset add remove add leaves one copy" {
  let history = parse_history({
    "model": "multiset",
    "initial": [],
    "operations": [
      {
        "id": "a1",
        "client": "a",
        "call": 1,
        "return": 2,
        "input": { "type": "add", "value": 5 },
        "output": "ok",
      },
      {
        "id": "a2",
        "client": "a",
        "call": 3,
        "return": 4,
        "input": { "type": "add", "value": 5 },
        "output": "ok",
      },
      {
        "id": "r",
        "client": "a",
        "call": 5,
        "return": 6,
        "input": { "type": "remove", "value": 5 },
        "output": 2,
      },
      {
        "id": "a3",
        "client": "a",
        "call": 7,
        "return": 8,
        "input": { "type": "add", "value": 5 },
        "output": "ok",
      },
      {
        "id": "c",
        "client": "a",
        "call": 9,
        "return": 10,
        "input": { "type": "count", "value": 5 },
        "output": 2,
      },
    ],
  })
  let mut state = history.initial
  for op in history.operations {
    match transition(MultiSet, state, op) {
      Some(next) => state = next
      None => abort("multiset cycle failed")
    }
  }
  assert_eq(state, from_json([5, 5]))
}
