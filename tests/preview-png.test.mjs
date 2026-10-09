import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
test('lossless PNG cache preserves sample bytes and rejects malformed/special inputs',()=>{
 execFileSync('/usr/bin/python3',[fileURLToPath(new URL('./preview_png_test.py',import.meta.url))],{stdio:'pipe'});
});
