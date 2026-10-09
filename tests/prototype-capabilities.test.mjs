import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const sandbox=vm.createContext({});vm.runInContext(readFileSync(new URL('../engine/Shared/engine.js',import.meta.url),'utf8'),sandbox);const E=sandbox.StudioEngine;
const get=path=>({get:path}),op=(op,...args)=>({op,args});
const model=()=>({entry:'home',state:{expiry:0,date:'',result:null},viewport:{width:393,height:852},pages:{home:{root:{id:'home',type:'container',style:{},children:[]},navigation:{hidden:true}},other:{root:{id:'other',type:'container',style:{},children:[]}}},assets:[],navigation:{tabs:[]},actions:{renew:[{type:'set',path:'expiry',value:op('add',op('max',get('state.expiry'),get('clock.now')),86400000)}],date:[{type:'set',path:'date',value:op('dateFormat',get('clock.now'),'day',get('clock.offsetMinutes'))}],photo:[{type:'photoPreview',path:'result',title:'Image preview',message:'No service connected; no coins charged.',close:'Close'}]},localization:{default:'en',tables:{en:{}}}});
test('clock injection renews from later expiry; dates use the specified timezone',()=>{
 const m=model();let s=E.initial(m,{now:0,offsetMinutes:0});const now=Date.UTC(2026,8,28,17);
 s=E.reduce(m,s,{action:'renew',clock:{now,offsetMinutes:-480}});assert.equal(s.state.expiry,now+86400000);
 s=E.reduce(m,s,{action:'renew',clock:{now:now+100,offsetMinutes:-480}});assert.equal(s.state.expiry,now+2*86400000);
 s=E.reduce(m,s,{action:'date'});assert.equal(s.state.date,'2026-09-29');
 const before=JSON.stringify(s);assert.throws(()=>E.reduce(m,s,{action:'date',clock:{now:NaN,offsetMinutes:0}}),/clock/);assert.equal(JSON.stringify(s),before);
});
test('layout bindings follow actual insets and viewport height',()=>{
 const m=model();m.pages.home.root.children=[{id:'measured',type:'container',style:{position:'absolute',width:10,height:10},styles:{top:op('sub',0,get('layout.top'))},children:[]}];
 let s=E.initial(m);s=E.reduce(m,s,{type:'chromeInsets',top:61,bottom:34,height:874});const f=E.frame(m,s);
 assert.equal(f.nodes.find(n=>n.id.endsWith('/measured')).y,-61);assert.equal(f.height,874);assert.equal(f.contentInsets.top,61);
});
test('photo cancellation is one-shot; results cannot mutate a different route or reset session',()=>{
 const m=model();let s=E.reduce(m,E.initial(m),{action:'photo'});const id=s.effects[0].id;
 assert.throws(()=>E.reduce(m,s,{type:'photoResult',id,status:'arbitrary'}),/photo/);
 let cancelled=E.reduce(m,s,{type:'photoResult',id,status:'cancelled'});assert.equal(cancelled.state.result.status,'cancelled');
 cancelled=E.reduce(m,cancelled,{type:'photoResult',id,status:'selected'});assert.equal(cancelled.state.result.status,'cancelled');
 m.actions.go=[{type:'push',page:'other'}];s=E.reduce(m,s,{action:'go'});s=E.reduce(m,s,{type:'photoResult',id,status:'selected'});assert.equal(s.state.result,null);
 m.actions.reset=[{type:'reset'}];let fresh=E.reduce(m,E.reduce(m,E.initial(m),{action:'photo'}),{action:'reset'});fresh=E.reduce(m,fresh,{type:'photoResult',id,status:'selected'});assert.equal(fresh.state.result,null);
});
test('source font metrics wrap words and explicit lines deterministically',()=>{
 const m=model();m.state.measured=null;m.actions.wrap=[{type:'set',path:'measured',value:op('wrapText','ab cd\nef',{widths:{a:5,b:5,c:5,d:5,e:5,f:5,' ':3},fallback:10},12)}];
 const s=E.reduce(m,E.initial(m),{action:'wrap'});assert.deepEqual(JSON.parse(JSON.stringify(s.state.measured)),['ab\ncd\nef',10,3]);
});
test('project scoped replies survive navigation but a reset invalidates them',()=>{
 const m=model();m.actions.reply=[{type:'delay',scope:'project',duration:.9,actions:[{type:'set',path:'date',value:'replied'}]}];
 let s=E.reduce(m,E.initial(m),{action:'reply'});const id=s.effects[0].id;s=E.reduce(m,s,{type:'navigate',page:'other'});s=E.reduce(m,s,{type:'effectComplete',id});assert.equal(s.state.date,'replied');
});

test('explicit scroll request is clamped by layout and subsequent manual scrolling remains possible',()=>{
 const m=model();m.actions.end=[{type:'scrollTo',node:'home/list',y:1000000}];m.pages.home.root.children=[{id:'list',type:'scroll',style:{width:100,height:100},children:[{id:'long',type:'container',style:{width:100,height:500},children:[]}]}];let s=E.reduce(m,E.initial(m),{action:'end'});assert.equal(E.frame(m,s).nodes.find(n=>n.id==='home/list').scrollY,400);s=E.reduce(m,s,{type:'scroll',node:'home/list',y:30});assert.equal(E.frame(m,s).nodes.find(n=>n.id==='home/list').scrollY,30);m.actions.bad=[{type:'scrollTo',node:'home/list',y:-1}];assert.throws(()=>E.reduce(m,s,{action:'bad'}),/scroll/);
});

test('restoring older nested state adds new fields while preserving owned data and empty lists',()=>{
 const m=model();m.actions.restore=[{type:'restore',key:'profile',path:'profile',default:{skins:{alex:0,nora:0},coins:20,history:['seed']}}];const s=E.initial(m);s.storage.profile={skins:{alex:2},coins:0,history:[]};const restored=E.reduce(m,s,{action:'restore'});assert.equal(restored.state.profile.skins.alex,2);assert.equal(restored.state.profile.skins.nora,0);assert.equal(restored.state.profile.coins,0);assert.equal(restored.state.profile.history.length,0);assert.equal(s.storage.profile.skins.nora,undefined);
});
