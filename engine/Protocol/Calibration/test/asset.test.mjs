import test from 'node:test';
import assert from 'node:assert/strict';
import {PNG} from 'pngjs';
import {inspectAsset} from '../inspect-asset.mjs';
test('real alpha catches nearly opaque subject and dimension mismatch without claiming visual pass', () => {
 const p=new PNG({width:3,height:1});p.data.set([0,0,0,0,123,45,67,253,20,30,40,255]);
 const r=inspectAsset(PNG.sync.write(p),{width:4,height:1,opaqueRegion:[1,0,2,1]});
 assert.equal(r.dimensionsMatch,false);assert.equal(r.transparentPixels,1);assert.equal(r.partialPixels,1);assert.equal(r.opaquePixels,1);assert.equal(r.nonOpaqueRegionPixels,1);assert.equal(r.visualStatus,'not-verified');assert.deepEqual(r.visibleBounds,{x:1,y:0,width:2,height:1});
});
test('fully transparent image is flagged, invalid region and size are rejected',()=>{
 const p=PNG.sync.write(new PNG({width:2,height:2}));
 assert.equal(inspectAsset(p).visibleBounds,null);
 assert.throws(()=>inspectAsset(p,{opaqueRegion:[1,1,2,2]}));assert.throws(()=>inspectAsset(p,{width:-1}));
});
