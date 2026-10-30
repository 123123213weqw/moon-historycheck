"""Malformed-input sweep: every bad request is answered, never crashed.

The oracle in scripts/reference.py only sends well-formed requests, so nothing
here asserts a verdict; the one property a command-line tool must hold is that
structurally malformed input produces exactly one JSON object with verdict
invalid_input and exit 64, rather than a crash, a hang or a stack trace.
"""
import json, subprocess, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/main/main.js'

LONG = 'x' * 257
DEEP = json.dumps({'value': json.loads('[' * 200 + ']' * 200)}) if False else None

def case(label, request):
    return (label, request)

CASES = [
    ('operation wrong type', {'operation': 42}),
    ('unknown operation', {'operation': 'nope', 'model': 'register'}),
    ('model wrong type', {'operation': 'check', 'model': 42}),
    ('model unknown', {'operation': 'check', 'model': 'nope'}),
    ('operations wrong type', {'model': 'register', 'operations': 'nope'}),
    ('operation entry not an object', {'model': 'register', 'operations': [7]}),
    ('missing id', {'model': 'register',
      'operations': [{'client': 'a', 'call': 1, 'input': {'type': 'read'}}]}),
    ('missing client', {'model': 'register',
      'operations': [{'id': 'a', 'call': 1, 'input': {'type': 'read'}}]}),
    ('missing call', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'input': {'type': 'read'}}]}),
    ('missing input', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1}]}),
    ('call fractional', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1.5,
        'input': {'type': 'read'}}]}),
    ('call negative', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': -1,
        'input': {'type': 'read'}}]}),
    ('call huge', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1e400,
        'input': {'type': 'read'}}]}),
    ('return before call', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 5, 'return': 4,
        'input': {'type': 'read'}, 'output': 0}]}),
    ('return equals call', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 5, 'return': 5,
        'input': {'type': 'read'}, 'output': 0}]}),
    ('duplicate ids', {'model': 'register',
      'operations': [
        {'id': 'a', 'client': 'a', 'call': 1, 'input': {'type': 'read'}},
        {'id': 'a', 'client': 'a', 'call': 2, 'input': {'type': 'read'}}]}),
    ('duplicate ordinals', {'model': 'register',
      'operations': [
        {'id': 'a', 'client': 'a', 'call': 1, 'input': {'type': 'read'}},
        {'id': 'b', 'client': 'a', 'call': 1, 'input': {'type': 'read'}}]}),
    ('pending with output', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read'}, 'output': 0}]}),
    ('output without return', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1, 'return': 2,
        'input': {'type': 'read'}}]}),
    ('id too long', {'model': 'register',
      'operations': [{'id': LONG, 'client': 'a', 'call': 1,
        'input': {'type': 'read'}}]}),
    ('empty id', {'model': 'register',
      'operations': [{'id': '', 'client': 'a', 'call': 1,
        'input': {'type': 'read'}}]}),
    ('client missing', {'model': 'register',
      'operations': [{'id': 'a', 'call': 1, 'input': {'type': 'read'}}]}),
    ('unknown request field', {'model': 'register', 'wat': 1, 'operations': []}),
    ('unknown input field', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read', 'wat': 1}}]}),
    ('register with key', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read', 'key': 'x'}}]}),
    ('register write without value', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'write'}}]}),
    ('register unknown kind', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'swap'}}]}),
    ('kv without key', {'model': 'kv_register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read'}}]}),
    ('kv initial not object', {'model': 'kv_register', 'initial': 0,
      'operations': []}),
    ('queue initial not array', {'model': 'queue', 'initial': 0,
      'operations': []}),
    ('queue enqueue without value', {'model': 'queue', 'initial': [],
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'enqueue'}}]}),
    ('counter step zero', {'model': 'counter', 'initial': 0,
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'increment', 'by': 0}}]}),
    ('counter initial not number', {'model': 'counter', 'initial': [],
      'operations': []}),
    ('lock initial not boolean', {'model': 'lock', 'initial': 0,
      'operations': []}),
    ('set initial not array', {'model': 'set', 'initial': {},
      'operations': []}),
    ('map initial not object', {'model': 'map', 'initial': [],
      'operations': []}),
    ('lww initial incomplete', {'model': 'lww_set', 'initial': {'adds': []},
      'operations': []}),
    ('lww at fractional', {'model': 'lww_set',
      'initial': {'adds': {}, 'rems': {}},
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'add', 'element': 'e', 'at': 1.5}}]}),
    ('max_operations zero', {'model': 'register', 'max_operations': 0,
      'operations': []}),
    ('max_operations fractional', {'model': 'register', 'max_operations': 2.5,
      'operations': []}),
    ('max_operations over hard cap', {'model': 'register',
      'max_operations': 5000, 'operations': []}),
    ('max_states over cap', {'model': 'register', 'max_states': 2000000,
      'operations': []}),
    ('max_memo_units negative', {'model': 'register', 'max_memo_units': -1,
      'operations': []}),
    ('partition on register', {'model': 'register', 'partition': True,
      'operations': []}),
    ('partition on queue', {'model': 'queue', 'partition': True,
      'operations': []}),
    ('witness wrong type', {'operation': 'verify', 'model': 'register',
      'witness': 7, 'operations': []}),
    ('certificate wrong type', {'operation': 'verify_certificate',
      'model': 'register', 'certificate': 7, 'operations': []}),
    ('analyze pending model missing', {'operation': 'analyze'}),
    ('deep nesting', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read'}, 'output': json.loads(
          '[' * 200 + ']' * 200)}]}),
    ('string over units', {'model': 'register',
      'operations': [{'id': 'a', 'client': 'a', 'call': 1,
        'input': {'type': 'read'}, 'output': 'y' * 70000}]}),
    ('over 256 operations under default ceiling', {'model': 'register',
      'operations': [{'id': 'o' + str(i), 'client': 'c', 'call': 2 * i + 1,
        'input': {'type': 'read'}} for i in range(257)]}),
]

failures = []
for label, request in CASES:
    try:
        result = subprocess.run(
            ['node', str(CLI), '-'],
            input=json.dumps(request), capture_output=True, text=True,
            encoding='utf-8', timeout=20)
    except subprocess.TimeoutExpired:
        failures.append(label + ': hung')
        continue
    if result.returncode != 64:
        failures.append(label + ': exit ' + str(result.returncode))
        continue
    try:
        parsed = json.loads(result.stdout)
    except Exception:
        failures.append(label + ': stdout is not one JSON object')
        continue
    if not isinstance(parsed, dict) or parsed.get('verdict') != 'invalid_input':
        failures.append(label + ': verdict ' + json.dumps(parsed.get('verdict')))
    if result.stderr.strip():
        failures.append(label + ': wrote to stderr')

print(f'Robustness: {len(CASES)} malformed requests all answered with '
      + 'invalid_input and exit 64')
if failures:
    for failure in failures:
        print('  ' + failure)
    sys.exit(1)
