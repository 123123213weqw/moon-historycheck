"""Independent permutation oracle and witness replay; Python stdlib only."""
import copy,itertools,json,random,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
CLI=ROOT/'_build/js/debug/build/cmd/main/main.js'

def same(a,b):
    if isinstance(a,bool) or isinstance(b,bool):return type(a) is type(b) and a==b
    if isinstance(a,(int,float)) and isinstance(b,(int,float)):return a==b
    if type(a) is not type(b):return False
    if isinstance(a,list):return len(a)==len(b) and all(same(x,y) for x,y in zip(a,b))
    if isinstance(a,dict):return a.keys()==b.keys() and all(same(a[k],b[k]) for k in a)
    return a==b

def member(items,v):
    # Structural membership: Python's == would conflate True and 1.
    return any(same(x,v) for x in items)

def without_first(items,v):
    out=[];skipped=False
    for x in items:
        if not skipped and same(x,v):skipped=True
        else:out.append(x)
    return out

def apply(model,state,op):
    state=copy.deepcopy(state);arg=op['input'];kind=arg['type'];output=op['output']
    if model=='queue':
        if kind=='enqueue':
            if not same(output,'ok'):return False,state
            state.append(arg['value']);return True,state
        expected={'value':state[0]} if state else {'empty':True}
        if not same(output,expected):return False,state
        return True,state[1:] if state else state
    if model=='stack':
        if kind=='push':
            if not same(output,'ok'):return False,state
            state.append(arg['value']);return True,state
        expected={'value':state[-1]} if state else {'empty':True}
        if not same(output,expected):return False,state
        return True,state[:-1] if state else state
    if model=='lock':
        if kind=='acquire':
            if not same(output,not state):return False,state
            return True,True
        if not same(output,'ok'):return False,state
        return (True,not state) if state else (False,state)
    if model=='set':
        v=arg['value']
        if kind=='add':
            if not same(output,'ok'):return False,state
            if not member(state,v):state=state+[copy.deepcopy(v)]
            return True,state
        present=member(state,v)
        if not same(output,present):return False,state
        if kind=='remove' and present:state=without_first(state,v)
        return True,state
    if model=='max_register':
        if kind=='write':
            if not same(output,'ok'):return False,state
            v=arg['value']
            if not isinstance(v,(int,float)) or isinstance(v,bool):return False,state
            if v>state:return True,v
            if v==state:return True,state
            return False,state
        if not same(output,state):return False,state
        return True,state
    if model=='lww_set':
        e=arg['element'];t=arg.get('at')
        if kind in ('add','remove'):
            if not same(output,'ok'):return False,state
            table='adds' if kind=='add' else 'rems'
            cur=state[table].get(e)
            if cur is None or t>=cur:state[table][e]=t
            return True,state
        a=state['adds'].get(e);r=state['rems'].get(e)
        expected=a is not None and (r is None or a>=r)
        if not same(output,expected):return False,state
        return True,state
    if model=='map':
        key=arg['key'];present=key in state
        if kind=='put':
            if not same(output,'ok'):return False,state
            state[key]=copy.deepcopy(arg['value']);return True,state
        if kind=='get':
            expected=copy.deepcopy(state[key]) if present else None
            if not same(output,expected):return False,state
            return True,state
        if not same(output,present):return False,state
        if present:del state[key]
        return True,state
    if model=='counter':
        if kind in ('increment','decrement'):
            if not same(output,'ok'):return False,state
            step=arg.get('by',1)
            return True,state+(step if kind=='increment' else -step)
        if not same(output,state):return False,state
        return True,state
    key=arg.get('key');current=state.get(key) if model=='kv_register' else state
    next_value=current
    if kind=='read':legal=same(output,current)
    elif kind=='write':legal=same(output,'ok');next_value=arg['value']
    else:
        succeeds=same(current,arg['expected']);legal=same(output,succeeds)
        if succeeds:next_value=arg['value']
    if model=='kv_register':
        if not same(current,next_value):state[key]=next_value
    else:state=next_value
    return legal,state

def verify(request,ids):
    ops=request['operations'];by_id={op['id']:op for op in ops}
    if len(ids)!=len(ops) or set(ids)!=set(by_id):return False
    order={id:i for i,id in enumerate(ids)}
    if any(a['return']<b['call'] and order[a['id']]>=order[b['id']] for a in ops for b in ops):return False
    state=copy.deepcopy(request['initial'])
    for id in ids:
        legal,state=apply(request['model'],state,by_id[id])
        if not legal:return False
    return True

def oracle(request):
    # No memoization, partitioning, or production predecessor code.
    return next((list(p) for p in itertools.permutations(op['id'] for op in request['operations']) if verify(request,p)),None)

def run(request):
    process=subprocess.run(['node',str(CLI),'-'],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=60)
    if not process.stdout:raise AssertionError(process.stderr)
    result=json.loads(process.stdout)
    expected={'non_linearizable':2,'invalid_witness':2,'invalid_certificate':2,'unknown':3,'invalid_input':64}.get(result.get('verdict'),0)
    assert process.returncode==expected,(process.returncode,result,process.stderr)
    return result

def generated(rng,model,index):
    n=rng.randrange(1,7);positive=index%2==0
    state=False if model=='lock' else ([] if model in ('queue','stack','set') else ({'x':0,'y':0} if model=='kv_register' else ({} if model=='map' else ({'adds':{},'rems':{}} if model=='lww_set' else 0))))
    initial=copy.deepcopy(state);ops=[]
    for i in range(n):
        kind=rng.choice(['enqueue','dequeue'] if model=='queue' else ['push','pop'] if model=='stack' else ['acquire','release'] if model=='lock' else ['add','remove','contains'] if model=='set' else ['increment','decrement','read'] if model=='counter' else ['put','get','remove'] if model=='map' else ['add','remove','contains'] if model=='lww_set' else ['write','read'] if model=='max_register' else ['read','write','cas'])
        if model=='lock' and kind=='release' and not state:kind='acquire'
        arg={'type':kind}
        if model=='kv_register':arg['key']=rng.choice(['x','y'])
        if model=='map':arg['key']=rng.choice(['x','y','z'])
        if model=='lww_set':arg['element']=rng.choice(['a','b','c'])
        if model=='lww_set' and kind in ('add','remove'):arg['at']=rng.randrange(0,10)
        if model!='lww_set' and model!='max_register' and (kind in ['write','cas','enqueue','push','add','contains','put'] or (kind=='remove' and model=='set')):arg['value']=rng.choice([None,False,0,1,2,{'nested':[1,True]}])
        if model=='max_register' and kind=='write':arg['value']=rng.choice([v for v in [0,1,3,5,9] if v>=state] or [state])
        if model=='counter' and kind in ('increment','decrement') and rng.random()<0.5:arg['by']=rng.choice([1,2,5,100,1000000])
        if kind=='cas':arg['expected']=rng.choice([None,False,0,1,2])
        current=state.get(arg.get('key')) if model=='kv_register' else state
        if kind in ['write','enqueue','push','release','add','increment','decrement','put'] and model!='max_register' or (model=='lww_set' and kind in ('add','remove')) or (model=='max_register' and kind=='write'):output='ok'
        elif kind=='acquire':output=not current
        elif kind=='cas':output=same(current,arg['expected'])
        elif model=='max_register' and kind=='read':output=copy.deepcopy(state)
        elif model=='lww_set' and kind=='contains':
            e=arg['element'];a=state['adds'].get(e);r=state['rems'].get(e)
            output=a is not None and (r is None or a>=r)
        elif model=='map' and kind=='get':output=copy.deepcopy(state[arg['key']]) if arg['key'] in state else None
        elif kind in ['remove','contains']:output=member(state,arg['value']) if model!='map' else (arg['key'] in state)
        elif kind=='read':output=copy.deepcopy(current)
        else:output={'value':copy.deepcopy(state[-1] if model=='stack' else state[0])} if state else {'empty':True}
        if not positive and rng.random()<0.65:
            output=99 if kind in ['read','get'] or (model=='max_register' and kind=='read') or (model=='lww_set' and kind=='contains' and False) else (not output if kind in ['cas','acquire','remove','contains'] or (model=='lww_set' and kind=='contains') else ('wrong' if kind in ['write','enqueue','push','release','add','increment','decrement','put'] or (model=='lww_set' and kind in ('add','remove')) or (model=='max_register' and kind=='write') else {'value':99}))
        concurrent=index%3!=0
        op={'id':str(i),'client':'c'+str(i%3),'call':i+1 if concurrent else 2*i+1,'return':n+i+1 if concurrent else 2*i+2,'input':arg,'output':output}
        if positive:
            legal,state=apply(model,state,op);assert legal
        ops.append(op)
    if not positive and index%3==1:
        events=[];unstarted=list(range(n));active=[];ordinal=0
        while unstarted or active:
            ordinal+=1
            if unstarted and (not active or rng.random()<0.5):
                i=unstarted.pop(rng.randrange(len(unstarted)));active.append(i);ops[i]['call']=ordinal
            else:i=active.pop(rng.randrange(len(active)));ops[i]['return']=ordinal
    rng.shuffle(ops)
    return {'model':model,'initial':initial,'operations':ops}

def main():
    rng=random.Random(20261020);checked=0;partitioned=0
    for model in ['register','kv_register','queue','stack','lock','set','counter','map','lww_set','max_register']:
        for index in range(120):
            request=generated(rng,model,index);expected=oracle(request);result=run(request)
            assert result['verdict']==('linearizable' if expected is not None else 'non_linearizable'),(request,result,expected)
            if expected is not None:
                assert verify(request,result['witness']) and result['witness_verified']
                assert run({**request,'operation':'verify','witness':result['witness']})['valid']
                bad=result['witness'][:-1]
                assert not run({**request,'operation':'verify','witness':bad})['valid']
            else:assert result['complete_search']
            if model in ('kv_register','map'):
                part=run({**request,'partition':True});assert part['verdict']==result['verdict']
                if expected is not None:assert verify(request,part['witness'])
                partitioned+=1
            checked+=1
        print(model,'120 independent permutation checks passed',flush=True)
    reductions=0
    for index in range(20):
        ops=[]
        for i in range(3):ops.append({'id':'noise'+str(i),'client':'a','call':i*2+1,'return':i*2+2,'input':{'type':'read'},'output':0})
        ops += [{'id':'write','client':'a','call':7,'return':8,'input':{'type':'write','value':index+1},'output':'ok'},{'id':'stale','client':'b','call':9,'return':10,'input':{'type':'read'},'output':0}]
        request={'model':'register','initial':0,'operations':ops};result=run({**request,'operation':'reduce'})
        reduced=result['history'];assert oracle(reduced) is None and result['reduction_complete']
        for i in range(len(reduced['operations'])):assert oracle({**reduced,'operations':reduced['operations'][:i]+reduced['operations'][i+1:]}) is not None
        reductions+=1
    print(f'Oracle totals: {checked} histories, {partitioned} partition equivalence checks, 20 sound 1-minimal reductions; returned witnesses and omitted witnesses checked',flush=True)
if __name__=='__main__':main()
