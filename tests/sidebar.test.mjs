import test from 'node:test';import assert from 'node:assert/strict';import {mergedSidebar,SidebarSync} from '../sidebar-sync.mjs';
const p={id:'official',name:'原生项目',roots:[{path:'/work/app'}]};const native={id:'native',name:'本地别名',sourcePath:'/work/app'};
const thread={id:'t1',cwd:'/work/app',name:'官方名称',preview:'初始提示',createdAt:1,updatedAt:2,section:{id:'pins'}};
test('同一路径共用官方项目身份，不生成副本',()=>{const r=mergedSidebar([native],[],{projects:[p],threads:[thread],sections:[{id:'pins',name:'Pinned'}]});assert.equal(r.projects.length,1);assert.equal(r.projects[0].codexId,'official');assert.equal(r.projects[0].nativePreview,true);assert.equal(r.conversations[0].projectId,'native');assert.equal(r.conversations[0].pinned,true)});
test('官方重命名优先于本地旧标题，普通代码项目可继续对话',()=>{const r=mergedSidebar([],[{id:'t1',title:'旧标题'}],{projects:[p],threads:[thread],sections:[]});assert.equal(r.conversations[0].title,'官方名称');assert.equal(r.projects[0].nativePreview,false)});
test('从官方列表消失的已归档对话不会被本地记录复活，未发送草稿保留',()=>{const r=mergedSidebar([],[{id:'sent',hasStarted:true},{id:'draft',hasStarted:false},{id:'archived',hasStarted:false,archived:true}],{projects:[],threads:[],sections:[]});assert.deepEqual(r.conversations.map(t=>t.id),['draft'])});
test('读取完整分页列表并合并并发刷新，避免轮询堆积',async()=>{let calls=0;const rpc={start:async()=>{},call:async(method,p)=>{calls++;return {data:method==='project/list'?[{id:p.cursor?'p2':'p1'}]:[],nextCursor:method==='project/list'&&!p.cursor?'next':null}}};const sync=new SidebarSync(rpc);const [a,b]=await Promise.all([sync.read(),sync.read()]);assert.equal(a,b);assert.equal(a.projects.length,2);assert.equal(calls,4);await sync.read();assert.equal(calls,4)});
test('移动目录后仍保留已知对话归属，子目录和多根目录也能匹配',()=>{
 const projects=[{id:'moved',name:'Moved',roots:[{path:'/new/root'},{path:'/second'}]}];
 const threads=[{id:'old',cwd:'/old/root'},{id:'nested',cwd:'/new/root/sub'},{id:'second',cwd:'/second/child'},{id:'unrelated',cwd:'/new/root-other'}];
 const r=mergedSidebar([],[{id:'old',projectId:'codex:moved'}],{projects,threads,sections:[]});
 assert.deepEqual(r.conversations.map(t=>t.projectId),['codex:moved','codex:moved','codex:moved',null]);
});
test('分支对话有父对话也不能从侧栏丢弃',()=>{
 const r=mergedSidebar([],[],{projects:[p],threads:[{...thread,parentThreadId:'parent'}],sections:[]});assert.equal(r.conversations.length,1);
});
test('用户强制刷新也只读索引，不阻塞在全部历史文件扫描',async()=>{
 const calls=[];const sync=new SidebarSync({start:async()=>{},call:async(method,params)=>{calls.push({method,params});return {data:[]}}});await sync.read(true);assert.equal(calls.find(c=>c.method==='thread/list').params.useStateDbOnly,true);
});
