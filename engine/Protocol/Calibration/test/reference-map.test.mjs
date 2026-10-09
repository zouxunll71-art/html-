import test from 'node:test';import assert from 'node:assert/strict';import {mapReference} from '../map-reference.mjs';
const sample={sourceWidth:1206,sourceHeight:2622,viewportWidth:402,coordinateSpace:'source-screen',contentInsets:{top:103,bottom:34},elements:[{id:'bg',placement:'viewport-background',x:0,y:0,width:1206,height:2622},{id:'panel',x:60,y:360,width:1086,height:900},{id:'label',parentId:'panel',x:90,y:390,width:600,height:120,fontSize:48}]};
test('uniform scale and native safe area applied once; child stays parent-local',()=>{
 const r=mapReference(sample);assert.equal(r.viewport.height,874);assert.equal(r.scale,1/3);
 assert.equal(r.elements[0].style.top,0);assert.equal(r.elements[1].style.top,17);assert.equal(r.elements[2].style.top,10);assert.equal(r.elements[2].style.left,10);assert.equal(r.elements[2].style['font-size'],16);
 assert.equal(r.elements[1].style.top+103+r.elements[2].style.top,r.elements[2].screenBounds.y);
});
test('different reference ratios do not get nonuniformly scaled',()=>{
 const r=mapReference({...sample,sourceWidth:870,sourceHeight:1808,viewportWidth:393});assert.ok(Math.abs(r.viewport.height-1808*393/870)<1e-6);
 assert.throws(()=>mapReference({...sample,viewportHeight:852}),/Aspect ratio/);
});
test('invalid geometry, parent cycles and unsupported transformed parents fail explicitly',()=>{
 assert.throws(()=>mapReference({...sample,elements:[sample.elements[1],sample.elements[1]]}),/duplicate/);
 assert.throws(()=>mapReference({...sample,elements:[{...sample.elements[1],parentId:'panel'}]}),/cycle/);
 assert.throws(()=>mapReference({...sample,elements:[{...sample.elements[1],rotation:30},sample.elements[2]]}),/inverse-matrix/);
 assert.throws(()=>mapReference({...sample,sourceWidth:0}),/Invalid/);
 assert.throws(()=>mapReference({...sample,elements:[{...sample.elements[1],x:NaN}]}),/Invalid/);
});
