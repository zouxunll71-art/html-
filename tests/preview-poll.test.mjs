import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const source=fs.readFileSync(new URL('../engine/web/preview.js',import.meta.url),'utf8');
const poll=source.slice(source.indexOf('function acceptRuntime(p)'),source.indexOf('\nsetInterval(poll,150)'));
test('preview reuses the model and services a click arriving during polling',async()=>{
 let resolveFirst,calls=0;const rendered=[];
 const context=vm.createContext({document:{hidden:false},URLSearchParams,api:()=>{calls++;if(calls===1)return new Promise(r=>resolveFirst=r);return Promise.resolve({revision:3,reuseModel:true,projectID:'a',modelHash:'h',page:{id:'next'}})},render:p=>rendered.push(p),error:{style:{}}});
 vm.runInContext("let busy=false,pollPending=false,revision=1,payload={projectID:'a',modelHash:'h',model:{hash:'h'},assets:[]};"+poll,context);
 const first=vm.runInContext('poll()',context);await vm.runInContext('poll(true)',context);resolveFirst({revision:2,reuseModel:true,projectID:'a',modelHash:'h',page:{id:'old'}});await first;await new Promise(r=>setImmediate(r));
 assert.equal(calls,2);assert.equal(rendered.at(-1).page.id,'next');assert.equal(rendered.at(-1).model.hash,'h');
});

test('late polling cannot replace a newer click frame',()=>{
 const frames=[];const context=vm.createContext({render:p=>frames.push(p)});
 vm.runInContext("let revision=8,payload={projectID:'a',modelHash:'h',model:{hash:'h'},assets:[]};"+poll,context);
 assert.equal(vm.runInContext("acceptRuntime({revision:7,reuseModel:true,projectID:'a',modelHash:'old',page:{id:'old'}})",context),true);
 assert.equal(frames.length,0);
 assert.equal(vm.runInContext("acceptRuntime({revision:9,reuseModel:true,projectID:'a',modelHash:'h',page:{id:'new'}})",context),true);
 assert.equal(frames[0].page.id,'new');
 assert.equal(vm.runInContext("acceptRuntime({revision:10,reuseModel:true,projectID:'b',modelHash:'h',page:{id:'wrong'}})",context),false);
 assert.equal(frames.length,1);
});

test('an event and its concurrent poll render the same revision only once',()=>{
 const frames=[];const context=vm.createContext({render:p=>frames.push(p)});
 vm.runInContext("let revision=8,payload={projectID:'a',modelHash:'h',model:{hash:'h'},assets:[]};"+poll,context);
 assert.equal(vm.runInContext("acceptRuntime({revision:8,reuseModel:true,projectID:'a',modelHash:'h',page:{id:'same'}})",context),true);
 assert.equal(frames.length,0);
});
