# Current boundaries

- Built-in deterministic register/CAS, keyed register, FIFO queue, LIFO stack, mutual-exclusion lock, membership set, integer counter, key-value map, LWW element-set and monotonic max-register models only. No transactions, arbitrary executable-model plug-ins or database protocol collector.
- Finite observed histories are checked. Pending or unknown completion is not silently removed or completed.
- Reliable recorder ordinals are required. Uncalibrated cross-machine clocks cannot supply this assumed ordering. Client labels add no implicit serial-client constraints.
- Model values use finite Double and structural JSON equality, not arbitrary-precision decimal values.
- At most 256 operations by default, raisable per request to 4,096 with max_operations. High overlap can exhaust budgets. Unknown is neither a pass nor an impossibility proof.
- Decomposition applies to per-key independent models only (kv_register, map). Key budgets measure string units and entries, not whole-process heap bytes. No in-core wall-clock cancellation contract.
- Closed-state evidence concerns a supplied finite history and model, not every future system execution or implementation-level formal verification.
- Reduction proves at most single-operation-deletion 1-minimality, not global minimum size.
- The async demo runs controlled in-process services. No production database adoption or performance comparison against Porcupine is claimed.
- Four core targets are supported. The file adapter and recorder need Node.js 24; native tests need a C compiler. Source and installed-package evidence are recorded separately.
