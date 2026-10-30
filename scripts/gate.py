"""Deterministic search-cost gate: expansion counts may only stay or fall.

Timing varies by machine, so this gate measures work instead of time: for
pinned histories it asserts the exact or bounded expanded-state counts the
search reports. A search-order change that backtracks more shows up here
before any human notices a slowdown, and the numbers are the same on every
backend because exploration order is deterministic.
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

def ops(count, prefix='o', kind_write=True):
    out = []
    for i in range(count):
        out.append({'id': prefix + str(i), 'client': 'c' + str(i % 4),
            'call': 2 * i + 1, 'return': 2 * i + 2,
            'input': {'type': 'write', 'value': i} if kind_write
              else {'type': 'read'}, 'output': 'ok' if kind_write else 0})
    return out

# Serial histories: one expansion per operation, no backtracking at all.
gate = []
for count in (8, 32, 128):
    report = run({'model': 'register', 'initial': 0, 'operations': ops(count)})
    gate.append((f'serial {count}: one expansion per operation',
        report['stats']['expanded_states'] == count, report['stats']))

# Overlap with a fresh read resolves without touching the budget; the same
# history with a stale read is exhaustively rejected, and both costs are pinned.
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
gate.append(('stale read after both writes: exhausted in exactly 5 expansions',
    report['verdict'] == 'non_linearizable'
    and report['stats']['expanded_states'] == 5
    and report['stats']['memo_entries'] == 5, report['stats']))

# Partitioned keys decompose: the aggregate expansion is the sum over keys,
# each of which stays linear.
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

failures = []
for label, held, detail in gate:
    if not held:
        failures.append(label + ': ' + json.dumps(detail))
if failures:
    for failure in failures:
        print('  ' + failure)
    sys.exit(1)
print('Gate: ' + str(len(gate)) + ' deterministic search-cost relations hold '
    + '(serial linearity, concurrent maxima, memoized exhaustion, partition sum)')
