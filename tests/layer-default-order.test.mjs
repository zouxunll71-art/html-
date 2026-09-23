import test from 'node:test';import assert from 'node:assert/strict';import {createRequire} from 'node:module';import fs from 'node:fs';
const require=createRequire(import.meta.url),E=require('../engine/Shared/engine.js');
const model={id:'test',hash:'test',viewport:{width:393,height:852},assets:[],state:{},initialPage:'home',pages:{home:{name:'Home',root:{id:'root',type:'container',style:{width:393,height:852},children:[{id:'cabinet',type:'shape',style:{width:300,height:600,background:'#AA8877'}}]}}},actions:{}};
function session(){return {state:{},stack:[{page:'home',params:{}}],modals:[],scroll:{},tick:0}}
test('new root text is above existing page and survives serialization',()=>{
 const additions={home:[{id:'new-text',type:'text',parent:'',text:'Rate',x:10,y:20,width:100,height:40}]};
 const scene=E.compose(model,session(),{},additions),node=scene.nodes.find(n=>n.id==='new-text');
 assert.ok(node.layerOrder>scene.nodes.find(n=>n.id==='home').layerOrder);
 assert.equal(E.editorFrame(scene).nodes.at(-1).id,'new-text');
 assert.deepEqual(E.compose(model,session(),{},JSON.parse(JSON.stringify(additions))),scene);
 assert.equal(additions.home[0].layerOrder,undefined);
});
test('explicit order zero retained; missing nested additions ordered deterministically',()=>{
 const scene=E.compose(model,session(),{}, {home:[{id:'group',type:'container',parent:'',layerOrder:100},{id:'child',parent:'group',type:'text'},{id:'back',parent:'',type:'shape',layerOrder:0}]});
 assert.equal(scene.nodes.find(n=>n.id==='child').layerOrder,101);
 assert.equal(scene.nodes.find(n=>n.id==='back').layerOrder,0);
 assert.ok(scene.nodes.indexOf(scene.nodes.find(n=>n.id==='group'))<scene.nodes.indexOf(scene.nodes.find(n=>n.id==='child')));
});
test('legacy editor fallback and renderer cached order use the same index',()=>{
 const nodes=[{id:'root',x:0,y:0},{id:'text',x:1,y:1,layerOrder:null}];
 assert.deepEqual(E.editorFrame({nodes}).nodes.map(n=>n.layerOrder),[0,1]);
 const swift=fs.readFileSync('engine/Shared/NativeSceneController.swift','utf8');assert.match(swift,/cached.layer.zPosition=paintOrder/);assert.match(swift,/Double\(nodeIndex\)/);
});
