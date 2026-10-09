import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root=fileURLToPath(new URL('..',import.meta.url));
const source=fs.readFileSync(path.join(root,'engine/Studio/SourceResources.swift'),'utf8');

test('source preview demand rejects stale responses, resumes editing and coalesces route changes',{skip:process.platform!=='darwin'},()=>{
 const folder=fs.mkdtempSync(path.join(os.tmpdir(),'studio-source-demand-'));
 try{
  const state=source.split('extension StudioController {')[0].replace('import UIKit','import Foundation').replace('import CoreText','');
  fs.writeFileSync(path.join(folder,'SourcePreviewDemand.swift'),state);
  fs.writeFileSync(path.join(folder,'main.swift'),`import Foundation
var demand=SourcePreviewDemand()
for _ in 0..<100 { demand.markChanged();assert(demand.begin(allowed:false,revision:1)==nil) }
assert(!demand.loading && demand.needsRefresh)
let first=demand.begin(allowed:true,revision:1)!
assert(demand.begin(allowed:true,revision:1)==nil, "only one source request per generation")
demand.suspend()
assert(!demand.accepts(first,allowed:true,revision:1), "mode/project change invalidates asset and thumbnail callbacks")
let resumed=demand.begin(allowed:true,revision:7)!
assert(!demand.finish(first,allowed:true,revision:1), "old response cannot consume a newer request")
assert(demand.loading)
assert(demand.finish(resumed,allowed:true,revision:7))
assert(!demand.loading && !demand.needsRefresh)
assert(demand.accepts(resumed,allowed:true,revision:7), "asset callbacks remain valid after their source request completes")
assert(!demand.accepts(resumed,allowed:false,revision:7), "running/hidden tab cannot apply queued thumbnails")
let olderRoute=demand.begin(allowed:true,revision:7)!
demand.markChanged()
assert(!demand.finish(olderRoute,allowed:true,revision:8))
assert(demand.needsRefresh && !demand.loading)
let newestRoute=demand.begin(allowed:true,revision:8)!
assert(!demand.accepts(olderRoute,allowed:true,revision:8))
assert(demand.finish(newestRoute,allowed:true,revision:8))
let switching=demand.begin(allowed:true,revision:8)!
assert(!demand.finish(switching,allowed:false,revision:8))
assert(demand.needsRefresh)
demand.suspend()
let secondProject=demand.begin(allowed:true,revision:8)!
assert(!demand.finish(switching,allowed:true,revision:8), "same revision in another project is still a different request generation")
assert(demand.loading && demand.finish(secondProject,allowed:true,revision:8))
print("PASS source preview demand and stale-response recovery")
`);
  const executable=path.join(folder,'test');
  execFileSync('xcrun',['swiftc',path.join(folder,'SourcePreviewDemand.swift'),path.join(folder,'main.swift'),'-o',executable],{stdio:'pipe'});
  assert.match(execFileSync(executable,{encoding:'utf8'}),/PASS source preview demand/);
 }finally{fs.rmSync(folder,{recursive:true,force:true});}
});

test('maintained and generated controllers preserve preview-demand lifecycle wiring',()=>{
 const controller=fs.readFileSync(path.join(root,'engine/Studio/StudioController.swift'),'utf8');
 assert.match(controller,/sourceFrameRevision=rev;sourcePreviewDemand\.markChanged\(\)\};if sourcePreviewAllowed,sourcePreviewDemand\.needsRefresh\{loadSourceLayers\(\)\}/);
 assert.match(controller,/running=mode\.selectedSegmentIndex==1;updateSourcePreviewMode\(\)/);
 assert.match(controller,/scrollRelay\.cancel\(\);suspendSourcePreview\(\);UserDefaults/);
 const patched=execFileSync('python3',['-c',"import sys,pathlib;sys.path.insert(0,'native');from editor_sync import patch;print(patch(pathlib.Path('engine/Studio/StudioController.swift').read_text()))"],{cwd:root,encoding:'utf8'});
 assert.match(patched,/updateSourcePreviewMode\(\)/);
 assert.match(patched,/self\.acceptEditorSnapshot\(next,raw:current,revision:receivedRevision\)/);
 assert.match(source,/sourceThumbnailWork\?\.cancel\(\);sourceThumbnailWork=nil/);
 assert.match(source,/sourceDecodeOperations\.values\.forEach\{\$0\.cancel\(\)\}/);
 assert.match(source,/if let image=sourceThumbnails\[n\.id\]\{return image\}\s+guard sourcePreviewAllowed else\{return nil\}/);
});
