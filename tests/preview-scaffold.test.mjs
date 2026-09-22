import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {ensurePreviewSource} from '../preview-scaffold.mjs';
const system=path.join(os.homedir(),'Library/Application Support/HTMLNativeStudio-Share-1.0.2');
test('empty iOS project gets isolated valid starter, retry preserves edits', {skip:!fs.existsSync(system)}, async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio-scaffold-'));
 try{
  fs.mkdirSync(path.join(root,'Demo.xcodeproj'));fs.writeFileSync(path.join(root,'Demo.xcodeproj/project.pbxproj'),'ios sentinel');fs.writeFileSync(path.join(root,'AGENTS.md'),'user rules');
  const [a,b]=await Promise.all([ensurePreviewSource(root,'工作台联调示例',system),ensurePreviewSource(root,'工作台联调示例',system)]);
  assert.equal(a,b);assert.ok(fs.statSync(path.join(root,'HTMLNativeStudio/iOS')).isDirectory());assert.equal(a,path.join(fs.realpathSync(root),'HTMLNativeStudio','HTML'));
  assert.equal(JSON.parse(fs.readFileSync(path.join(a,'app.json'))).protocol,'html-native/1');
  assert.ok(fs.existsSync(path.join(a,'.studio/authoring/validate.py')));
  fs.writeFileSync(path.join(a,'README.md'),'local edits');await ensurePreviewSource(root,'ignored',system);
  assert.equal(fs.readFileSync(path.join(a,'README.md'),'utf8'),'local edits');
  assert.equal(fs.readFileSync(path.join(root,'AGENTS.md'),'utf8'),'user rules');
  assert.equal(fs.readFileSync(path.join(root,'Demo.xcodeproj/project.pbxproj'),'utf8'),'ios sentinel');
  assert.deepEqual(fs.readdirSync(root).sort(),['AGENTS.md','Demo.xcodeproj','HTMLNativeStudio']);
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('conflicting directory and failed installation leave project intact',async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio-scaffold-'));
 try{
  fs.mkdirSync(path.join(root,'HTMLNativeStudio'));fs.writeFileSync(path.join(root,'HTMLNativeStudio/keep'),'keep');
  await assert.rejects(ensurePreviewSource(root,'QA',system),/已存在/);
  assert.equal(fs.readFileSync(path.join(root,'HTMLNativeStudio/keep'),'utf8'),'keep');
  fs.rmSync(path.join(root,'HTMLNativeStudio'),{recursive:true});
  await assert.rejects(ensurePreviewSource(root,'QA','/nonexistent-studio'));
  assert.deepEqual(fs.readdirSync(root),[]);
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('precreated HTML and iOS folders are accepted without touching outer files',{skip:!fs.existsSync(system)},async()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio-empty-folders-'));
 try{
  fs.mkdirSync(path.join(root,'HTMLNativeStudio/HTML'),{recursive:true});fs.mkdirSync(path.join(root,'HTMLNativeStudio/iOS'));fs.writeFileSync(path.join(root,'keep'),'unchanged');
  const source=await ensurePreviewSource(root,'QA',system);assert.ok(fs.existsSync(path.join(source,'app.json')));assert.equal(fs.readFileSync(path.join(root,'keep'),'utf8'),'unchanged');
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
