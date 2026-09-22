import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const context=vm.createContext({});
vm.runInContext(readFileSync(new URL('../engine/Shared/engine.js',import.meta.url),'utf8'),context);
const clips=context.StudioEngine.clipsContent;
const container={type:'scroll',clip:false,width:393,height:712.679104477612,contentWidth:393,contentHeight:712.679104477612};
test('layout-only scroll container allows a resource to cross its top boundary',()=>{
 assert.equal(clips(container),false);
 assert.equal(clips({...container,contentHeight:container.height+1e-9}),false);
});
test('real vertical and horizontal scroll areas retain their viewport crop',()=>{
 assert.equal(clips({...container,contentHeight:900}),true);
 assert.equal(clips({...container,contentWidth:500}),true);
});
test('explicit crops and image boundaries remain effective',()=>{
 assert.equal(clips({...container,clip:true}),true);
 assert.equal(clips({type:'container',clip:true}),true);
 assert.equal(clips({type:'container',clip:false}),false);
 assert.equal(clips({type:'image',clip:false}),true);
});
test('resizing back to a non-scrolling layout releases the implicit crop',()=>{
 const node={...container,contentHeight:900};
 assert.equal(clips(node),true);node.height=900;assert.equal(clips(node),false);
 node.clip=true;assert.equal(clips(node),true);
});
