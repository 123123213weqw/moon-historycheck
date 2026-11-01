"""Independent permutation oracle and witness replay; Python stdlib only.

Every model is a table entry: the initial state, a legal-step generator for
positive histories, and an apply() that answers one operation against one
state. Adding a model means adding a table entry - the shared conditional
chains this replaces were where three generator defects were planted and
caught, so the dispatch is now structural instead of textual.
"""
import copy, itertools, json, random, subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / '_build/js/debug/build/cmd/main/main.js'

def same(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    return a == b

def member(items, v):
    return any(same(x, v) for x in items)

def without_first(items, v):
    out, skipped = [], False
    for x in items:
        if not skipped and same(x, v):
            skipped = True
        else:
            out.append(x)
    return out

# --- per-model tables ------------------------------------------------------
# Each entry: initial state, apply(state, op) -> (legal, next_state), and
# step(rng, state) -> (arg, output, next_state) drawing one legal operation.

def _reg_step(current, rng, value_pool):
    kind = rng.choice(['read', 'write', 'cas'])
    arg = {'type': kind}
    if kind == 'read':
        return arg, current, current
    if kind == 'write':
        v = rng.choice(value_pool)
        arg['value'] = v
        return arg, 'ok', v
    expected = rng.choice([None, False, True, 0, 1])
    arg['expected'] = expected
    v = rng.choice(value_pool)
    arg['value'] = v
    succeeds = same(current, expected)
    return arg, succeeds, (v if succeeds else current)

def _queue_pop(state):
    return ({'value': state[0]}, state[1:]) if state else ({'empty': True}, state)

def _stack_pop(state):
    return ({'value': state[-1]}, state[:-1]) if state else ({'empty': True}, state)

MODELS = {}

MODELS['register'] = {
    'initial': 0,
    'apply': lambda state, op: _reg_apply_kv(state, op, keyed=False),
    'step': lambda rng, state: _reg_step(state, rng, [None, False, 0, 1, 2, {'nested': [1, True]}]),
}

def _reg_apply_kv(state, op, keyed):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'read':
        return same(output, state), state
    if kind == 'write':
        return (same(output, 'ok'), arg['value'])
    succeeds = same(state, arg['expected'])
    if not same(output, succeeds):
        return False, state
    return True, (arg['value'] if succeeds else state)

MODELS['kv_register'] = {
    'initial': {'x': 0, 'y': 0},
    'apply': lambda state, op: _kv_apply(state, op),
    'step': lambda rng, state: _kv_step(rng, state),
}

def _kv_step(rng, state):
    key = rng.choice(['x', 'y'])
    kind = rng.choice(['read', 'write', 'cas'])
    arg = {'type': kind, 'key': key}
    current = state.get(key)
    if kind == 'read':
        return arg, current, state
    if kind == 'write':
        v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
        arg['value'] = v
        return arg, 'ok', {**state, key: v}
    expected = rng.choice([None, False, True, 0, 1])
    arg['expected'] = expected
    v = rng.choice([None, False, 0, 1, 2])
    arg['value'] = v
    succeeds = same(current, expected)
    return arg, succeeds, ({**state, key: v} if succeeds else state)

def _kv_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    key, current = arg['key'], state.get(arg['key'])
    if kind == 'read':
        return same(output, current), state
    if kind == 'write':
        return (same(output, 'ok'), {**state, key: arg['value']})
    succeeds = same(current, arg['expected'])
    if not same(output, succeeds):
        return False, state
    return True, ({**state, key: arg['value']} if succeeds else state)

MODELS['map'] = {
    'initial': {},
    'apply': lambda state, op: _map_apply(state, op),
    'step': lambda rng, state: _map_step(rng, state),
}

def _map_step(rng, state):
    kind = rng.choice(['put', 'get', 'remove'])
    arg = {'type': kind, 'key': rng.choice(['x', 'y', 'z'])}
    if kind == 'put':
        arg['value'] = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
        return arg, 'ok', {**state, arg['key']: arg['value']}
    present = arg['key'] in state
    if kind == 'get':
        return arg, state.get(arg['key']) if present else None, state
    return arg, present, ({k: v for k, v in state.items() if k != arg['key']}
        if present else state)

def _map_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    key = arg['key']
    if kind == 'put':
        return (same(output, 'ok'), {**state, key: arg['value']})
    present = key in state
    if kind == 'get':
        want = state.get(key) if present else None
        return same(output, want), state
    if not same(output, present):
        return False, state
    return True, ({k: v for k, v in state.items() if k != key} if present else state)

MODELS['counter'] = {
    'initial': 0,
    'apply': lambda state, op: _counter_apply(state, op),
    'step': lambda rng, state: _counter_step(rng, state),
}

def _counter_step(rng, state):
    kind = rng.choice(['increment', 'decrement', 'read'])
    if kind == 'read':
        return {'type': 'read'}, state, state
    arg = {'type': kind, 'by': rng.choice([1, 1, 5])}
    return arg, 'ok', state + arg['by'] * (1 if kind == 'increment' else -1)

def _counter_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind in ('increment', 'decrement'):
        if not same(output, 'ok'):
            return False, state
        return True, state + arg.get('by', 1) * (1 if kind == 'increment' else -1)
    return same(output, state), state

MODELS['max_register'] = {
    'initial': 0,
    'apply': lambda state, op: _max_apply(state, op),
    'step': lambda rng, state: _max_step(rng, state),
}

def _max_step(rng, state):
    kind = rng.choice(['read', 'write'])
    if kind == 'read':
        return {'type': 'read'}, state, state
    pool = [v for v in [0, 3, 5, 9] if v >= state] or [state]
    v = rng.choice(pool)
    return {'type': 'write', 'value': v}, 'ok', max(state, v)

def _max_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'write':
        if not same(output, 'ok'):
            return False, state
        v = arg['value']
        if v > state:
            return True, v
        if v == state:
            return True, state
        return False, state
    return same(output, state), state

MODELS['lock'] = {
    'initial': False,
    'apply': lambda state, op: _lock_apply(state, op),
    'step': lambda rng, state: _lock_step(rng, state),
}

def _lock_step(rng, state):
    if state:
        return {'type': 'release'}, 'ok', False
    return {'type': 'acquire'}, True, True

def _lock_apply(state, op):
    kind, output = op['input']['type'], op['output']
    if kind == 'acquire':
        return (same(output, not state), True)
    if not same(output, 'ok'):
        return False, state
    return (True, False) if state else (False, state)

MODELS['queue'] = {
    'initial': [],
    'apply': lambda state, op: _queue_apply(state, op),
    'step': lambda rng, state: _queue_step(rng, state),
}

def _queue_step(rng, state):
    if not state or rng.random() < 0.5:
        v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
        return {'type': 'enqueue', 'value': v}, 'ok', state + [v]
    output, next_state = _queue_pop(state)
    return {'type': 'dequeue'}, output, next_state

def _queue_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'enqueue':
        if not same(output, 'ok'):
            return False, state
        return True, state + [arg['value']]
    want, next_state = _queue_pop(state)
    return (same(output, want), next_state)

MODELS['stack'] = {
    'initial': [],
    'apply': lambda state, op: _stack_apply(state, op),
    'step': lambda rng, state: _stack_step(rng, state),
}

def _stack_step(rng, state):
    if not state or rng.random() < 0.5:
        v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
        return {'type': 'push', 'value': v}, 'ok', state + [v]
    output, next_state = _stack_pop(state)
    return {'type': 'pop'}, output, next_state

def _stack_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'push':
        if not same(output, 'ok'):
            return False, state
        return True, state + [arg['value']]
    want, next_state = _stack_pop(state)
    return (same(output, want), next_state)

MODELS['set'] = {
    'initial': [],
    'apply': lambda state, op: _set_apply(state, op),
    'step': lambda rng, state: _set_step(rng, state),
}

def _set_step(rng, state):
    kind = rng.choice(['add', 'remove', 'contains'])
    arg = {'type': kind, 'value': rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])}
    present = member(state, arg['value'])
    if kind == 'add':
        return arg, 'ok', state if present else state + [arg['value']]
    if kind == 'remove':
        return arg, present, (without_first(state, arg['value']) if present else state)
    return arg, present, state

def _set_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    v = arg['value']
    if kind == 'add':
        if not same(output, 'ok'):
            return False, state
        return True, state if member(state, v) else state + [copy.deepcopy(v)]
    present = member(state, v)
    if not same(output, present):
        return False, state
    return True, (without_first(state, v) if kind == 'remove' and present else state)

MODELS['grow_only_set'] = {
    'initial': [],
    'apply': lambda state, op: _gset_apply(state, op),
    'step': lambda rng, state: _gset_step(rng, state),
}

def _gset_step(rng, state):
    kind = rng.choice(['add', 'contains'])
    arg = {'type': kind, 'value': rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])}
    present = member(state, arg['value'])
    if kind == 'add':
        return arg, 'ok', state if present else state + [arg['value']]
    return arg, present, state

def _gset_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    v = arg['value']
    if kind == 'add':
        if not same(output, 'ok'):
            return False, state
        return True, state if member(state, v) else state + [copy.deepcopy(v)]
    return same(output, member(state, v)), state

MODELS['two_phase_set'] = {
    'initial': {'added': [], 'removed': []},
    'apply': lambda state, op: _2p_apply(state, op),
    'step': lambda rng, state: _2p_step(rng, state),
}

def _2p_step(rng, state):
    kind = rng.choice(['add', 'remove', 'contains'])
    arg = {'type': kind, 'value': rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])}
    present = member(state['added'], arg['value']) and not member(state['removed'], arg['value'])
    if kind == 'add':
        return arg, 'ok', state
    if kind == 'remove':
        return arg, present, ({**state, 'removed': state['removed'] + [arg['value']]}
            if present else state)
    return arg, present, state

def _2p_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    v = arg['value']
    if kind == 'add':
        if not same(output, 'ok'):
            return False, state
        if not member(state['added'], v):
            state['added'].append(copy.deepcopy(v))
        return True, state
    present = member(state['added'], v) and not member(state['removed'], v)
    if not same(output, present):
        return False, state
    if kind == 'remove' and present:
        state['removed'].append(copy.deepcopy(v))
    return True, state

MODELS['priority_queue'] = {
    'initial': [],
    'apply': lambda state, op: _pq_apply(state, op),
    'step': lambda rng, state: _pq_step(rng, state),
}

def _pq_step(rng, state):
    if state and rng.random() < 0.5:
        # Pop the smallest priority, first-inserted among ties.
        best = 0
        for i in range(1, len(state)):
            if state[i]['priority'] < state[best]['priority']:
                best = i
        victim = state[best]
        remaining = [e for j, e in enumerate(state) if j != best]
        return ({'type': 'pop_min'}, {'value': victim['value']}, remaining)
    return ({'type': 'push', 'value': rng.choice([None, False, 0, 1, 2]),
        'priority': rng.randrange(0, 4)}, 'ok',
        state + [{'value': None, 'priority': 0}])

def _pq_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'push':
        if not same(output, 'ok'):
            return False, state
        return True, state + [{'value': copy.deepcopy(arg['value']),
            'priority': arg['priority']}]
    if not state:
        return same(output, {'empty': True}), state
    best = 0
    for i in range(1, len(state)):
        if state[i]['priority'] < state[best]['priority']:
            best = i
    if not same(output, {'value': state[best]['value']}):
        return False, state
    return True, [e for j, e in enumerate(state) if j != best]

MODELS['lww_map'] = {
    'initial': {},
    'apply': lambda state, op: _lmap_apply(state, op),
    'step': lambda rng, state: _lmap_step(rng, state),
}

def _lmap_step(rng, state):
    kind = rng.choice(['set', 'get'])
    key = rng.choice(['k1', 'k2', 'k3'])
    if kind == 'get':
        entry = state.get(key)
        want = entry['value'] if entry else None
        return {'type': 'get', 'key': key}, want, state
    at = rng.randrange(0, 10)
    dominated = key in state and state[key]['at'] >= at
    arg = {'type': 'set', 'key': key, 'value': rng.choice([None, False, 0, 1, 2]), 'at': at}
    if dominated:
        return arg, 'ok', state
    return arg, 'ok', {**state, key: {'value': arg['value'], 'at': at}}

def _lmap_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    key = arg['key']
    if kind == 'set':
        if not same(output, 'ok'):
            return False, state
        at = arg['at']
        dominated = key in state and state[key]['at'] >= at
        if dominated:
            return True, state
        return True, {**state, key: {'value': copy.deepcopy(arg['value']), 'at': at}}
    entry = state.get(key)
    want = entry['value'] if entry else None
    return same(output, want), state

MODELS['semaphore'] = {
    'initial': {'permits': 2, 'taken': 0},
    'apply': lambda state, op: _sem_apply(state, op),
    'step': lambda rng, state: _sem_step(rng, state),
}

def _sem_step(rng, state):
    if state['taken'] < state['permits'] or rng.random() < 0.5:
        if state['taken'] < state['permits']:
            return {'type': 'acquire'}, True, {**state,
                'taken': state['taken'] + 1}
        return {'type': 'acquire'}, False, state
    return {'type': 'release'}, 'ok', {**state, 'taken': state['taken'] - 1}

def _sem_apply(state, op):
    kind, output = op['input']['type'], op['output']
    if kind == 'acquire':
        if state['taken'] < state['permits']:
            return (same(output, True), {**state, 'taken': state['taken'] + 1})
        return same(output, False), state
    if not same(output, 'ok') or state['taken'] <= 0:
        return False, state
    return True, {**state, 'taken': state['taken'] - 1}

MODELS['rwlock'] = {
    'initial': {'readers': 0, 'writer': False},
    'apply': lambda state, op: _rw_apply(state, op),
    'step': lambda rng, state: _rw_step(rng, state),
}

def _rw_step(rng, state):
    kind = rng.choice(['acquire_read', 'release_read', 'acquire_write',
        'release_write'])
    if kind == 'acquire_read':
        blocked = state['writer']
        return ({'type': kind}, not blocked, ({**state,
            'readers': state['readers'] + 1} if not blocked else state))
    if kind == 'release_read':
        if state['readers'] <= 0:
            # Nothing to release: an ok there cannot replay, so draw a
            # different operation instead (the generator must stay legal).
            return _rw_step(rng, state)
        return ({'type': kind}, 'ok', {**state,
            'readers': state['readers'] - 1})
    if kind == 'acquire_write':
        blocked = state['writer'] or state['readers'] > 0
        return ({'type': kind}, not blocked, ({**state, 'writer': True}
            if not blocked else state))
    if not state['writer']:
        return _rw_step(rng, state)
    return ({'type': kind}, 'ok', {**state, 'writer': False})

def _rw_apply(state, op):
    kind, output = op['input']['type'], op['output']
    if kind == 'acquire_read':
        if state['writer']:
            return same(output, False), state
        return (same(output, True), {**state,
            'readers': state['readers'] + 1})
    if kind == 'release_read':
        if state['readers'] <= 0:
            return False, state
        return (same(output, 'ok'), {**state,
            'readers': state['readers'] - 1})
    if kind == 'acquire_write':
        blocked = state['writer'] or state['readers'] > 0
        if blocked:
            return same(output, False), state
        return (same(output, True), {**state, 'writer': True})
    if not state['writer']:
        return False, state
    return (same(output, 'ok'), {**state, 'writer': False})

MODELS['pncounter'] = {
    'initial': {'p': {}, 'n': {}},
    'apply': lambda state, op: _pnc_apply(state, op),
    'step': lambda rng, state: _pnc_step(rng, state),
}

def _pnc_step(rng, state):
    kind = rng.choice(['increment', 'decrement', 'read'])
    who = rng.choice(['a', 'b', 'c'])
    if kind == 'read':
        total = sum(state['p'].values()) - sum(state['n'].values())
        return {'type': 'read'}, total, state
    by = rng.choice([1, 2, 5])
    table = 'p' if kind == 'increment' else 'n'
    return ({'type': kind, 'who': who, 'by': by}, 'ok',
        {**state, table: {**state[table], who: state[table].get(who, 0) + by}})

def _pnc_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'read':
        total = sum(state['p'].values()) - sum(state['n'].values())
        return same(output, total), state
    who, by = arg['who'], arg['by']
    if not same(output, 'ok'):
        return False, state
    table = 'p' if kind == 'increment' else 'n'
    return True, {**state, table: {**state[table], who: state[table].get(who, 0) + by}}

MODELS['multiset'] = {
    'initial': [],
    'apply': lambda state, op: _ms_apply(state, op),
    'step': lambda rng, state: _ms_step(rng, state),
}

def _ms_step(rng, state):
    kind = rng.choice(['add', 'remove', 'count'])
    v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
    copies = sum(1 for x in state if same(x, v))
    if kind == 'add':
        return {'type': 'add', 'value': v}, 'ok', state + [copy.deepcopy(v)]
    if kind == 'remove':
        return ({'type': 'remove', 'value': v}, copies,
            [x for x in state if not same(x, v)] if copies else state)
    return {'type': 'count', 'value': v}, copies, state

def _ms_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    v = arg['value']
    copies = sum(1 for x in state if same(x, v))
    if kind == 'add':
        if not same(output, 'ok'):
            return False, state
        return True, state + [copy.deepcopy(v)]
    if not same(output, copies):
        return False, state
    if kind == 'remove' and copies:
        return True, [x for x in state if not same(x, v)]
    return True, state

BOUNDED_QUEUE_CAPACITY = 3

MODELS['bounded_queue'] = {
    'initial': [],
    'apply': lambda state, op: _bq_apply(state, op),
    'step': lambda rng, state: _bq_step(rng, state),
}

def _bq_step(rng, state):
    # A full queue observes false on enqueue until a dequeue happens; the
    # generator must never draw an ok there, because that verdict cannot
    # replay on the positive path.
    full = len(state) >= BOUNDED_QUEUE_CAPACITY
    if not full or rng.random() < 0.5:
        v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
        output = False if full else 'ok'
        return {'type': 'enqueue', 'value': v}, output, (state if full else state + [v])
    want, next_state = ({'value': state[0]}, state[1:]) if state else ({'empty': True}, state)
    return {'type': 'dequeue'}, want, next_state

def _bq_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'enqueue':
        if len(state) >= BOUNDED_QUEUE_CAPACITY:
            return same(output, False), state
        if not same(output, 'ok'):
            return False, state
        return True, state + [copy.deepcopy(arg['value'])]
    want = {'value': state[0]} if state else {'empty': True}
    if not same(output, want):
        return False, state
    return True, state[1:] if state else state

MODELS['deque'] = {
    'initial': [],
    'apply': lambda state, op: _deque_apply(state, op),
    'step': lambda rng, state: _deque_step(rng, state),
}

def _deque_step(rng, state):
    push = rng.random() < 0.5
    v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
    if push:
        front = rng.random() < 0.5
        kind = 'push_front' if front else 'push_back'
        arg = {'type': kind, 'value': v}
        return arg, 'ok', ([v] + state if front else state + [v])
    if not state:
        return {'type': 'pop_front'}, {'empty': True}, state
    front = rng.random() < 0.5
    kind = 'pop_front' if front else 'pop_back'
    return {'type': kind}, {'value': state[0] if front else state[-1]}, (
        state[1:] if front else state[:-1])

def _deque_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'push_front':
        return (same(output, 'ok'), [copy.deepcopy(arg['value'])] + state)
    if kind == 'push_back':
        return (same(output, 'ok'), state + [copy.deepcopy(arg['value'])])
    if not state:
        return same(output, {'empty': True}), state
    if kind == 'pop_front':
        want = {'value': state[0]}
        if not same(output, want):
            return False, state
        return True, state[1:]
    want = {'value': state[-1]}
    if not same(output, want):
        return False, state
    return True, state[:-1]

MODELS['min_register'] = {
    'initial': 0,
    'apply': lambda state, op: _minreg_apply(state, op),
    'step': lambda rng, state: _minreg_step(rng, state),
}

def _minreg_step(rng, state):
    kind = rng.choice(['read', 'write'])
    if kind == 'read':
        return {'type': 'read'}, state, state
    pool = [v for v in [0, 3, 5, 9] if v <= state] or [state]
    v = rng.choice(pool)
    return {'type': 'write', 'value': v}, 'ok', min(state, v)

def _minreg_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'write':
        if not same(output, 'ok'):
            return False, state
        v = arg['value']
        if v < state:
            return True, v
        if v == state:
            return True, state
        return False, state
    return same(output, state), state

MODELS['lww_register'] = {
    'initial': None,
    'apply': lambda state, op: _lwwreg_apply(state, op),
    'step': lambda rng, state: _lwwreg_step(rng, state),
}

def _lwwreg_step(rng, state):
    kind = rng.choice(['read', 'write'])
    if kind == 'read':
        current_at = -1.0 if state is None else state['at']
        return {'type': 'read'}, (state['value'] if state is not None else None), state
    at = rng.randrange(0, 10)
    # Only strictly newer timestamps can replay, so draw above the current one.
    floor = 0 if state is None else state['at'] + 1
    at = rng.randrange(floor, max(floor + 1, 11))
    v = rng.choice([None, False, 0, 1, 2, {'nested': [1, True]}])
    return {'type': 'write', 'value': v, 'at': at}, 'ok', {'value': v, 'at': at}

def _lwwreg_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    if kind == 'write':
        if not same(output, 'ok'):
            return False, state
        at = arg['at']
        if state is None or at > state['at']:
            return True, {'value': copy.deepcopy(arg['value']), 'at': at}
        return False, state
    want = state['value'] if state is not None else None
    return same(output, want), state

MODELS['lww_set'] = {
    'initial': {'adds': {}, 'rems': {}},
    'apply': lambda state, op: _lww_apply(state, op),
    'step': lambda rng, state: _lww_step(rng, state),
}

def _lww_step(rng, state):
    kind = rng.choice(['add', 'remove', 'contains'])
    arg = {'type': kind, 'element': rng.choice(['a', 'b', 'c'])}
    if kind != 'contains':
        arg['at'] = rng.randrange(0, 8)
    table = 'adds' if kind == 'add' else 'rems'
    if kind == 'contains':
        a, r = state['adds'].get(arg['element']), state['rems'].get(arg['element'])
        return arg, a is not None and (r is None or a >= r), state
    cur = state[table].get(arg['element'])
    newer = cur is None or arg['at'] >= cur
    return arg, 'ok', ({**state, table: {**state[table], arg['element']: arg['at']}}
        if newer else state)

def _lww_apply(state, op):
    arg, kind, output = op['input'], op['input']['type'], op['output']
    e, t = arg['element'], arg.get('at')
    if kind in ('add', 'remove'):
        if not same(output, 'ok'):
            return False, state
        table = 'adds' if kind == 'add' else 'rems'
        cur = state[table].get(e)
        if cur is None or t >= cur:
            state[table][e] = t
        return True, state
    a, r = state['adds'].get(e), state['rems'].get(e)
    return same(output, a is not None and (r is None or a >= r)), state

# --- shared entry points -----------------------------------------------------

def apply(model, state, op):
    """One operation against one state; the table dispatches."""
    return MODELS[model]['apply'](copy.deepcopy(state), op)

def run(request):
    process = subprocess.run(['node', str(CLI), '-'],
        input=json.dumps(request), capture_output=True, text=True,
        encoding='utf-8', timeout=60)
    if not process.stdout:
        raise AssertionError(process.stderr)
    result = json.loads(process.stdout)
    expected = {'non_linearizable': 2, 'invalid_witness': 2, 'invalid_certificate': 2,
        'unknown': 3, 'invalid_input': 64}.get(result.get('verdict'), 0)
    assert process.returncode == expected, (process.returncode, result, process.stderr)
    return result

def verify(request, ids):
    ops = request['operations']
    by_id = {op['id']: op for op in ops}
    if len(ids) != len(ops) or set(ids) != set(by_id):
        return False
    order = {id: i for i, id in enumerate(ids)}
    if any(a.get('return', 1 << 53) < b['call'] and order[a['id']] >= order[b['id']]
           for a in ops for b in ops):
        return False
    state = copy.deepcopy(request['initial'])
    for id in ids:
        legal, state = apply(request['model'], state, by_id[id])
        if not legal:
            return False
    return True

def oracle(request):
    # No memoization, partitioning, or production predecessor code.
    return next((list(p) for p in itertools.permutations(op['id'] for op in
        request['operations']) if verify(request, p)), None)

def generated(rng, model, index):
    n = rng.randrange(1, 7)
    positive = index % 2 == 0
    state = copy.deepcopy(MODELS[model]['initial'])
    initial = copy.deepcopy(state)
    ops = []
    for i in range(n):
        arg, output, next_state = MODELS[model]['step'](rng, state)
        if not positive and rng.random() < 0.65:
            kind = arg['type']
            if kind in ('read', 'get'):
                output = 99
            elif isinstance(output, bool):
                output = not output
            elif kind == 'cas':
                output = not output
            else:
                output = 'wrong'
        op = {'id': str(i), 'client': 'c' + str(i % 3), 'input': arg,
            'output': output}
        if positive:
            legal, state = apply(model, state, op)
            assert legal, (model, op)
        ops.append(op)
    # Event ordinals: every third negative history gets its call/return pairs
    # redrawn as an interleaved legal schedule; everything else keeps the
    # concurrent (overlapping) or serial pattern the old generator used.
    for i, op in enumerate(ops):
        if index % 3 != 0:
            op["call"] = i + 1
            op["return"] = n + i + 1
        else:
            op["call"] = 2 * i + 1
            op["return"] = 2 * i + 2
    if not positive and index % 3 == 1:
        events = []
        unstarted = list(range(n))
        active = []
        ordinal = 0
        while unstarted or active:
            ordinal += 1
            if unstarted and (not active or rng.random() < 0.5):
                i = unstarted.pop(rng.randrange(len(unstarted)))
                active.append(i)
                ops[i]['call'] = ordinal
            else:
                i = active.pop(rng.randrange(len(active)))
                ops[i]['return'] = ordinal
    rng.shuffle(ops)
    return {'model': model, 'initial': initial, 'operations': ops}

def main():
    rng = random.Random(20261020)
    checked = 0
    partitioned = 0
    for model in sorted(MODELS):
        for index in range(120):
            request = generated(rng, model, index)
            expected = oracle(request)
            result = run(request)
            assert result['verdict'] == ('linearizable' if expected is not None
                else 'non_linearizable'), (request, result, expected)
            if expected is not None:
                assert verify(request, result['witness']) and result['witness_verified']
                assert run({**request, 'operation': 'verify',
                    'witness': result['witness']})['valid']
                bad = result['witness'][:-1]
                assert not run({**request, 'operation': 'verify',
                    'witness': bad})['valid']
            else:
                assert result['complete_search']
            if model in ('kv_register', 'map', 'lww_map'):
                part = run({**request, 'partition': True})
                assert part['verdict'] == result['verdict']
                if expected is not None:
                    assert verify(request, part['witness'])
                partitioned += 1
            checked += 1
        print(model, '120 independent permutation checks passed', flush=True)
    reductions = 0
    for index in range(20):
        ops = []
        for i in range(3):
            ops.append({'id': 'noise' + str(i), 'client': 'a', 'call': i * 2 + 1,
                'return': i * 2 + 2, 'input': {'type': 'read'}, 'output': 0})
        ops += [{'id': 'write', 'client': 'a', 'call': 7, 'return': 8,
            'input': {'type': 'write', 'value': index + 1}, 'output': 'ok'},
            {'id': 'stale', 'client': 'b', 'call': 9, 'return': 10,
            'input': {'type': 'read'}, 'output': 0}]
        request = {'model': 'register', 'initial': 0, 'operations': ops}
        result = run({**request, 'operation': 'reduce'})
        reduced = result['history']
        assert oracle(reduced) is None and result['reduction_complete']
        for i in range(len(reduced['operations'])):
            assert oracle({**reduced, 'operations': reduced['operations'][:i]
                + reduced['operations'][i + 1:]}) is not None
        reductions += 1
    print(f'Oracle totals: {checked} histories, {partitioned} partition '
        + 'equivalence checks, 20 sound 1-minimal reductions; returned '
        + 'witnesses and omitted witnesses checked', flush=True)

if __name__ == '__main__':
    main()
