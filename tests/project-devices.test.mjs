import test from 'node:test';
import {execFileSync} from 'node:child_process';
test('deleted simulator assignments recover without adopting other projects or external phones',()=>{
 execFileSync('python3',['tests/project_devices_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
