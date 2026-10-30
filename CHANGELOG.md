# Changelog

## 0.2.0 — 2026-10-30

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
