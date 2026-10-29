"""Correctness at larger serial depth and high overlap; no timing claims."""
from reference import run,verify
def main():
    ops=[]
    for i in range(256):ops.append({'id':str(i),'client':'serial','call':2*i+1,'return':2*i+2,'input':{'type':'write','value':i},'output':'ok'})
    request={'model':'register','initial':0,'operations':ops};result=run(request)
    assert result['verdict']=='linearizable' and verify(request,result['witness'])
    keyed=[]
    for i in range(100):
        keyed += [{'id':'w'+str(i),'client':'a','call':4*i+1,'return':4*i+2,'input':{'type':'write','key':str(i),'value':i},'output':'ok'},
                  {'id':'r'+str(i),'client':'b','call':4*i+3,'return':4*i+4,'input':{'type':'read','key':str(i)},'output':i}]
    request={'model':'kv_register','initial':{},'operations':keyed,'partition':True};result=run(request)
    assert result['verdict']=='linearizable' and verify(request,result['witness']) and len(result['partitions'])==100
    counter=[{'id':'c'+str(i),'client':'cc'+str(i%8),'call':2*i+1,'return':2*i+2,'input':{'type':'increment'},'output':'ok'} for i in range(1024)]
    request={'model':'counter','initial':0,'operations':counter,'max_operations':1024};result=run(request)
    assert result['verdict']=='linearizable' and verify(request,result['witness'])
    refusal=run({'model':'counter','initial':0,'operations':counter[:2],'max_operations':5000})
    assert refusal['verdict']=='invalid_input'
    mapped=[]
    for i in range(100):
        mapped += [{'id':'mw'+str(i),'client':'a','call':4*i+1,'return':4*i+2,'input':{'type':'put','key':'k'+str(i),'value':i},'output':'ok'},
                   {'id':'mr'+str(i),'client':'b','call':4*i+3,'return':4*i+4,'input':{'type':'get','key':'k'+str(i)},'output':i}]
    request={'model':'map','initial':{},'operations':mapped,'partition':True};result=run(request)
    assert result['verdict']=='linearizable' and verify(request,result['witness']) and len(result['partitions'])==100
    lww=[{'id':str(i),'client':str(i),'call':i+1,'return':20+i,'input':{'type':'add','element':'e'+str(i),'at':i},'output':'ok'} for i in range(12)]
    lww.append({'id':'bad','client':'r','call':13,'return':40,'input':{'type':'contains','element':'e0'},'output':False})
    result=run({'model':'lww_set','initial':{'adds':{},'rems':{}},'operations':lww,'max_states':40})
    assert result['verdict']=='unknown' and result['stats']['memo_hits']>0
    overlap=[{'id':str(i),'client':str(i),'call':i+1,'return':20+i,'input':{'type':'write','value':i+1},'output':'ok'} for i in range(12)]
    overlap.append({'id':'bad','client':'reader','call':13,'return':40,'input':{'type':'read'},'output':99})
    result=run({'model':'register','initial':0,'operations':overlap,'max_states':40})
    assert result['verdict']=='unknown' and result['stats']['expanded_states']<=40
    assert result['stats']['memo_hits']>0
    print('Scale passed: 256 serial register operations, 1024 serial counter operations under a raised ceiling, 100 independent keys / 200 operations for both kv_register and map partitions, a budgeted 12-way-overlap LWW failure with memo hits, a hard-ceiling refusal, and budgeted 13-way-overlap register failure with memo hits')
if __name__=='__main__':main()
