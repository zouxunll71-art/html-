import test from 'node:test';import assert from 'node:assert/strict';import {mergedSidebar} from '../sidebar-sync.mjs';
const native=[{id:'native1',sourcePath:'/studio/app',name:'Preview'}];
const catalog={projects:[{id:'p',name:'Code',roots:[{path:'/code'}]}],threads:[{id:'a',projectId:'p',cwd:'/code'},{id:'b',projectId:'p',cwd:'/code'}],sections:[]};
test('绑定按项目生效，两条对话复用同一预览且保留原源码路径',()=>{const s=mergedSidebar(native,[],catalog,{p:'native1'}),p=s.projects.find(p=>p.codexId==='p');assert.equal(p.id,'codex:p');assert.equal(p.nativeProjectId,'native1');assert.equal(p.sourcePath,'/code');assert.equal(p.previewSourcePath,'/studio/app');assert.equal(p.nativePreview,true);assert.deepEqual(s.conversations.map(c=>c.projectId),['codex:p','codex:p'])});
test('失效绑定不显示无关手机，未关联项目不自动继承当前预览',()=>{for(const bindings of [{},{p:'missing'}])assert.equal(mergedSidebar(native,[],catalog,bindings).projects[0].nativePreview,false)});
