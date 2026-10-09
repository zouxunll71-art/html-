import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source=fs.readFileSync(new URL('../engine/Web/preview.js',import.meta.url),'utf8');
const definition=source.slice(source.indexOf('class PreviewImageMemory'),source.indexOf('const imageMemory='));
function memory(limit=400){return vm.runInNewContext(definition+`;new PreviewImageMemory(${limit})`)}
const image=(src,width=5,height=5)=>({tagName:'IMG',dataset:{},src,complete:true,naturalWidth:width,naturalHeight:height});

test('decoded resources have a byte budget and evict least recently used images',()=>{
 const cache=memory(200);cache.reset('a:v1');const a=image('a'),b=image('b'),c=image('c');
 cache.retain(a);cache.retain(b);assert.equal(cache.touch('a'),true);cache.retain(c);
 assert.equal(cache.bytes,200);assert.equal(cache.images.get('a').image,a);
 assert.equal(cache.images.has('b'),false);assert.equal(cache.images.get('c').image,c);
 cache.retain(a);assert.equal(cache.bytes,200);assert.equal(cache.images.size,2);
});
test('project and source changes release old decoded resources',()=>{
 const cache=memory();cache.reset('a:v1');cache.retain(image('a'));cache.reset('a:v1');assert.equal(cache.images.size,1);
 cache.reset('b:v1');assert.equal(cache.images.size,0);assert.equal(cache.bytes,0);
 cache.retain(image('b'));cache.reset('b:v2');assert.equal(cache.images.size,0);
});
test('unloaded, failed, symbolic and oversized images are not retained',()=>{
 const cache=memory(200);
 for(const candidate of [{...image('pending'),complete:false},image('broken',0),{...image('symbol'),dataset:{symbolKey:'a'}},image('large',20,20),{...image('not-image'),tagName:'DIV'}])cache.retain(candidate);
 assert.equal(cache.images.size,0);assert.equal(cache.bytes,0);
});
