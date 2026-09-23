import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import fs from 'node:fs';
const c=vm.createContext({});vm.runInContext(fs.readFileSync(new URL('../engine/Shared/engine.js',import.meta.url),'utf8'),c);
test('saved layer order changes editor list without changing nested coordinates',()=>{
 const page={nodes:[{id:'parent',x:20,y:30,layerOrder:3},{id:'a',parent:'parent',x:4,y:5,layerOrder:2},{id:'b',parent:'parent',x:8,y:9,layerOrder:1}]};
 const edited=c.StudioEngine.editorFrame(page);assert.deepEqual(Array.from(edited.nodes,n=>n.id),['b','a','parent']);
 assert.equal(edited.nodes[0].x,28);assert.equal(edited.nodes[0].y,39);assert.equal(page.nodes[2].x,8);
 const decoded=JSON.parse(JSON.stringify(edited));assert.equal(decoded.nodes[0].layerOrder,1);
});
test('cross-container saved override emits parent before child and restores page position',()=>{
 const model={entry:'home',state:{},viewport:{width:300,height:600},assets:[],pages:{home:{name:'Home',root:{id:'root',type:'stack',style:{width:300,height:600},children:[{id:'item',type:'shape',style:{width:20,height:20}},{id:'target',type:'stack',style:{position:'absolute',left:50,top:60,width:100,height:100},children:[]}]}}},actions:{}};
 const session=c.StudioEngine.initial(model),base=c.StudioEngine.frame(model,session);const item=base.nodes.find(n=>n.id.endsWith('/item')),parent=base.nodes.find(n=>n.id.endsWith('/target'));
 const result=c.StudioEngine.compose(model,session,{[item.id]:{patch:{parent:parent.id,x:10,y:15,layerOrder:1}},[parent.id]:{patch:{layerOrder:2}}},{});
 assert.ok(result.nodes.findIndex(n=>n.id===parent.id)<result.nodes.findIndex(n=>n.id===item.id));
 const edited=c.StudioEngine.editorFrame(result),moved=edited.nodes.find(n=>n.id===item.id);assert.equal(moved.x,parent.x+10);assert.equal(moved.y,parent.y+15);
});
