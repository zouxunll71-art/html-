import test from 'node:test';
import assert from 'node:assert/strict';
import {Capabilities} from '../capabilities.mjs';
test('同步技能和插件只读取共享目录，不创建模型请求',async()=>{
 const calls=[];const rpc={start:async()=>{},call:async(m,p)=>{calls.push(m);if(m==='plugin/installed')return {marketplaces:[{name:'shared',plugins:[{id:'p',name:'p',installed:true,enabled:true}]}],marketplaceLoadErrors:[]};if(m==='skills/list')return {data:[{skills:[{name:'imagegen',path:'/shared/imagegen/SKILL.md',enabled:true}],errors:[]}]};if(m==='app/installed')return {apps:[]};throw Error('Unexpected mutation: '+m)}};
 const service=new Capabilities(rpc);const [a,b]=await Promise.all([service.read('/project'),service.read('/project')]);assert.equal(a,b);assert.equal(a.skills[0].name,'imagegen');assert.deepEqual(calls,['plugin/installed','skills/list','app/installed']);
 const selected=await service.inputs('/project',['/shared/imagegen/SKILL.md','/shared/imagegen/SKILL.md']);assert.deepEqual(selected,[{type:'skill',name:'imagegen',path:'/shared/imagegen/SKILL.md'}]);assert.ok(!calls.some(m=>/turn\/|thread\/start/.test(m)));
 await assert.rejects(service.inputs('/project',['/arbitrary/secret']),/停用或不存在/);
});
test('普通发送没有选中技能时不查询插件或技能目录',async()=>{
 const c=new Capabilities({start:()=>assert.fail('no startup'),call:()=>assert.fail('no RPC')});
 assert.deepEqual(await c.inputs('/project',[]),[]);
});
