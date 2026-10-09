import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
test('record cache preserves state and invalidates replaced records',()=>{
 const result=spawnSync('python3',[new URL('./record_cache_test.py',import.meta.url).pathname],{encoding:'utf8'});
 assert.equal(result.status,0,result.stderr||result.stdout);
});
