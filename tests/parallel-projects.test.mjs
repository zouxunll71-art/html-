import {test} from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import fs from 'node:fs';
const source=fs.readFileSync(new URL('../server.mjs',import.meta.url),'utf8');
function runRoute(route,context){
 const start=source.indexOf(`      case '${route}':`),end=source.indexOf('\n      case ',start+1);
 assert.ok(start>=0&&end>start);
 return vm.runInNewContext(`(async()=>{switch(route){${source.slice(start,end)}}})()`,{route,...context});
}
test('switching previews does not interrupt another running project',async()=>{
 const running=new Map([['a','turn-a']]),calls=[],registry={};
 const activate=source.slice(source.indexOf('async function activate(id)'),source.indexOf('\nconst instructions'));
 await vm.runInNewContext(activate+';activate("b")',{running,registry,project:async id=>({id,nativePreview:true}),studio:async(...args)=>calls.push(args),save(){}});
 assert.equal(registry.selectedProject,'b');assert.equal(running.get('a'),'turn-a');assert.equal(calls[0][0],'/activate-project');
});
test('new and imported projects are permitted while another project runs',async()=>{
 for(const route of ['/api/project/create','/api/project/import']){
  const running=new Map([['a','turn-a']]),registry={},calls=[];
  const result=await runRoute(route,{body:{name:'B',path:'/project-b'},running,registry,res:{},sidebar:async()=>({projects:[]}),studio:async endpoint=>{calls.push(endpoint);return endpoint==='/projects'?[]:{id:'b'}},directoryInput:p=>p,fs:{existsSync:()=>true},path:{join:(...p)=>p.join('/')},registerStudioProject:async()=>{},save(){},json:(_,v)=>v});
  assert.equal(result.id,'b');assert.equal(running.get('a'),'turn-a');assert.equal(registry.selectedProject,'b');
 }
});
test('different conversations submit concurrently using their own directories without moving the preview',async()=>{
 const running=new Map([['a','turn-a']]),startingTurns=new Set(),seen=[],conversations={b:{id:'b',sourcePath:'/project-b',projectId:'b'},c:{id:'c',sourcePath:'/project-c',projectId:'c'}};
 const common={running,startingTurns,conversation:id=>conversations[id],res:{},capabilities:{inputs:async()=>[]},crypto:{randomUUID:()=> 'event'},rpc:{call:async(method,params)=>{if(method==='model/list')return {data:[]};seen.push(params);return {turn:{id:'turn-'+params.threadId,status:'inProgress'}}}},turnSpeed:()=>({}),resume:async()=>{},submitToThread:async options=>options.start(),events:[],save(){},sidebarSync:{invalidate(){}},json:(_,v)=>v,activate:()=>assert.fail('submission must not activate preview')};
 await Promise.all(['b','c'].map(id=>runRoute('/api/turn/start',{...common,body:{threadId:id,text:'task'}})));
 assert.deepEqual(seen.map(p=>[p.threadId,p.cwd]).sort(),[['b','/project-b'],['c','/project-c']]);
 assert.equal(running.size,3);assert.equal(startingTurns.size,0);
 await assert.rejects(runRoute('/api/turn/start',{...common,body:{threadId:'b',text:'duplicate'}}),/当前对话正在运行/);
});
