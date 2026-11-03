# Engineering choices

## Observation and model

Operations have an input, observed output and invocation/response interval. Real-time constraints come from unique recorder ordinals. Overlap does not introduce an invocation-order edge. A legal sequence covers every operation once, obeys non-overlap constraints and reproduces every output under the model.

## Memoized search

The selected mask and full canonical state identify a search state. A mask alone incorrectly merges different write orders. Full state keys avoid trusting hash equality. Only completely exhausted DFS states enter the negative memo table. Every recursive step selects one operation, so depth is bounded by 256.

Limits bound deterministic work and retained keys, not total heap bytes or elapsed time. Raw input and semantic-value sizes have separate bounds. High overlap remains combinatorial, so unknown is a first-class result.

## Positive and negative evidence

The witness verifier does not invoke search or trust its predecessor arrays. It checks coverage, re-derives all pairwise obligations and replays the model. It shares the transition specification, because a witness is meaningful only relative to that specification.

Negative certification uses a separate breadth-first graph builder. Its verifier checks closure of every reachable nonterminal state under all enabled legal transitions. Closed finite reachability without a terminal node establishes rejection under the chosen model. The verifier shares model semantics but not construction logic or pruning. This is not a formal proof that either implementation has no defects.

## Decomposition and reduction

Only independent keyed registers admit decomposition. Local orders are merged with global real-time edges and the full witness is checked again. Transactions and queues are not split by a convenient field name.

Deletion changes the history's possible behavior. Every candidate is solved again. Unknown cannot support deletion. An accepted deletion restarts scanning so stale deletion results cannot justify a minimality claim. The final claim is single-operation-deletion minimality with the same initial state.

## Module responsibilities

history and value validate input; models specifies behavior; precedence derives temporal obligations; search performs bounded DFS; witness verifies positive evidence; partition handles independent objects; reduction shrinks definite failures; certificate constructs and verifies negative closure; api rejects irrelevant options and dispatches. The Node adapter does not replace domain search.

Python enumerates small permutations without production memoization or partitioning, using a separately written transition model. Closure graphs are audited independently in Python. Golden cases exercise both core API and CLI, including negative witnesses, tampered certificates and unknown outcomes.

## Model family

Twenty-two sequential models (22) share one transition interface (state, operation
-> next state or refusal) and one identity contract (unique ordinals, unique
IDs). The register family is monotonic (max), anti-monotonic (min) and
timestamp-ordered (LWW); the collection family covers set, multiset, map,
priority queue and bounded/unbounded FIFO and LIFO; the coordination family
covers lock, counting semaphore and reader-writer lock; the counter family
covers plain, grow-only set, two-phase set, positive-negative and per-key
last-writer-wins. Each model's semantics are pinned by wbtest, fixture,
oracle entry and (where applicable) a runnable example.

## Oracle architecture

The independent Python oracle is table-driven per model: each entry supplies
the initial state, an apply() that answers one operation, and a legal-step
generator for positive histories. Adding a model is a pure table append — the
shared conditional chains this replaced were where three generator defects
were planted and caught. The oracle covers permutation brute force, witness
replay, partition equivalence (kv_register, map, lww_map) and reduction
minimality.

## Blocked-acquire semantics

Models with a "blocked" verdict (lock, semaphore, rwlock, bounded queue)
treat a failed acquisition as a legal observation — output false — rather
than a replay failure. The distinction matters because a client that was
told "no" recorded a real event, and the checker must honor it. The first
cut of rwlock treated blocked acquires as replay failures, which the
fixture writer-excludes-readers caught immediately.

## Partition family

kv_register, map and lww_map are per-key independent, so their histories
decompose: each key's operations form a sub-history checked in isolation,
the aggregate budget is shared, and the merged witness is re-verified
against the full history. kv_register strips the key (each object becomes a
plain register); map and lww_map keep the key because their commands name
it. lww_map keys seed from their own entry ({value, at}) or an empty object
when never written — the first cut seeded Null, which broke every get on a
never-written key. The oracle cross-checks 360 partition equivalences
(120 each for kv_register, map and lww_map).

## Earliest-return-first search ordering

The DFS explores candidate operations by recorder return ordinal instead of
call order: real-time-consistent linearizations surface early, so typical
histories need less backtracking. The regression test pins the reduced
expansion count on a backtracking-prone history — a change that backtracks
more fails the gate before any human notices a slowdown. Exploration order
does not affect completeness, exhaustion results or the independently
verified witness contract.

## Table-driven oracle

The independent Python oracle was originally a pair of shared conditional
chains (one for apply, one for the legal-step generator). Adding a model
meant splicing both chains, and three generator defects were planted and
caught in exactly that way. The oracle is now table-driven per model: each
entry supplies the initial state, an apply() and a step() generator, and
adding a model is a pure append. The refactor surfaced two latent issues —
pending operations have no return field (verify treats a missing return as
+infinity), and the event-ordinal assignment for positive histories had been
folded into the old chain and went missing in the first cut.

## Partition sub-model dispatch

The partition path strips the key for kv_register (each object becomes a
plain register) and keeps the key for map and lww_map (their commands name
it). The first lww_map partition cut dispatched both map and lww_map
sub-histories as lww_map, which broke every map partition fixture — the sub
model must be the parent model itself, not a constant.

## Counter family

The plain counter steps by 1..1000000 and replays until 2^53-1, beyond which
increment and decrement are unverifiable. The positive-negative counter
tracks per-actor tables rather than a bare total, which is what makes it the
mergeable CRDT form rather than a plain register: merging two replicas'
tables is a per-key max, and the sum is derived.

## Collection family

The set, grow-only set, two-phase set and multiset differ in their removal
semantics: the set removes exactly one copy and reports membership; the
grow-only set never removes; the two-phase set removes forever (an add
after remove cannot resurrect); the multiset counts duplicates and drops
exactly one copy per remove. The map and bounded queue extend the same
principle with keys and capacity respectively.

## Register family

The plain register has CAS; the kv_register adds per-key independence; the
min and max registers are anti-monotonic and monotonic respectively (a
write in the wrong direction is a refusal, not a no-op); the lww_register
and lww_map keep the strictly newest write by timestamp over a
null-initialized or per-key state; a dominated write in lww_map observes
ok (the client was acknowledged) but leaves the entry intact.

## Priority queue, pncounter and lww_map

The priority queue appends in insertion order and pops the smallest priority,
first-inserted among ties. The pncounter tracks per-actor tables (p for
increments, n for decrements) rather than a bare total, which is what makes
it the mergeable CRDT form: merging two replicas is a per-key max, and the
sum is derived. The lww_map keeps per-key {value, at} entries and moves one
only on a strictly newer at; a dominated write observes ok (the client was
acknowledged) but leaves the entry intact.

## Per-model transition summary

| Model | State | Transitions | Key invariant |
|---|---|---|---|
| register | value | read; write; cas | CAS only when equal |
| kv_register | key→value | per-key register ops | missing keys read null |
| queue | FIFO array | enqueue; dequeue | oldest first |
| stack | LIFO array | push; pop | newest first |
| lock | held bool | acquire; release | mutual exclusion |
| set | array | add; remove; contains | structural membership |
| counter | number | increment; decrement; read | by 1..1000000 |
| map | key→value | put; get; remove | missing keys read null |
| lww_set | adds+rems | add; remove; contains (at) | add-wins ties |
| max_register | number | write; read | only grows |
| grow_only_set | array | add; contains | never removes |
| two_phase_set | added+removed | add; remove; contains | no resurrection |
| min_register | number | write; read | only shrinks |
| lww_register | value+at or null | write (value, at); read | strictly newer at |
| bounded_queue | array (≤3) | enqueue; dequeue | overflow observes false |
| deque | array | push_front/back; pop_front/back | both-end ordering |
| semaphore | permits+taken | acquire; release | taken ≤ permits |
| rwlock | readers+writer | acquire_read; release_read; acquire_write; release_write | readers xor writer |
| multiset | array (duplicates) | add; remove; count | copy count |
| priority_queue | array of (value, priority) | push; pop_min | smallest first |
| pncounter | p+n tables | increment (who, by); decrement (who, by); read | per-actor sum |
| lww_map | key→(value, at) | set (key, value, at); get | strictly newer at per key |

## Oracle coverage matrix

Each of the twenty-two models is exercised by five evidence layers: white-box
tests (transition calls), CLI fixtures (through the compiled binary), the
independent Python oracle (permutation brute force), the closure audit
(breadth-first rejection certificates) and a shipped example (pinned answer).
The matrix is checked by scripts/coverage.py, which names any model missing
a layer.

## Model evolution

The model family grew from three (register, kv_register, queue) in 0.1.0 to
twenty-two in 0.5.0. Each addition followed the same pattern: the transition
semantics are pinned by a wbtest, the oracle table gains an entry, the
golden CLI cases pin the characteristic behavior, a runnable example ships,
and the robustness sweep covers the malformed-input shapes. The table-driven
oracle made additions pure appends, eliminating the shared conditional
chains where three generator defects were planted and caught.

## Blocked-acquire and dominated-write semantics

Models with a "blocked" verdict (lock, semaphore, rwlock, bounded queue)
treat a failed acquisition as a legal observation — output false or null —
rather than a replay failure. Models with a "dominated" verdict (lww_register,
lww_map) treat a stale or dominated write as acknowledged but not applied.
Both distinctions were caught by fixtures and wbtests after the first cuts
got them wrong, and both are documented where they live.

## Gate architecture

The gate (scripts/gate.py) asserts deterministic properties — expansion
counts and verdicts — rather than timings, because timings vary by machine
and a strict check would be turned off within a week. Eighteen relations
cover serial linearity, concurrent maxima, memoized exhaustion, partition
sums and per-model verdicts. A search-order change that backtracks more
fails the gate on every backend before any human notices a slowdown.

## Delta-debugging reduction

Trials delete contiguous chunks of operations, refining granularity after
each accepted chunk and restarting; the final pass always deletes single
operations, so a complete result still proves 1-minimality under single
operation deletion and unknown subresults still block minimality claims.
Grouped noise shrinks with fewer solver checks — 5 instead of 8 on the
regression history.

## Witness verifier

The witness verifier does not trust the searcher's predecessor arrays: it
recomputes every pairwise return-before-call obligation directly and replays
the model at each step. A witness that passes is a statement about the
complete history, not about the search path that found it. The partition
merge reuses this verifier on the global history after combining per-key
chains.

## Certificate verifier

The certificate verifier checks the initial binding, every enabled legal
branch, exact successor selection and state, node reachability, and the
absence of a terminal node. It recomputes temporal obligations directly
rather than trusting the generator's predecessor arrays.

## Fixture uniqueness

The oracle asserts every fixture case name is unique before running. The
check was added after a patch applied twice produced a duplicate fixture,
which the regenerated white-box file then failed as a duplicate test
declaration.

