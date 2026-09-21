import {test} from 'node:test';
import assert from 'node:assert/strict';
import {removeProject} from '../project-removal.mjs';
import {mergedSidebar} from '../sidebar-sync.mjs';
const project={id:'codex:p',codexId:'p',nativeProjectId:'native',nativePreview:true,sourcePath:'/project'};
const fresh=()=>({conversations:[{id:'t',projectId:'codex:p',sourcePath:'/project',hasStarted:false}],previewBindings:{p:'native'},selectedProject:'codex:p'});
test('removal calls official project API once and preserves conversation records',async()=>{
 const registry=fresh(),calls=[];await removeProject(project,{registry,rpc:{call:async(...args)=>calls.push(args)}});
 assert.deepEqual(calls,[['project/delete',{projectId:'p'}]]);assert.equal(registry.conversations.length,1);assert.equal(registry.conversations[0].projectId,null);assert.equal(registry.selectedProject,null);assert.deepEqual(registry.previewBindings,{});
 const native=[{id:'native',sourcePath:'/project/HTMLNativeStudio'}];
 assert.equal(mergedSidebar(native,registry.conversations,{projects:[],threads:[],sections:[]},{},registry.hiddenNativeProjects).projects.length,0);
 // Re-adding the official project makes it visible despite a hidden local fallback.
 assert.equal(mergedSidebar(native,[],{projects:[{id:'p2',roots:[{path:'/project/HTMLNativeStudio'}]}],threads:[],sections:[]},{},registry.hiddenNativeProjects).projects.length,1);
});
test('failed official removal does not change local state',async()=>{
 const registry=fresh(),before=structuredClone(registry);await assert.rejects(removeProject(project,{registry,rpc:{call:async()=>{throw Error('offline')}}}));assert.deepEqual(registry,before);
});
test('running project cannot be removed',async()=>{
 const registry=fresh();await assert.rejects(removeProject(project,{registry,rpc:{call:async()=>assert.fail('must not call')},runningThreadIds:['t'],conversations:registry.conversations}),/正在执行/);
});
test('local-only project removal does not call official deletion',async()=>{
 const registry=fresh();await removeProject({id:'native',nativePreview:true},{registry,rpc:{call:async()=>assert.fail('must not call')}});assert.ok(registry.hiddenNativeProjects.includes('native'));
});
