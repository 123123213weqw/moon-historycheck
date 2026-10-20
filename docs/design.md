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
