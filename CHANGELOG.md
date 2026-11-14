# Changelog

## 0.9.0 — 2026-11-14

Thirty-three sequential models, up from twenty-eight at 0.8.0. Five new
models join the checker, each with a distinct observability lesson, and
CI now pins its toolchain:

set_of_sets (model 29): a set whose elements are themselves sets.
add_set pushes a whole subset once (structural equality, duplicates
collapse), remove_set drops exactly one matching subset and reports
whether one existed, contains_set answers membership. Validation
requires the payload to be an array, so a bare element cannot sneak
into a collection-of-collections history.

multi_pncounter (model 30): one PN-counter family spread over named
keys, each key carrying its own positive and negative per-actor tables.
Keys never see each other's totals, and that per-key independence makes
it the fourth partitionable model: check_partitioned splits a history
by key, seeds never-touched keys as two empty tables, and re-verifies
the merged witness against the full history.

register_with_expiry (model 31): writes stamp an expiry instant and
always succeed - expiry never blocks a writer, it only blinds readers.
Reads carry the instant they observe at: strictly before expires_at the
value is visible, at the instant itself and after the register reads
null, and an unwritten register reads null however late the observer
is.

fifo_channel (model 32): a two-slot FIFO channel with paired
send/recv. send reports true while a slot is free and false once full
(a refused send never entered); recv hands back the oldest item
directly and answers null on an empty channel.

priority_deque (model 33): a double-ended priority queue. push stamps a
priority, pop_min extracts the smallest and pop_max the largest, both
taking the first-inserted element among ties - the tie bias makes the
extract order observable, not just the extremes. An empty deque answers
{empty: true} on either end.

CI installs the moon toolchain from this repository's own
toolchain-0.1.20261104 release asset instead of whatever the setup
action fetched that day, so toolchain drift cannot flip verdicts or
deny-warns without a local change. 244 tests across the four targets,
zero warnings on 0.1.20261104.

## 0.8.0 — 2026-11-13

Twenty-eight sequential models, up from twenty-four at 0.7.0. Four new
models join the checker, each with a distinct concurrency lesson:

ticket_lock (model 25): ticket-based mutual exclusion. State is the
currently-held ticket number; acquire(n) succeeds when free or when n
is the next ticket; release(n) only from the holder. A blocked acquire
leaves state unchanged, representing locks that fail rather than block.

barrier (model 26): one-shot distributed barrier. open is idempotent;
a completed wait can only linearize after open - a wait that returns
before open violates real-time and the whole history is rejected.

versioned_register (model 27): per-write version numbers. write
returns the version it claims (previous + 1); read returns value and
version. The write-output version sequence is the observable proof of
write serialization; two writes claiming the same version cannot
linearize.

rw_register (model 28): concurrent reads with exclusive writers. read
is pure (any number can overlap); write is get-and-set returning the
exact prior state - two writes can never observe the same predecessor,
so write exclusion is observable in the outputs.

The models operation (new in this release) answers with the complete
model catalog as machine-readable data: name, description, and
supports_partition for exactly the three keyable models. The API test
catalog grows to 28 entries; the hardcoded "24" in comments is gone.
238 tests across js and native, zero warnings on 0.1.20261104.

## 0.7.0
## 0.7.0 — 2026-11-03

Registry version: 0.7.0. Twenty-four sequential models (adding the observed-remove set with per-tag add-wins and the one-way flag); the table-driven per-model oracle; randomized differential fuzzing; the 76-case malformed-input sweep; the 22-relation deterministic search-cost gate; serializer pinning; executed examples for every model; lww_map partitioning; the verification coverage matrix; and the deny-warn-aligned verify ladder.

## 0.6.0 — 2026-11-03 — 2026-11-03

Registry version: 0.6.0. Twenty-two sequential models; the table-driven per-model oracle; randomized differential fuzzing; the 72-case malformed-input sweep; the twenty-relation deterministic search-cost gate; serializer pinning; executed examples for every model; lww_map partitioning; the verification coverage matrix; and the deny-warn-aligned verify ladder.

## 0.5.0 — 2026-11-01 — 2026-11-01

Registry version: 0.5.0. Twenty-two sequential models; the table-driven per-model oracle; randomized differential fuzzing; the 62-case malformed-input sweep; the eighteen-relation deterministic search-cost gate; serializer pinning; executed examples for every model; lww_map partitioning; and the deny-warn-aligned verify ladder.

## 0.4.0 — 2026-11-01 — 2026-11-01

Registry version: 0.4.0. Twenty-two sequential models (adding min-register, last-writer-wins register, bounded queue, deque, counting semaphore, reader-writer lock, multiset and priority queue); lww_map partitioning; a table-driven per-model oracle; randomized differential fuzzing across every model; a 62-case malformed-input sweep; a thirteen-relation deterministic search-cost gate; serializer pinning; executed examples for every model; and the deny-warn-aligned verify ladder.

## 0.3.0 — 2026-11-01 — 2026-11-01

Registry version: 0.3.0. Sixteen sequential models (register/CAS, keyed register, FIFO queue, LIFO stack, lock, set, counter with optional steps, key-value map, LWW element-set, monotonic max-register, grow-only set, two-phase set, min-register, last-writer-wins register, bounded queue, deque, counting semaphore, reader-writer lock, multiset and priority queue); map partitioning; a configurable operation ceiling; randomized differential fuzzing, a 51-case malformed-input sweep, a deterministic search-cost gate, serializer pinning across four backends, a table-driven per-model oracle and the one-command verify ladder.

## 0.2.0 — 2026-10-30 — 2026-10-30

Registry version: 0.2.0. Twelve sequential models (register/CAS, keyed register, FIFO queue, LIFO stack, lock, set, counter with optional steps, key-value map, LWW element-set, monotonic max-register, grow-only set, two-phase set); map partitioning; a configurable operation ceiling; randomized differential fuzzing, a 51-case malformed-input sweep, a deterministic search-cost gate, serializer pinning across four backends and a one-command verify ladder.

Two-phase set sequential model: add is ok but never resurrects a removed element, remove reports and requires membership, contains is added-and-not-removed. Permutation-oracle, closure-audit and golden-case coverage included.

Grow-only set sequential model: add is ok and idempotent, contains observes membership, nothing is ever removed. Permutation-oracle, closure-audit and golden-case coverage included.

Monotonic max-register sequential model: write reports ok only at or above the current value and moves the state to the maximum, read observes exactly. Permutation-oracle, closure-audit and golden-case coverage included.

LWW element-set sequential model over string elements: add and remove carry a timestamp and keep the greatest one, contains resolves add-wins on ties; duplicate older writes are idempotent. Permutation-oracle, closure-audit and golden-case coverage included.

Counter steps accept an optional by amount (1..1000000, default 1) on increment and decrement; the oracle generates stepped operations and zero or oversized steps are refused.

Partition extends to map: per-key sub-histories keep the map commands and missing-key semantics, aggregate budget and fully verified global witness merge unchanged; the Python oracle cross-checks 120 map partition equivalences.

Key-value map sequential model (put is ok, get observes the entry or null when missing, remove reports membership and drops the key only when present), with permutation-oracle, closure-audit and golden-case coverage.

max_operations request field raises the per-history ceiling up to 4,096 operations (default 256); refusals name the effective limit and every API operation accepts the field.

Integer counter sequential model (increment/decrement report "ok" and step by one, read observes exactly), with permutation-oracle, closure-audit and golden-case coverage.

Earliest-return-first DFS candidate ordering. LIFO stack, mutual-exclusion lock and membership set sequential models, each with independent Python permutation and closure-audit coverage, golden CLI cases and examples. Delta-debugging counterexample reduction replaces single-deletion scanning: chunked deletions shrink grouped noise with fewer solver checks while the final single-operation pass preserves the 1-minimality contract.

## 0.1.0 2026-10-20

Strict finite histories; register/CAS, keyed-register and FIFO models; bounded DFS; verified witnesses; safe key decomposition and global witness merge; sound single-deletion reduction; finite negative closure certificates and a separate verifier; verdict-aware CLI and async recorder; independent permutation/closure references and four-target CI.
