import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {execFileSync} from 'node:child_process';
const source=fs.readFileSync(new URL('../engine/Web/preview.js',import.meta.url),'utf8');
const definition=source.slice(source.indexOf('function previewRasterBox'),source.indexOf('function previewImageURL'));
const box=vm.runInNewContext(definition+';previewRasterBox');

test('raster sizing accounts for ancestors, Retina and workbench zoom without layout reads',()=>{
 const root={id:'root',scale:.5},parent={id:'p',parent:'root',scale:2},image={id:'i',parent:'p',scale:1.5,width:100,height:60};
 const page={width:402,nodes:[root,parent,image]};
 assert.deepEqual([...box(image,page,456,910,2)],[608,384]);
 assert.deepEqual([...box(image,page,228,455,2)],[320,192]);
 assert.deepEqual([...box(image,{...page,width:804},456,910,2)],[320,192]);
});
test('pixel-art sampling, missing parents, cycles and huge zoom preserve original images',()=>{
 const image={id:'i',width:100,height:100},page={width:402,nodes:[image]};
 for(const n of [{...image,imageRendering:'pixelated'},{...image,parent:'missing'},{...image,parent:'i'},{...image,scale:Infinity}])assert.equal(box(n,{...page,nodes:[n]},456,910,2),null);
 assert.equal(box(image,page,456,910,100),null);
});
test('display and pixel-art URLs request lossless decoding without changing display sizing or sampling',()=>{
 const urlDefinition=source.slice(source.indexOf('function previewRasterBox'),source.indexOf('function updatePreviewImage'));
 const imageURL=vm.runInNewContext(urlDefinition+';previewImageURL',{TOKEN:'fixture-token',innerWidth:456,innerHeight:910,devicePixelRatio:2});
 const node={id:'image',asset:'asset.png',width:100,height:60,fit:'fill'},page={width:402,nodes:[node]},payload={projectID:'fixture',page};
 const display=new URL(imageURL(node,payload), 'http://fixture');
 assert.equal(display.searchParams.get('raster'),[...box(node,page,456,910,2)].join(','));
 assert.equal(display.searchParams.get('fit'),'cover');
 assert.equal(display.searchParams.get('decode'),'fast'); // Bust older immutable original-PNG responses.
 const pixel=new URL(imageURL({...node,imageRendering:'pixelated'},payload),'http://fixture');
 assert.equal(pixel.searchParams.has('raster'),false);
 assert.equal(pixel.searchParams.get('decode'),'fast');
 assert.equal(pixel.searchParams.get('id'),'asset.png');
});
test('raster cache conversion, invalidation and cancellation preserve original files',()=>{
 execFileSync('python3',['tests/preview_raster_test.py'],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
