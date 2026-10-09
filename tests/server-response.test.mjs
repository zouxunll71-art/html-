import test from 'node:test';
import {execFileSync} from 'node:child_process';
test('slow HTTP readers do not block shared state or alter replies',()=>{
 execFileSync('python3',['tests/server_response_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
