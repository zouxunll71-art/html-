import test from 'node:test';
import assert from 'node:assert/strict';
import {turnSpeed} from '../speed.mjs';
const models=[{model:'fast-model',isDefault:true,serviceTiers:[{id:'priority'}]},{model:'standard-model',serviceTiers:[]}];
test('标准速度明确清除旧对话继承的加速',()=>assert.deepEqual(turnSpeed('default','fast-model',models),{serviceTierForTurn:'default'}));
test('加速映射官方 priority 档位',()=>assert.deepEqual(turnSpeed('priority','fast-model',models),{serviceTierForTurn:'priority'}));
test('默认模型可选择其支持的加速',()=>assert.deepEqual(turnSpeed('priority','',models),{serviceTierForTurn:'priority'}));
test('不支持加速的模型和未知档位被拒绝',()=>{assert.throws(()=>turnSpeed('priority','standard-model',models));assert.throws(()=>turnSpeed('invalid','fast-model',models))});
