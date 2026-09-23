import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import fs from 'node:fs';
const source=fs.readFileSync(new URL('../web/app.js',import.meta.url),'utf8');
const handler=source.slice(source.indexOf("$('composer').onsubmit ="),source.indexOf("$('prompt').onkeydown ="));
for(const failure of [false,true])test(`message appears before server acknowledgement; failure=${failure}`,async()=>{
 let finish,draws=0,calls=0;const request=new Promise((resolve,reject)=>finish=()=>failure?reject(Error('offline')):resolve({}));
 const elements={composer:{},prompt:{value:'hello',style:{}},model:{value:''},effort:{value:''}};
 const state={thread:'a',running:{},items:new Map(),attachments:[],selectedSkills:[]};const pendingMessages=new Map();
 vm.runInNewContext(handler,{$:id=>elements[id],state,pendingMessages,attempt:fn=>fn,updateRunning(){},renderMessages(){draws++},crypto:{randomUUID:()=> 'id'},speedTier:'default',api:()=>{calls++;return request},renderSelectedSkills(){},renderAttachments(){},refreshRegistry:async()=>{},toast(){},URL:{revokeObjectURL(){}}});
 const result=elements.composer.onsubmit({preventDefault(){}});
 assert.equal(draws,1);assert.equal(pendingMessages.get('a').status,'发送中…');assert.equal(calls,1);
 finish();if(failure){await assert.rejects(result,/offline/);assert.equal(elements.prompt.value,'hello');assert.match(pendingMessages.get('a').status,/草稿已保留/)}else{await result;assert.equal(elements.prompt.value,'')}
 assert.equal(calls,1);
});
