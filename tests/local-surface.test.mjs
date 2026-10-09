import test from 'node:test';
import {execFileSync} from 'node:child_process';
test('local surface subscription is authenticated, project-bound, leased and cancel-safe',()=>{
 execFileSync('python3',['tests/local_surface_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
