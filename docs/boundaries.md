# Current boundaries

- Built-in deterministic register/CAS, keyed register, FIFO queue, LIFO stack, mutual-exclusion lock, membership set, integer counter, key-value map, LWW element-set, monotonic max-register, grow-only set, two-phase set, min-register, last-writer-wins register, bounded queue, deque, counting semaphore, reader-writer lock and multiset models only; the bounded queue's capacity is a module constant (3); the lww_register ties and the lww_map dominated writes observe ok but leave the entry intact. No transactions, arbitrary executable-model plug-ins or database protocol collector.
- Finite observed histories are checked. Pending or unknown completion is not silently removed or completed.
- Reliable recorder ordinals are required. Uncalibrated cross-machine clocks cannot supply this assumed ordering. Client labels add no implicit serial-client constraints.
- Model values use finite Double and structural JSON equality, not arbitrary-precision decimal values.
- At most 256 operations by default, raisable per request to 4,096 with max_operations. High overlap can exhaust budgets. Unknown is neither a pass nor an impossibility proof.
- Decomposition applies to per-key independent models only (kv_register, map). Key budgets measure string units and entries, not whole-process heap bytes. No in-core wall-clock cancellation contract.
- Closed-state evidence concerns a supplied finite history and model, not every future system execution or implementation-level formal verification.
- Reduction proves at most single-operation-deletion 1-minimality, not global minimum size.
- The async demo runs controlled in-process services. No production database adoption or performance comparison against Porcupine is claimed.
- Four core targets are supported. The file adapter and recorder need Node.js 24; native tests need a C compiler. Source and installed-package evidence are recorded separately.
- The oracle is table-driven per model; the shared conditional chains it replaced are gone. Closure-audit counts shift by a handful when the per-model step functions draw randomness in a different order; the evidence documents are synced per release.
- lww_register and lww_map treat a tied timestamp as "cannot replay": only a strictly newer at moves the state. A dominated write in lww_map observes ok (the client was acknowledged) but leaves the entry intact.
- The bounded queue's capacity is a compile-time constant (3), not a request parameter.
- The counter's by amount is bounded to 1..1000000; the safe-integer replay boundary (2^53-1) is where increment and decrement stop being verifiable.

