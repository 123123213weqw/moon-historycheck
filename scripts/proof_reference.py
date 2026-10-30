"""Closed-state certificate audit using separate Python transition and precedence checks."""
import copy,random
from reference import apply,generated,oracle,run,same,verify

def audit(request,certificate):
    nodes=certificate['nodes'];ops={o['id']:o for o in request['operations']}
    assert not nodes[0]['selected'] and same(nodes[0]['state'],request['initial'])
    reached={0};pending=[0]
    while pending:
        index=pending.pop();node=nodes[index];done=set(node['selected'])
        assert len(done)<len(ops)
        edges={edge['operation']:edge['target'] for edge in node['edges']};expected=set()
        for id,op in ops.items():
            if id in done or any(a['return']<op['call'] and a['id'] not in done for a in ops.values()):continue
            legal,state=apply(request['model'],node['state'],op)
            if not legal:assert id not in edges;continue
            expected.add(id);assert id in edges
            target=edges[id];child=nodes[target]
            assert set(child['selected'])==done|{id} and len(child['selected'])==len(done)+1 and same(child['state'],state)
            if target not in reached:reached.add(target);pending.append(target)
        assert set(edges)==expected
    assert len(reached)==len(nodes)

def main():
    rng=random.Random(921334);closed=0;positive=0
    for model in ['register','kv_register','queue','stack','lock','set','counter','map','lww_set','max_register']:
        for index in range(30):
            request=generated(rng,model,index);expected=oracle(request);result=run({**request,'operation':'certify'})
            assert result['verdict']==('linearizable' if expected is not None else 'non_linearizable'),(request,result)
            if expected is not None:assert verify(request,result['witness']);positive+=1;continue
            certificate=result['certificate'];audit(request,certificate)
            assert run({**request,'operation':'verify_certificate','certificate':certificate})['valid']
            tampered=copy.deepcopy(certificate);tampered['history_canonical']+='tampered'
            assert not run({**request,'operation':'verify_certificate','certificate':tampered})['valid']
            closed+=1
        print(model,'30 closure searches independently checked',flush=True)
    print('Closure evidence:',closed,'negative certificates,',positive,'positive witnesses; Python closure audit and tampering rejection passed')
if __name__=='__main__':main()
