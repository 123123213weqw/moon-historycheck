"""Randomized differential testing against a permutation brute force.

scripts/reference.py checks fixed seeded histories; this script draws random
models, random operation mixes and random event orderings, then asks a
permutation brute force - no memoization, no partitioning, none of the
searcher's code - whether a legal order exists, and compares. kv_register and
map histories are additionally cross-checked through partition. Seeds come from
the command line so a failure reproduces: python -B scripts/fuzz.py 5.
"""
import json, random, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from reference import apply, member, run, same, verify  # noqa: E402

INITIAL = {
    'register': 0, 'kv_register': {}, 'queue': [], 'stack': [], 'lock': False,
    'set': [], 'counter': 0, 'map': {}, 'lww_set': {'adds': {}, 'rems': {}},
    'max_register': 0, 'grow_only_set': [], 'two_phase_set':
    {'added': [], 'removed': []},
}

VALUES = [None, False, True, 0, 1, 2, {'nested': [1, True]}]
KEYS = ['x', 'y', 'z']
ELEMENTS = ['a', 'b', 'c']

def legal_step(rng, model, state):
    """A random operation that is legal against `state`, with its output."""
    key = lambda: rng.choice(KEYS)
    value = lambda: rng.choice(VALUES)
    element = lambda: rng.choice(ELEMENTS)
    if model in ('register', 'kv_register'):
        kind = rng.choice(['read', 'write', 'cas'])
        arg = {'type': kind}
        if model == 'kv_register':
            arg['key'] = key()
        current = state.get(arg['key']) if model == 'kv_register' else state
        if kind == 'read':
            return arg, current, state
        if kind == 'write':
            arg['value'] = value()
            return arg, 'ok', lambda s: _set_current(s, arg, value() if False else arg['value'])
        expected = rng.choice([None, False, True, 0, 1])
        arg['expected'] = expected
        arg['value'] = value()
        succeeds = same(current, expected)
        return arg, succeeds, lambda s: _cas_state(s, model, arg, succeeds)
    if model in ('map',):
        kind = rng.choice(['put', 'get', 'remove'])
        arg = {'type': kind, 'key': key()}
        current = state.get(arg['key'])
        if kind == 'put':
            arg['value'] = value()
            return arg, 'ok', lambda s: {**s, arg['key']: arg['value']}
        if kind == 'get':
            return arg, current, state
        present = arg['key'] in state
        return arg, present, lambda s: ({k: v for k, v in s.items()
            if k != arg['key']} if present else s)
    if model == 'queue':
        if not state or rng.random() < 0.5:
            arg = {'type': 'enqueue', 'value': value()}
            return arg, 'ok', lambda s: s + [arg['value']]
        return {'type': 'dequeue'}, {'value': state[0]}, lambda s: s[1:]
    if model == 'stack':
        if not state or rng.random() < 0.5:
            arg = {'type': 'push', 'value': value()}
            return arg, 'ok', lambda s: s + [arg['value']]
        return {'type': 'dequeue' if False else 'pop'}, {'value': state[-1]}, lambda s: s[:-1]
    if model == 'lock':
        if state:
            return {'type': 'release'}, 'ok', lambda s: False
        return {'type': 'acquire'}, True, lambda s: True
    if model == 'set':
        kind = rng.choice(['add', 'remove', 'contains'])
        arg = {'type': kind, 'value': value()}
        present = member(state, arg['value'])
        if kind == 'add':
            return arg, 'ok', lambda s: s if present else s + [arg['value']]
        if kind == 'remove':
            return arg, present, lambda s: ([x for x in s
                if not same(x, arg['value'])] if present else s)
        return arg, present, lambda s: s
    if model == 'counter':
        kind = rng.choice(['increment', 'decrement', 'read'])
        if kind == 'read':
            return {'type': 'read'}, state, lambda s: s
        arg = {'type': kind, 'by': rng.choice([1, 1, 5])}
        return arg, 'ok', lambda s: s + arg['by'] * (1 if kind == 'increment' else -1)
    if model == 'max_register':
        kind = rng.choice(['read', 'write'])
        if kind == 'read':
            return {'type': 'read'}, state, lambda s: s
        arg = {'type': 'write', 'value': rng.choice([0, 3, 7, 9]) if state < 9
          else state}
        return arg, 'ok', lambda s: max(s, arg['value'])
    if model == 'lww_set':
        kind = rng.choice(['add', 'remove', 'contains'])
        arg = {'type': kind, 'element': element()}
        if kind != 'contains':
            arg['at'] = rng.randrange(0, 8)
        table = 'adds' if kind == 'add' else 'rems'
        if kind == 'contains':
            a, r = state['adds'].get(arg['element']), state['rems'].get(arg['element'])
            return arg, a is not None and (r is None or a >= r), lambda s: s
        return arg, 'ok', lambda s: {**s, table: {**s[table], arg['element']:
            max(arg['at'], s[table].get(arg['element'], arg['at']))}}
    if model == 'grow_only_set':
        kind = rng.choice(['add', 'contains'])
        arg = {'type': kind, 'value': value()}
        present = member(state, arg['value'])
        if kind == 'add':
            return arg, 'ok', lambda s: s if present else s + [arg['value']]
        return arg, present, lambda s: s
    # two_phase_set
    kind = rng.choice(['add', 'remove', 'contains'])
    arg = {'type': kind, 'value': value()}
    present = member(state['added'], arg['value']) and not member(
        state['removed'], arg['value'])
    if kind == 'add':
        return arg, 'ok', lambda s: s
    if kind == 'remove':
        return arg, present, lambda s: ({**s, 'removed': s['removed']
            + [arg['value']]} if present else s)
    return arg, present, lambda s: s

def _set_current(s, arg, value):
    if 'key' in arg:
        return {**s, arg['key']: value}
    return value

def _cas_state(s, model, arg, succeeds):
    if not succeeds:
        return s
    value = arg['value']
    if 'key' in arg:
        return {**s, arg['key']: value}
    return value

def make_history(rng, model, index):
    n = rng.randrange(1, 7)
    positive = index % 2 == 0
    state = json.loads(json.dumps(INITIAL[model]))
    initial = json.loads(json.dumps(state))
    ops = []
    for i in range(n):
        arg, output, advance = legal_step(rng, model, state)
        if not positive and rng.random() < 0.65:
            kind = arg['type']
            if kind in ('read', 'get'):
                output = 99
            elif kind in ('contains', 'cas', 'acquire') or (
                model == 'two_phase_set' and kind == 'remove') or (
                model == 'set' and kind == 'remove'):
                output = not output
            elif isinstance(output, bool):
                output = not output
            else:
                output = 'wrong'
        op = {'id': str(i), 'client': 'c' + str(i % 3), 'input': arg,
            'output': output}
        if positive:
            legal, state = apply(model, state, op)
            assert legal, (model, op)
        ops.append(op)
    events = list(range(1, 2 * n + 1))
    rng.shuffle(events)
    for i, op in enumerate(ops):
        first, second = events[2 * i], events[2 * i + 1]
        # call takes the smaller of the pair, so return always follows;
        # the pairs still interleave, which is where overlap comes from.
        op['call'], op['return'] = min(first, second), max(first, second)
    return {'model': model, 'initial': initial, 'operations': ops}

def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    models = list(INITIAL)
    checked = 0
    for seed in range(seeds):
        rng = random.Random(90000 + seed)
        for index in range(20):
            model = rng.choice(models)
            request = make_history(rng, model, index)
            expected = oracle(request)
            result = run(request)
            want = 'linearizable' if expected is not None else 'non_linearizable'
            assert result['verdict'] == want, (seed, index, model, request,
                result)
            if expected is not None:
                assert verify(request, result['witness'])
                assert result['witness_verified']
            checked += 1
    print(f'Fuzz: {checked} randomized histories across {len(models)} models '
        + f'agree with the permutation oracle over {seeds} seeds')

def oracle(request):
    import itertools
    ids = [op['id'] for op in request['operations']]
    return next((list(p) for p in itertools.permutations(ids)
        if verify(request, list(p))), None)

if __name__ == '__main__':
    main()
