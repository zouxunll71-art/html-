import test from 'node:test';
import assert from 'node:assert/strict';
import {readHistoryTail} from '../history-sync.mjs';
function fixture(ids){const calls=[];return {calls,call:async(method,p)=>{assert.equal(method,'thread/turns/list');calls.push(p);const start=Number(p.cursor||0),end=start+p.limit;return {data:ids.slice(start,end).map(id=>({id,items:[]})),nextCursor:end<ids.length?String(end):null}}};}
test('后台错过多轮时分页补齐，包含仍可能更新的已知轮次',async()=>{const rpc=fixture(['6','5','4','3','2','1']);const r=await readHistoryTail(rpc,'thread','1');assert.deepEqual(r.turns.map(t=>t.id),['1','2','3','4','5','6']);assert.equal(r.historyReset,false);assert.equal(rpc.calls.length,2);});
test('正常轮询只读取尾页，避免重复拉取整个历史',async()=>{const rpc=fixture(['6','5','4']);const r=await readHistoryTail(rpc,'thread','6');assert.deepEqual(r.turns.map(t=>t.id),['6']);assert.equal(rpc.calls.length,1);});
test('回滚删除已知轮次时恢复完整现有历史',async()=>{const rpc=fixture(['3','2','1']);const r=await readHistoryTail(rpc,'thread','6');assert.deepEqual(r.turns.map(t=>t.id),['1','2','3']);assert.equal(r.historyReset,true);});
test('空历史以后首次出现多轮时不能只取最后两轮',async()=>{const r=await readHistoryTail(fixture(['3','2','1']),'thread','');assert.deepEqual(r.turns.map(t=>t.id),['1','2','3']);assert.equal(r.historyReset,false);});
test('旧客户端无断点时兼容尾页，空线程可正常同步',async()=>{assert.equal((await readHistoryTail(fixture(['3','2','1']),'thread')).turns.length,2);assert.deepEqual((await readHistoryTail(fixture([]),'thread','')).turns,[]);});
