import test from 'node:test';
import assert from 'node:assert/strict';
import {normalizeUsage} from '../usage.mjs';
test('usedPercent 5 显示剩余 95，不显示已用值',()=>{const v=normalizeUsage({rateLimits:{primary:{usedPercent:5,windowDurationMins:10080,resetsAt:1790560233}}});assert.equal(v.buckets[0].windows[0].remaining,95)});
test('缺失额度不会伪装成 100%',()=>{const v=normalizeUsage({rateLimits:{primary:null,secondary:{usedPercent:null}}});assert.equal(v.buckets[0].windows.length,0)});
test('多额度桶优先于兼容单额度',()=>{const v=normalizeUsage({rateLimits:{primary:{usedPercent:90}},rateLimitsByLimitId:{codex:{primary:{usedPercent:5}}}});assert.equal(v.buckets[0].windows[0].remaining,95)});
test('数值限制在 0–100，保留重置时间',()=>{const v=normalizeUsage({rateLimits:{primary:{usedPercent:102,resetsAt:123},secondary:{usedPercent:-1}}});assert.deepEqual(v.buckets[0].windows.map(w=>w.remaining),[0,100]);assert.equal(v.buckets[0].windows[0].resetsAt,123)});
test('不把百分比推断成服务准许',()=>{assert.equal(normalizeUsage({rateLimits:{primary:{usedPercent:1}}}).ordinaryUsageAllowed,null);assert.equal(normalizeUsage({ordinaryUsageAllowed:false,rateLimits:{primary:{usedPercent:1}}}).ordinaryUsageAllowed,false)});
