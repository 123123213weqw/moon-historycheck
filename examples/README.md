# One request per capability

Each file is a complete request. Run it with:

```sh
node _build/js/debug/build/cmd/main/main.js examples/<name>.json
```

Every model ships one. The four original history examples cover the core check flows; the model examples cover each algorithm's characteristic behavior.

| File | What it shows |
|---|---|
| overlap.json | a read concurrent with a write, linearizable |
| stale.json | a stale read after a completed write, non-linearizable |
| reduce.json | a counterexample reduced to its minimal pair |
| unknown.json | a pending write, reported unknown |
| stack.json | LIFO ordering |
| lock.json | mutual exclusion |
| set.json | membership with structural equality |
| counter.json | increment/decrement with steps |
| map.json | key-value with removal |
| lww_set.json | add-wins ties with timestamps |
| max_register.json | monotonic growth |
| grow_only_set.json | idempotent adds, no removal |
| two_phase_set.json | removal is forever |
| min_register.json | anti-monotonic descent |
| lww_register.json | strictly-newest-wins by timestamp |
| bounded_queue.json | capacity overflow observes false |
| deque.json | both-end ordering |
| semaphore.json | permit exhaustion |
| rwlock.json | reader-writer exclusion |
| multiset.json | duplicate counting |
| priority_queue.json | smallest-priority-first pop |
| pncounter.json | per-actor merge |
| lww_map.json | per-key newest-wins |
| `or_set.json` | per-tag add-wins with observed removes |
| `flag.json` | the one-way boolean barrier |
