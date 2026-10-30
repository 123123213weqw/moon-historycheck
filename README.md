# Moon HistoryCheck

Bounded linearizability checking for concurrent operation histories, implemented in MoonBit. Register/CAS, independent keyed registers, FIFO queues, LIFO stacks, mutual-exclusion locks, membership sets, integer counters, key-value maps, timestamped LWW sets and monotonic max-registers have executable sequential models. Results distinguish a verified legal ordering, an exhaustive rejection, an unknown result and malformed input.

- Owner: `123123213weqw`
- Module: `123123213weqw/moon_historycheck@0.1.0`
- License: Apache-2.0
- New project: no inherited FindCore code, releases or commit counts.

## Implemented

1. Strict identities, recorder ordinals, model inputs and resource options. Unresolved operations return unknown.
2. Precedence-aware DFS with full selected-set/model-state memoization and earliest-return-first candidate ordering. A search cut is never an impossibility proof.
3. A witness verifier recomputes pairwise real-time obligations and replays the complete ordering.
4. Independent-key decomposition with an aggregate state budget and fully verified global witness merge.
5. Delta-debugging counterexample reduction with chunked operation deletion; completion still proves 1-minimality under single-operation deletion, and unknown subresults never justify a deletion.
6. A separate breadth-first closed-state search emits finite rejection certificates. A verifier checks initial binding, every legal enabled successor, states, terminal exclusion and reachability without trusting the generator's predecessor graph.
7. Verdict-aware CLI, examples and an actual async-call recorder with a controlled stale-read demo.

The result applies only to the supplied finite history and supported model. A valid certificate is a runtime-checkable finite closure argument, not an SMT proof of the implementation or all future executions of the tested system.

## Install

```sh
moon add 123123213weqw/moon_historycheck@0.1.0
```

Consumer moon.pkg:

```moonbit
import {
  "123123213weqw/moon_historycheck" @historycheck,
}
```

```moonbit
fn inspect_history(request : Json) -> Json {
  @historycheck.execute(request)
}
```

The semantic-value interface is run(Value) -> Value. from_json, Value::to_json and Value::canonical are public. Exact exports: [pkg.generated.mbti](pkg.generated.mbti).

## Build and examples

Use MoonBit and Node.js 24. The core supports js, wasm, wasm-gc and native; the file/stdin adapter and recorder require Node.

```sh
moon update
moon build --target js
node _build/js/debug/build/cmd/main/main.js examples/overlap.json
node _build/js/debug/build/cmd/main/main.js examples/stale.json
node _build/js/debug/build/cmd/main/main.js examples/reduce.json
```

The last two examples deliberately report a counterexample and exit **2**. Status 0 means a positive or analysis result, 2 a definite rejection or invalid witness/certificate, 3 unknown, 64 invalid input.

## Verification

```sh
moon test --target js
moon test --target wasm
moon test --target wasm-gc
moon test --target native  # C compiler required
moon fmt --check
moon info
python -B scripts/fixtures.py --check
moon build --target js
node scripts/check.mjs
python -B scripts/reference.py
python -B scripts/proof_reference.py
python -B scripts/scale.py
node scripts/record-demo.mjs /YOUR/SCRATCH/DIRECTORY
python -B scripts/stats.py
```

34 manual test declarations plus 99 generated golden API tests make 133 declarations. The same 99 golden cases also run through the CLI; they are repeated entry-point checks, not 232 independent requirements. The independent Python oracle checks 1200 histories, 240 partition equivalence cases and 20 reductions. A separate closure audit checks 300 histories: 134 negative certificates and 166 positive witnesses, including tampering rejection. Tests are deterministic synthetic data. The async recorder runs controlled in-process services, not a production database.

## Contract and limits

Every operation has id, client, call, optional return, input and, when completed, output. Call and return are globally unique exact nonnegative recorder ordinals at most 2^53-1. Return follows call. Do not substitute unsynchronized wall clocks. Client is attribution metadata and does not invent order between overlapping calls. Unknown timeout completion must be represented as pending, with no return/output, rather than assumed to have failed.

At most 256 operations by default; a request may raise its own ceiling up to 4096 with max_operations. Values use finite Double and structural JSON equality, not arbitrary-precision decimals. Default budgets: 20,000 expanded states, 4,096 memo entries, 1,000,000 state-key units. Hard configurable maxima: 1,000,000 states, 200,000 entries, 16,000,000 units. Units use MoonBit String.length and are not total heap bytes or a wall-clock deadline. Reduction defaults to 200 checks (maximum 2,000), including the initial check, with one aggregate state budget. Certificates cap their graph at 4,096 nodes.

See [API and models](docs/api.md), [engineering choices](docs/design.md), [boundaries](docs/boundaries.md) and [source attribution](THIRD_PARTY.md). The [reference proposal](docs/proposal.md) records implemented scope. Competition acceptance and a registration receipt are separate from repository/package publication.
