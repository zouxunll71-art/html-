import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const E=require('../engine/Shared/engine.js');
const actualWorkerRequire=createRequire(new URL('../engine/bridge/engine_worker.js',import.meta.url));
function worker(){let handler;const output=[];const workerRequire=n=>n==='readline'?{createInterface:()=>({on:(_,f)=>handler=f})}:n==='../Shared/engine.js'?E:actualWorkerRequire(n);workerRequire.resolve=actualWorkerRequire.resolve;vm.runInNewContext(fs.readFileSync(new URL('../engine/bridge/engine_worker.js',import.meta.url),'utf8'),{require:workerRequire,process:{stdin:{},stdout:{write:s=>output.push(JSON.parse(s))}}});return v=>{handler(JSON.stringify(v));return output.pop()}}
const model=n=>({entry:'home',state:{project:n},pages:{home:{}},localization:{default:'en'}});
test('four interleaved project models retain independent state without retransmission',()=>{const call=worker();for(let i=0;i<4;i++)assert.equal(call({op:'initial',modelKey:String(i),model:model(i)}).ok.state.project,i);for(let j=0;j<40;j++){const i=j%4;const result=call({op:'initial',modelKey:String(i)});assert.equal(result.ok.state.project,i);result.ok.state.project='changed';}assert.equal(call({op:'initial',modelKey:'0'}).ok.state.project,0)});
test('cache promotes accessed entries, evicts least recently used and accepts refreshed models',()=>{const call=worker();for(let i=0;i<16;i++)call({op:'initial',modelKey:String(i),model:model(i)});call({op:'initial',modelKey:'0'});call({op:'initial',modelKey:'16',model:model(16)});assert.match(call({op:'initial',modelKey:'1'}).error,/cache mismatch/);assert.equal(call({op:'initial',modelKey:'0'}).ok.state.project,0);assert.equal(call({op:'initial',modelKey:'0',model:model('updated')}).ok.state.project,'updated');assert.equal(call({op:'initial',modelKey:'0'}).ok.state.project,'updated')});
