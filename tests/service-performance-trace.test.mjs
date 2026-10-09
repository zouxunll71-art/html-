import test from 'node:test';
import {execFileSync} from 'node:child_process';
test('service trace is opt-in, bounded, private and measures the real event handler outside logging locks',()=>{
 execFileSync('python3',['tests/service_performance_trace_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
