import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {resolveRuntime} from '../runtime-paths.mjs';
test('全新用户独立解析引擎位置和自定义 Codex，不继承开发者目录',()=>{
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'recipient-home-'));try{const binary=path.join(home,'codex');fs.writeFileSync(binary,'#!/bin/sh\n');fs.chmodSync(binary,0o700);const r=resolveRuntime({CODEX_BINARY:binary,PATH:''},home);assert.equal(r.engine,path.join(home,'Library/Application Support/HTMLNativeStudio/Engine'));assert.equal(r.codex,binary);
 const custom=path.join(home,'custom-engine');assert.equal(resolveRuntime({CODEX_BINARY:binary,STUDIO_ROOT:custom},home).engine,custom);
 }finally{fs.rmSync(home,{recursive:true,force:true})}
});
