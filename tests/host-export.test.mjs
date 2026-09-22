import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
test('host migration preserves configuration, supports repeat export, rejects conflicts and rolls back failures',{skip:process.platform!=='darwin'},()=>{
 execFileSync('python3',[fileURLToPath(new URL('./host_export_test.py',import.meta.url))],{stdio:'pipe'});
});
