import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('..',import.meta.url));
test('editor rebases two page structures without dropping local edits or fresh assets',{skip:process.platform!=='darwin'},()=>{
 const folder=fs.mkdtempSync(path.join(os.tmpdir(),'studio-rebase-'));
 try{
  const executable=path.join(folder,'test');
  execFileSync('xcrun',['swiftc','-parse-as-library',path.join(root,'native/EditorRebase.swift'),path.join(root,'tests/editor-rebase-main.swift'),'-o',executable],{stdio:'pipe'});
  assert.match(execFileSync(executable,{encoding:'utf8'}),/PASS cross-project/);
 }finally{fs.rmSync(folder,{recursive:true,force:true});}
});
test('generated editor polling is not blocked by dirty drafts and uses the recovery path',()=>{
 const output=execFileSync('python3',['-c',"import sys,pathlib;sys.path.insert(0,'native');from editor_sync import patch;print(patch(pathlib.Path('engine/Studio/StudioController.swift').read_text()))"],{cwd:root,encoding:'utf8'});
 assert.match(output,/func pollRoute\(\)\{guard !liveStatusBusy,!historyGesture,!saveInFlight/);
 assert.match(output,/self.acceptEditorSnapshot\(next,raw:current,revision:receivedRevision\)/);
 assert.match(output,/self.editorSyncFailure\(e\)/);
 assert.doesNotMatch(output,/guard !self.dirty,!self.historyGesture/);
});

test('clean editor snapshots use full typed equality and cannot erase offscreen drafts',{skip:process.platform!=='darwin'},()=>{
 const folder=fs.mkdtempSync(path.join(os.tmpdir(),'studio-clean-editor-'));
 try{
  const models=fs.readFileSync(path.join(root,'engine/Shared/Models.swift'),'utf8').split('extension UIColor')[0].replace('import UIKit','import Foundation\nimport CoreGraphics');
  fs.writeFileSync(path.join(folder,'Models.swift'),models);
  fs.writeFileSync(path.join(folder,'main.swift'),`import Foundation
let page=StudioPage(id:"home",name:"Home",route:"home",nodes:[StudioNode()])
let base=StudioProject(compileRevision:"a",id:"one",name:"One",sourcePath:"/one",package:"",assets:[],pages:[page,StudioPage(id:"detail",name:"Detail",route:"detail",nodes:[StudioNode()])],pageCandidates:[],updated:1)
var local=base
assert(local==base)
local.pages[1].nodes[0].x += 1
assert(local != base, "offscreen change must take the merge path")
local=base;local.pages[0].nodes.append(StudioNode());assert(local != base)
local=base;local.pages[0].nodes.removeAll();assert(local != base)
local=base;local.pages[0].nodes[0].parent="new-parent";assert(local != base)
local=base;local.pages[0].nodes[0].clip=true;assert(local != base)
local=base;local.selectionColor="#ABCDEF";assert(local != base)
local=base;local.assets=[StudioAsset(id:"a",name:"a",kind:"image",file:"a.png",source:"a.png",sha256:"a")];assert(local != base)
local=base;local.compileRevision="b";assert(local != base)
local=base;local.id="two";assert(local != base)
print("PASS typed equality preserves every local edit")
`);
  const executable=path.join(folder,'test');execFileSync('xcrun',['swiftc',path.join(folder,'Models.swift'),path.join(folder,'main.swift'),'-o',executable],{stdio:'pipe'});
  assert.match(execFileSync(executable,{encoding:'utf8'}),/PASS typed equality/);
  const sync=fs.readFileSync(path.join(root,'native/EditorSync.swift'),'utf8');assert.match(sync,/base\.compileRevision==fresh\.compileRevision,local==base/);
 }finally{fs.rmSync(folder,{recursive:true,force:true});}
});
