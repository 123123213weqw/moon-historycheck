"""Deterministic search-cost gate: expansion counts may only stay or fall.

Timing varies by machine, so this gate measures work instead of time: for
pinned histories it asserts the exact or bounded expanded-state counts the
search reports, plus the verdict for every model. A search-order change that
backtracks more shows up here before any human notices a slowdown.
"""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/main/main.js'

def run(request):
    result = subprocess.run(['node', str(CLI), '-'],
        input=json.dumps(request), capture_output=True, text=True,
        encoding='utf-8', timeout=60)
    if result.returncode not in (0, 2, 3, 64):
        raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)

def ops(count, prefix='o'):
    out = []
    for i in range(count):
        out.append({'id': prefix + str(i), 'client': 'c' + str(i % 4),
            'call': 2 * i + 1, 'return': 2 * i + 2,
            'input': {'type': 'write', 'value': i}, 'output': 'ok'})
    return out

gate = []
# Serial histories: one expansion per operation, no backtracking at all.
for count in (8, 32, 128):
    report = run({'model': 'register', 'initial': 0, 'operations': ops(count)})
    gate.append((f'serial {count}: one expansion per operation',
        report['stats']['expanded_states'] == count, report['stats']))

# Overlap with a fresh read resolves without touching the budget; the same
# history with a stale read is exhaustively rejected.
fresh = [{'id': 'w0', 'client': 'a', 'call': 1, 'return': 4,
    'input': {'type': 'write', 'value': 1}, 'output': 'ok'},
  {'id': 'w1', 'client': 'b', 'call': 2, 'return': 3,
    'input': {'type': 'write', 'value': 2}, 'output': 'ok'},
  {'id': 'r', 'client': 'c', 'call': 5, 'return': 6,
    'input': {'type': 'read'}, 'output': 2}]
report = run({'model': 'register', 'initial': 0, 'operations': fresh})
gate.append(('concurrent max: found in exactly 5 expansions',
    report['verdict'] == 'linearizable'
    and report['stats']['expanded_states'] == 5, report['stats']))

stale = [{'id': 'w0', 'client': 'a', 'call': 1, 'return': 4,
    'input': {'type': 'write', 'value': 1}, 'output': 'ok'},
  {'id': 'w1', 'client': 'b', 'call': 2, 'return': 3,
    'input': {'type': 'write', 'value': 2}, 'output': 'ok'},
  {'id': 'r', 'client': 'c', 'call': 5, 'return': 6,
    'input': {'type': 'read'}, 'output': 0}]
report = run({'model': 'register', 'initial': 0, 'operations': stale,
  'max_states': 40})
gate.append(('stale read: exhausted in exactly 5 expansions',
    report['verdict'] == 'non_linearizable'
    and report['stats']['expanded_states'] == 5
    and report['stats']['memo_entries'] == 5, report['stats']))

# Partitioned keys decompose: the aggregate expansion is the sum over keys.
keyed = []
for i in range(20):
    keyed.append({'id': 'w' + str(i), 'client': 'a', 'call': 4 * i + 1,
      'return': 4 * i + 2,
      'input': {'type': 'write', 'key': 'k' + str(i), 'value': i},
      'output': 'ok'})
    keyed.append({'id': 'r' + str(i), 'client': 'b', 'call': 4 * i + 3,
      'return': 4 * i + 4,
      'input': {'type': 'read', 'key': 'k' + str(i)}, 'output': i})
report = run({'model': 'kv_register', 'initial': {}, 'operations': keyed,
  'partition': True})
gate.append(('20-key partition: one expansion per operation',
    report['verdict'] == 'linearizable'
    and report['expanded_states'] == 40, report))

# Verdict gates for models whose reports carry no stats block.
def verdict(model, initial, operations, want):
    request = {'model': model, 'initial': initial, 'operations': operations}
    report = run(request)
    gate.append((f'{model}: {want}',
        report['verdict'] == want, report))

verdict('min_register', 7, [
    {'id': 'w1', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'write', 'value': 5}, 'output': 'ok'},
    {'id': 'w2', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'write', 'value': 3}, 'output': 'ok'},
    {'id': 'r', 'client': 'b', 'call': 5, 'return': 6,
     'input': {'type': 'read'}, 'output': 3},
], 'linearizable')
verdict('lww_register', None, [
    {'id': 'w1', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'write', 'value': 1, 'at': 5}, 'output': 'ok'},
    {'id': 'w2', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'write', 'value': 2, 'at': 7}, 'output': 'ok'},
    {'id': 'r', 'client': 'b', 'call': 5, 'return': 6,
     'input': {'type': 'read'}, 'output': 2},
], 'linearizable')
verdict('semaphore', {'permits': 2, 'taken': 0}, [
    {'id': 'a1', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'acquire'}, 'output': True},
    {'id': 'a2', 'client': 'b', 'call': 3, 'return': 4,
     'input': {'type': 'acquire'}, 'output': True},
    {'id': 'r', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'release'}, 'output': 'ok'},
], 'linearizable')
verdict('rwlock', {'readers': 0, 'writer': False}, [
    {'id': 'w', 'client': 'a', 'call': 1, 'return': 4,
     'input': {'type': 'acquire_write'}, 'output': True},
    {'id': 'r', 'client': 'b', 'call': 2, 'return': 3,
     'input': {'type': 'acquire_read'}, 'output': False},
    {'id': 'rw', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'release_write'}, 'output': 'ok'},
], 'linearizable')
verdict('priority_queue', [], [
    {'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'push', 'value': 'x', 'priority': 2}, 'output': 'ok'},
    {'id': 'b', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'push', 'value': 'y', 'priority': 1}, 'output': 'ok'},
    {'id': 'p', 'client': 'c', 'call': 5, 'return': 6,
     'input': {'type': 'pop_min'}, 'output': {'value': 'y'}},
], 'linearizable')
verdict('pncounter', {'p': {}, 'n': {}}, [
    {'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'increment', 'who': 'a', 'by': 2}, 'output': 'ok'},
    {'id': 'b', 'client': 'b', 'call': 3, 'return': 4,
     'input': {'type': 'increment', 'who': 'b', 'by': 3}, 'output': 'ok'},
    {'id': 'r', 'client': 'c', 'call': 5, 'return': 6,
     'input': {'type': 'read'}, 'output': 5},
], 'linearizable')
verdict('bounded_queue', [], [
    {'id': 'e', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'enqueue', 'value': 1}, 'output': 'ok'},
    {'id': 'd', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'dequeue'}, 'output': {'value': 1}},
], 'linearizable')
verdict('deque', [], [
    {'id': 'pf', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'push_front', 'value': 1}, 'output': 'ok'},
    {'id': 'pb', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'push_back', 'value': 2}, 'output': 'ok'},
    {'id': 'p', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'pop_front'}, 'output': {'value': 1}},
], 'linearizable')
verdict('multiset', [], [
    {'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'add', 'value': 5}, 'output': 'ok'},
    {'id': 'a2', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'add', 'value': 5}, 'output': 'ok'},
    {'id': 'c', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'count', 'value': 5}, 'output': 2},
    {'id': 'r', 'client': 'a', 'call': 7, 'return': 8,
     'input': {'type': 'remove', 'value': 5}, 'output': 2},
    {'id': 'c2', 'client': 'a', 'call': 9, 'return': 10,
     'input': {'type': 'count', 'value': 5}, 'output': 1},
], 'linearizable')
verdict('grow_only_set', [], [
    {'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'add', 'value': 1}, 'output': 'ok'},
    {'id': 'a2', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'add', 'value': 1}, 'output': 'ok'},
    {'id': 'c', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'contains', 'value': 1}, 'output': True},
], 'linearizable')
verdict('two_phase_set', {'added': [], 'removed': []}, [
    {'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'add', 'value': 1}, 'output': 'ok'},
    {'id': 'r', 'client': 'a', 'call': 3, 'return': 4,
     'input': {'type': 'remove', 'value': 1}, 'output': True},
    {'id': 'a2', 'client': 'a', 'call': 5, 'return': 6,
     'input': {'type': 'add', 'value': 1}, 'output': 'ok'},
    {'id': 'c', 'client': 'a', 'call': 7, 'return': 8,
     'input': {'type': 'contains', 'value': 1}, 'output': False},
], 'linearizable')
verdict('lww_map', {}, [
    {'id': 's1', 'client': 'a', 'call': 1, 'return': 2,
     'input': {'type': 'set', 'key': 'k', 'value': 1, 'at': 5}, 'output': 'ok'},
    {'id': 's2', 'client': 'b', 'call': 3, 'return': 4,
     'input': {'type': 'set', 'key': 'k', 'value': 2, 'at': 9}, 'output': 'ok'},
    {'id': 'g', 'client': 'c', 'call': 5, 'return': 6,
     'input': {'type': 'get', 'key': 'k'}, 'output': 2},
], 'linearizable')


# The configurable operation ceiling works across models.
ops_258 = [{'id': 'o' + str(i), 'client': 'c' + str(i % 5),
    'call': 2 * i + 1, 'return': 2 * i + 2,
    'input': {'type': 'increment', 'who': 'a', 'by': 1}, 'output': 'ok'}
    for i in range(258)]
request = {'model': 'pncounter', 'initial': {'p': {}, 'n': {}},
    'operations': ops_258, 'max_operations': 258}
report = run(request)
gate.append(('pncounter_258: raised ceiling admits 258 operations',
    report['verdict'] == 'linearizable', report))

failures = []
for label, held, detail in gate:
    if not held:
        failures.append(label + ': ' + json.dumps(detail))
if failures:
    for failure in failures:
        print('  ' + failure)
    sys.exit(1)
print(f'Gate: {len(gate)} deterministic search-cost relations hold across '
    + 'serial linearity, concurrent maxima, memoized exhaustion, partition '
    + 'sums and per-model verdicts')
