import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
const E=createRequire(import.meta.url)('../engine/Shared/engine.js');
const model={entry:'home',state:{},actions:{},assets:[],viewport:{width:393,height:852},navigation:{tabs:[],topBarTransparent:true},pages:{home:{name:'Home',root:{id:'root',type:'container',style:{width:393,height:852},children:[]}}}};
test('transparent top navigation remains in rendered chrome, opaque remains default',()=>{
 assert.equal(E.frame(model,E.initial(model)).nativeChrome.topBarTransparent,true);
 const plain=structuredClone(model);delete plain.navigation.topBarTransparent;
 assert.equal(E.frame(plain,E.initial(plain)).nativeChrome.topBarTransparent,false);
});
test('editing navigation clears prior presentation animation and pending effects',()=>{
 const s=E.initial(model);s.animation={duration:10};s.effects=[{id:'pending'}];s.pendingEffects={pending:1};
 const next=E.reduce(model,s,{type:'navigate',page:'home',preview:true});
 assert.equal(next.animation,null);assert.deepEqual(next.effects,[]);assert.deepEqual(next.pendingEffects,{});
});
test('navigation transparency rejects a non-boolean configuration',()=>{
 execFileSync('python3',['-c',`import sys
sys.path.insert(0,'engine/bridge')
from ios_rules import verify_navigation
try:verify_navigation({'topBarTransparent':'yes'}, {}, {}, {})
except Exception as e:assert 'must be boolean' in str(e)
else:raise AssertionError('invalid configuration accepted')`]);
});
