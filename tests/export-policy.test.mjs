import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
test('iOS export preserves visible overrides and dormant layers without mutating source records',()=>{
 const result=spawnSync('/usr/bin/python3',['-c',`
import sys,copy
sys.path.insert(0,'engine/bridge')
from export_policy import prepare,meaningful_patch
record={'conflicts':[{'key':'deleted','field':'*'},{'key':'icon','field':'width'}], 'overrides':{'icon':{'patch':{'width':199.5}},'deleted':{'patch':{'x':2}},'conditional':{'patch':{'fontSize':22}}},'additions':{'home':[{'id':'extra'}]}}
original=copy.deepcopy(record)
snapshot,report=prepare(record)
assert record==original
assert snapshot['conflicts']==[]
assert snapshot['overrides']==record['overrides']
assert snapshot['additions']==record['additions']
assert len(report['conflicts'])==2
assert meaningful_patch({'fontName':'','capPoints':13,'width':20,'fontSize':22}, {})=={'width':20,'fontSize':22}
assert meaningful_patch({'fontName':''},{'fontName':'Custom'})=={'fontName':''}
assert meaningful_patch({'capPoints':15}, {})=={'capPoints':15}
`],{cwd:new URL('..',import.meta.url),encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
});

test('bound input data does not block localization export; real copy and action overrides still do',()=>{
 const result=spawnSync('/usr/bin/python3',['-c',`
import sys,copy
sys.path.insert(0,'engine/bridge')
from export_policy import prepare
from ios_rules import export_issues
model={'ios':{},'pages':{'p':{'root':{'id':'p','type':'container','children':[{'id':'hex','type':'nativeTextField','bind':'color'},{'id':'note','type':'nativeTextView','bind':'note'},{'id':'label','type':'text','text-key':'title'}]}}},'actions':{}}
model['ios']={'classPrefix':'QA'}
record={'model':model,'overrides':{'p/hex':{'patch':{'text':'#082DB5','width':158}},'p/note[item-1]':{'patch':{'text':'user note','x':42}}}}
before=copy.deepcopy(record)
assert export_issues(record)==[]
out,report=prepare(record)
assert record==before
assert out['overrides']['p/hex']['patch']=={'width':158}
assert out['overrides']['p/note[item-1]']['patch']=={'x':42}
assert len(report['boundValuesFollowingState'])==2
for key,field in [('p/label','text'),('p/hex','placeholder'),('p/hex','action')]:
 bad=copy.deepcopy(record);bad['overrides'][key]={'patch':{field:'unregistered'}}
 assert export_issues(prepare(bad)[0]),(key,field)
`],{cwd:new URL('..',import.meta.url),encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
});
