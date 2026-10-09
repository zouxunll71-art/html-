import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

test('decoded resource ownership avoids duplicate loads without stale identities or retained-page leaks',()=>{
 const folder=fs.mkdtempSync(path.join(os.tmpdir(),'studio-resource-pool-'));
 try{
  const executable=path.join(folder,'tests');
  execFileSync('/usr/bin/xcrun',['swiftc','engine/Shared/AssetResourcePool.swift','tests/asset-resource-pool-main.swift','-o',executable],{stdio:'pipe',timeout:120000});
  const output=execFileSync(executable,[],{encoding:'utf8',timeout:10000});
  assert.match(output,/ownership, invalidation, concurrency and resolution tests passed/);
 }finally{fs.rmSync(folder,{recursive:true,force:true})}
});
