import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

test('surface waits for a real frame, retries with a finite activation budget, and invalidates stale callbacks', {skip:process.platform!=='darwin',timeout:30000},()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'studio-surface-retry-'));
 try{
  const executable=path.join(directory,'retry-tests');
  execFileSync('/usr/bin/xcrun',['swiftc','engine/Studio/LocalSurfaceRetry.swift','tests/local_surface_retry_main.swift','-o',executable],{stdio:'pipe',timeout:25000});
  const result=JSON.parse(execFileSync(executable,{encoding:'utf8',timeout:3000}));
  assert.equal(result.passed,true);assert.equal(result.checks.length,12);
 }finally{fs.rmSync(directory,{recursive:true,force:true})}
});
