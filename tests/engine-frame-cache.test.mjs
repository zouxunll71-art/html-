import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const rawEngine=createRequire(import.meta.url)('../engine/Shared/engine.js');
const actualWorkerRequire=createRequire(new URL('../engine/bridge/engine_worker.js',import.meta.url));
const E={...rawEngine,frame:(...args)=>JSON.parse(JSON.stringify(rawEngine.frame(...args))),compose:(...args)=>JSON.parse(JSON.stringify(rawEngine.compose(...args)))};
function worker(){
 let handler,output,calls=0;
 const engine={...E,frame(...a){calls++;return E.frame(...a)},compose(...a){calls++;return E.compose(...a)}};
 const workerRequire=n=>n==='readline'?{createInterface:()=>({on:(_,f)=>handler=f})}:n==='../Shared/engine.js'?engine:actualWorkerRequire(n);workerRequire.resolve=actualWorkerRequire.resolve;
 vm.runInNewContext(fs.readFileSync(new URL('../engine/bridge/engine_worker.js',import.meta.url),'utf8'),{require:workerRequire,process:{stdin:{},stdout:{write:s=>output=JSON.parse(s)}}});
 return {call(v){handler(JSON.stringify(v));if(output.error)throw Error(output.error);return output.ok},calls:()=>calls};
}
function model(label='One'){
 return {hash:'model-'+label,entry:'home',state:{disabled:false,title:label},viewport:{width:393,height:852},assets:[],localization:{default:'en',tables:{en:{title:'Home'},'zh-Hans':{title:'主页'}}},actions:{go:[{type:'navigate',page:'other'}]},pages:{home:{root:{id:'home',type:'container',children:[{id:'go',type:'nativeButton',action:'go','text-key':'title',disabled:{get:'state.disabled'},style:{width:100,height:44}},{id:'clock',type:'text',content:{get:'clock.now'}}]}},other:{root:{id:'other',type:'container',children:[]}}}};
}
test('interaction lookup reuses a rendered frame and returns only its declaration',()=>{
 const w=worker(),m=model(),s=E.initial(m,{now:20,offsetMinutes:0});
 const p=w.call({op:'frame',modelKey:'a',model:m,session:s});
 const reply=w.call({op:'interaction',kind:'frame',modelKey:'a',session:s,node:'home/go'});
 assert.deepEqual(reply,{pageID:p.id,declaration:p.events['home/go']});assert.equal(w.calls(),1);assert.equal(reply.nodes,undefined);
 reply.declaration.action='bad';p.nodes.length=0;
 assert.deepEqual(w.call({op:'frame',modelKey:'a',session:s}),E.frame(m,s));
 for(const node of ['deleted','__proto__','toString',null])assert.equal(w.call({op:'interaction',kind:'frame',modelKey:'a',session:s,node}).declaration,null);
});
test('session, locale, clock, safe area, disabled state and routes never return a stale frame',()=>{
 const w=worker(),m=model(),base=E.initial(m,{now:20,offsetMinutes:0});w.call({op:'initial',modelKey:'a',model:m});
 const states=[base,{...base,state:{...base.state,disabled:true}},{...base,locale:'zh-Hans'},{...base,clock:{now:100,offsetMinutes:-480}},{...base,viewportHeight:900,chromeInsets:{top:61,bottom:34}},{...base,editingPage:'home'},E.reduce(m,base,{type:'navigate',page:'other'})];
 for(const session of states){assert.deepEqual(w.call({op:'frame',modelKey:'a',session}),E.frame(m,session));assert.deepEqual(w.call({op:'interaction',kind:'frame',modelKey:'a',session,node:'home/go'}),{pageID:E.frame(m,session).id,declaration:E.frame(m,session).events['home/go']??null})}
 assert.equal(w.calls(),states.length);
});
test('iOS overrides, added-layer actions and source model replacements invalidate independently',()=>{
 const w=worker(),m=model(),s=E.initial(m);w.call({op:'initial',modelKey:'a',model:m});
 const variants=[{}, {overrides:{'home/go':{patch:{x:91,parent:'home',rotation:7}}}}, {additions:{home:[{id:'copy',type:'nativeButton',x:10,y:10,width:30,height:30,interaction:{action:'go'}}]}}];
 for(const v of variants){assert.deepEqual(w.call({op:'compose',modelKey:'a',session:s,...v}),E.compose(m,s,v.overrides,v.additions));assert.deepEqual(w.call({op:'interaction',kind:'compose',modelKey:'a',session:s,node:'copy',...v}).declaration,E.compose(m,s,v.overrides,v.additions).events.copy??null)}
 const other=model('Other');w.call({op:'initial',modelKey:'b',model:other});assert.deepEqual(w.call({op:'frame',modelKey:'b',session:s}),E.frame(other,s));
 const replaced=structuredClone(m);replaced.pages.home.root.children[0].action='changed';w.call({op:'initial',modelKey:'a',model:replaced});
 assert.equal(w.call({op:'interaction',kind:'frame',modelKey:'a',session:s,node:'home/go'}).declaration.action,'changed');
});
test('bounded LRU evicts old results; oversize keys remain correct without retention',()=>{
 const w=worker(),m=model(),base=E.initial(m);w.call({op:'initial',modelKey:'a',model:m});
 for(let tick=0;tick<33;tick++)w.call({op:'frame',modelKey:'a',session:{...base,tick}});
 const before=w.calls();w.call({op:'frame',modelKey:'a',session:{...base,tick:0}});assert.equal(w.calls(),before+1);
 const huge={...base,storage:{large:'x'.repeat(140000)}};
 for(let i=0;i<2;i++)assert.deepEqual(w.call({op:'frame',modelKey:'a',session:huge}),E.frame(m,huge));assert.equal(w.calls(),before+3);
});
test('closing one workbench discards its frame snapshots without flushing other models',()=>{
 const w=worker(),m=model(),s=E.initial(m);
 for(const key of ['a','b'])w.call({op:'frame',modelKey:key,model:m,session:s});
 w.call({op:'forgetFrames',key:'a'});const before=w.calls();
 w.call({op:'frame',modelKey:'b',session:s});assert.equal(w.calls(),before);
 assert.deepEqual(w.call({op:'frame',modelKey:'a',session:s}),E.frame(m,s));assert.equal(w.calls(),before+1);
});
