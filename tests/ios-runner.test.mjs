import test from 'node:test';
import {execFileSync} from 'node:child_process';
test('iOS runtime reuses only matching builds and installed content',()=>{
 execFileSync('python3',['tests/ios_runner_reuse_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
