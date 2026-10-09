import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';import {resolveRuntime} from '../runtime-paths.mjs';
test('桌面嵌套CLI优先于PATH版本，同时兼容旧安装路径及显式配置',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'studio-codex-path-'));
 const make=p=>{fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,'#!/bin/sh\n');fs.chmodSync(p,0o700);return p};
 try{
  const apps=path.join(root,'Applications'),bin=path.join(root,'bin');const fallback=make(path.join(bin,'codex'));
  const old=make(path.join(apps,'ChatGPT.app/Contents/Resources/codex'));
  const nested=make(path.join(apps,'ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'));
  assert.equal(resolveRuntime({PATH:bin},root,[apps]).codex,nested);
  assert.equal(resolveRuntime({PATH:bin,CODEX_BINARY:fallback},root,[apps]).codex,fallback);
  fs.unlinkSync(nested);assert.equal(resolveRuntime({PATH:bin},root,[apps]).codex,old);
  fs.unlinkSync(old);assert.equal(resolveRuntime({PATH:bin},root,[apps]).codex,fallback);
 }finally{fs.rmSync(root,{recursive:true,force:true})}
});
test('全新用户独立解析引擎位置和自定义 Codex，不继承开发者目录',()=>{
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'recipient-home-'));try{const binary=path.join(home,'codex');fs.writeFileSync(binary,'#!/bin/sh\n');fs.chmodSync(binary,0o700);const r=resolveRuntime({CODEX_BINARY:binary,PATH:''},home);assert.equal(r.engine,path.join(home,'Library/Application Support/HTMLNativeStudio/Engine'));assert.equal(r.codex,binary);
 const custom=path.join(home,'custom-engine');assert.equal(resolveRuntime({CODEX_BINARY:binary,STUDIO_ROOT:custom},home).engine,custom);
 }finally{fs.rmSync(home,{recursive:true,force:true})}
});
