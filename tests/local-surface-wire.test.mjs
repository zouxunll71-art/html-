import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';

test('production Catalyst receiver rejects forged identity, wrong metadata, stale sequence and foreign Mach sender', {skip:process.platform!=='darwin',timeout:120000},()=>{
 const directory=fs.mkdtempSync(path.join(os.tmpdir(),'studio-surface-wire-'));
 try {
  const sdk=execFileSync('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path'],{encoding:'utf8'}).trim();
  const receiver=path.join(directory,'receiver'),sender=path.join(directory,'sender');
  execFileSync('/usr/bin/xcrun',['clang','-O2','-fobjc-arc','-fblocks','-framework','Foundation','-framework','IOSurface','tests/local_surface_sender.m','-o',sender],{stdio:'pipe',timeout:30000});
  execFileSync('/usr/bin/xcrun',['swiftc','-O','-swift-version','5','-target',`${os.arch()==='arm64'?'arm64':'x86_64'}-apple-ios15.0-macabi`,'-sdk',sdk,'-F',path.join(sdk,'System/iOSSupport/System/Library/Frameworks'),'-import-objc-header','engine/Studio/LocalSurfaceBridge.h','engine/Studio/LocalSurfaceWire.swift','engine/Studio/LocalSurfaceView.swift','tests/local_surface_receiver_main.swift','-o',receiver],{stdio:'pipe',timeout:90000});
  const result=JSON.parse(execFileSync(receiver,[sender,'00000000-0000-0000-0000-000000000001'],{encoding:'utf8',timeout:15000}));
  assert.deepEqual(result.frames.map(frame=>frame.sequence),[1,9]);
  assert.equal(result.heartbeats,1);assert.equal(result.receiverFailed,false);
  assert.equal(result.helperReapedByEOF,true);assert.equal(result.helperStatus,0);
  assert.ok(result.frames.every(frame=>frame.deviceValid&&frame.sessionValid&&frame.width===32&&frame.height===48));
 }finally{fs.rmSync(directory,{recursive:true,force:true})}
});
