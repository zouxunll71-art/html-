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
