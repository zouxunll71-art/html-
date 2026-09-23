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
