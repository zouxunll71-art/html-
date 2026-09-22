import {test} from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {previewCatalog} from '../preview-catalog.mjs';
test('preview outage keeps project identity available to conversations',async()=>{
 let offline=false;const read=previewCatalog(async()=>{if(offline)throw Error('simulator offline');return [{id:'a',sourcePath:'/a'}]});
 assert.equal((await read())[0].id,'a');offline=true;assert.equal((await read())[0].sourcePath,'/a');offline=false;assert.equal((await read()).length,1);
});
test('project-bound runtime events and simulator allocations stay isolated',()=>{
 execFileSync('python3',['tests/project_runtime_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
