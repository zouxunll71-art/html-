import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {directoryInput,pathKey,workingDirectory} from '../project-paths.mjs';
import {mergedSidebar} from '../sidebar-sync.mjs';
test('中文、空格、file URL 和快捷路径解析到同一项目',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio-paths-'));try{
 const real=path.join(root,'中文 项目'),alias=path.join(root,'alias');fs.mkdirSync(real);fs.symlinkSync(real,alias);
 assert.equal(directoryInput(pathToFileURL(real).href),pathKey(real));assert.equal(directoryInput('"'+real+'"'),pathKey(real));assert.equal(pathKey(alias),pathKey(real));assert.throws(()=>directoryInput('relative/folder'),/完整/);
 const r=mergedSidebar([{id:'n',sourcePath:alias}],[],{projects:[{id:'p',name:'P',roots:[{path:real}]}],threads:[],sections:[]});assert.equal(r.projects.length,1);assert.equal(r.projects[0].nativePreview,true);
 assert.equal(workingDirectory({sourcePath:path.join(root,'missing')},{sourcePath:real}),pathKey(real));
 const sub=path.join(real,'worktree');fs.mkdirSync(sub);assert.equal(workingDirectory({sourcePath:sub},{sourcePath:real}),pathKey(sub));assert.throws(()=>workingDirectory({sourcePath:'/missing-project'}),/不存在/);
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
