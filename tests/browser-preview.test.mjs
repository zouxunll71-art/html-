import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
test('standalone HTML preview shares source, reloads safely and isolates projects and iOS',()=>{
 execFileSync('python3',['tests/browser_preview_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
