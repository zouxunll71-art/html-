import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const context=vm.createContext({});
vm.runInContext(readFileSync(new URL('../engine/Shared/engine.js',import.meta.url),'utf8'),context);
const E=context.StudioEngine;
test('model save rejects taps without completed work and preserves session',()=>{
 const model={entry:'home',state:{saved:[],work:''},pages:{home:{}},actions:{save:[{type:'append',path:'saved',value:{id:{get:'state.work'}}}]}};
 const s=E.initial(model),event={action:'save',bind:'work',requiresValue:true};
 for(const value of [undefined,null,'',' '])assert.throws(()=>E.reduce(model,s,{...event,value}),/completed work/);
 assert.equal(s.state.saved.length,0);
 const result=E.reduce(model,s,{...event,value:'work-123'});
 assert.equal(result.state.saved[0].id,'work-123');assert.equal(s.state.saved.length,0);
});
