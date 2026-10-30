# API and models

All operations use execute(Json) -> Json, or run(Value) -> Value. Unsupported fields are rejected. Domain-validation errors have verdict invalid_input and a reason.

## Shared history

```json
{
  "model": "register",
  "initial": 0,
  "operations": [
    {"id":"write","client":"a","call":1,"return":4,"input":{"type":"write","value":1},"output":"ok"},
    {"id":"read","client":"b","call":2,"return":3,"input":{"type":"read"},"output":0}
  ]
}
```

The read can precede the write despite being invoked later. The returned witness is checked against the complete history. Event ordinals are globally unique safe nonnegative JSON integers. IDs and clients have length 1..256. Initial and operation values share a 20,000-node validation budget, maximum depth 32 and 65,536 units per string. CLI input is at most 16 MiB of strictly decoded UTF-8.

No return/output means pending. Return without output, or output without a known return, is malformed. Explicit null is a legitimate completed output.

## Models

| Model | Initial state | Inputs | Observed outputs |
|---|---|---|---|
| register | Supported JSON value | read; write with value; cas with expected and value | read equals state; write is "ok"; CAS is the correct boolean |
| kv_register | Object mapping keys to values | Register commands with a nonempty key | Same per-key semantics; missing keys read null |
| queue | Array | enqueue with value; dequeue | enqueue is "ok"; dequeue is exactly {"value":v} or {"empty":true} |
| stack | Array | push with value; pop | push is "ok"; pop is exactly {"value":v} for the most recent push or {"empty":true} |
| lock | Boolean held flag | acquire; release | acquire returns whether it took the lock; release is "ok" and requires holding |
| set | Array of distinct values | add, remove or contains with value | add is "ok"; remove and contains return the structural membership boolean |
| counter | Finite number | increment or decrement with optional by (1..1000000, default 1); read | increment and decrement are "ok" and step by the given amount; read equals the current count |
| map | Object of key-value entries | put with key and value; get or remove with key | put is "ok"; get equals the entry or null when missing; remove returns whether the key was present and drops it only then |
| lww_set | Object with adds and rems timestamp tables | add or remove with string element and at (0..2^53-1); contains with element | add and remove are "ok" and keep the greatest timestamp; contains is add-wins on ties: present iff the add timestamp is at least the remove one |
| max_register | Finite number | write with value; read | write is "ok" only when the value is at least the current one and moves the state to it; read equals the current value |

Failed CAS leaves state unchanged. Reads and failed CAS do not introduce missing keys. Null is not an empty queue or stack. Releasing an unheld lock is a violation. Set membership and removal use structural JSON equality, so true is never 1. Wrong model outputs are violations, not automatically interpreted as network timeouts. The recorder must represent unknown completion as pending.

## check

Default operation. Optional max_states, max_memo_entries, max_memo_units, max_operations (1..4096, default 256) and partition (boolean, kv_register or map). Every operation accepts max_operations because the limit guards shared history parsing.

- linearizable: complete witness, final_state, witness_verified=true and stats.
- non_linearizable: complete_search=true and stats.
- unknown: reason, with no purported verified witness or counterexample.
- invalid_input: reason.

complete_search denotes exhaustive rejection, not simply a completed request. It is false for an early successful witness. Partition results show component checks; a failing key suffices for a negative conclusion, while unknown short-circuits remaining work. Expanded states are aggregated, memo resources apply to the active component.

## analyze

Accepts shared history and operation only. Reports all real-time obligations including transitive pairs, edge_count, overlap_pairs, max_in_flight and pending IDs. It does not decide model legality or compute a transitive reduction.

## verify

Shared history, operation verify, and witness (array of IDs). Rejects omissions, duplicates, unknown IDs, return-before-call violations and model-invalid outputs. A valid result contains verdict valid_witness, valid=true, final_state and a state-transition trace. Search budgets are not accepted.

## reduce

Shared history, operation reduce, optional search budgets and max_checks. Only a definite negative result is reduced. Trials delete contiguous chunks of complete operations, delta-debugging style: after an accepted chunk the granularity refines and scanning restarts, and the final pass always deletes one operation at a time. Initial state and remaining outputs are retained.

Reports history, removed IDs, trials (removed_candidates, verdict, reason), solver_checks, total_expanded_states, stopping_reason, reduction_complete and minimality. A complete result is 1-minimal_under_single_operation_deletion, not globally smallest. Unknown cannot justify deletion and prevents unsupported minimality claims.

## certify

Shared history, operation certify and optional search budgets. A breadth-first closed graph search without partitioning returns a verified positive witness, a fully rejected history with certificate and certificate_verified=true, or unknown on a budget cut.

Certificates bind to full normalized history_canonical text, not an unchecked hash. Nodes contain selected IDs, model state and outgoing operation/target edges. Object keys use character-lexical order. This is a project-specific format, not RFC 8785 canonicalization; do not reformat the binding with a different canonicalizer.

## verify_certificate

Shared history, operation verify_certificate and certificate. Checks binding, root state, every enabled legal branch, exact successor selection/state, no terminal node, and reachability. Temporal obligations are recomputed directly rather than trusting generator arrays.

Valid results contain verdict valid_certificate, valid=true, proved_verdict=non_linearizable and verified_nodes. Semantic defects return invalid_certificate; malformed structures return invalid_input. Limits are 4,096 nodes and 16,000,000 state-key units, and each model state is validated before recursive comparisons.
