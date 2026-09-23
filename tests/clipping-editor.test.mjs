import test from 'node:test';
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
test('移出裁切容器保留普通和嵌套旋转缩放图层的世界坐标',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'studio-clipping-'));
 try {const bin=path.join(dir,'test');execFileSync('xcrun',['swiftc','native/ClippingGeometry.swift','tests/clipping-geometry-main.swift','-o',bin],{stdio:'pipe'});assert.match(execFileSync(bin,{encoding:'utf8'}),/PASS/)}finally{fs.rmSync(dir,{recursive:true,force:true})}
});
test('生成的图层排序保持原有父级并集成裁切提示',()=>{
 const result=execFileSync('python3',['-c',`import sys,pathlib
sys.path.insert(0,'native')
from clipping_editor import patch_order,patch_controller,patch_surface
s=patch_order(pathlib.Path('engine/Studio/LayerReordering.swift').read_text())
assert 'moved.parent=' not in s
assert 'checkpoint();let moved=rows.remove(at:source);rows.insert(moved,at:destination)' in s
assert 'stampLayerOrder()' in s and 'identity.page==page?.id' in s
assert 'addClippingInspector(n)' in patch_controller(pathlib.Path('engine/Studio/StudioController.swift').read_text())
assert 'cropGuides.path=nil' in patch_surface(pathlib.Path('engine/Studio/DeviceSurface.swift').read_text())
print('PASS')`],{encoding:'utf8'});assert.match(result,/PASS/)
});
