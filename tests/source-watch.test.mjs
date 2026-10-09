import {test} from 'node:test';
import {execFileSync} from 'node:child_process';
test('source watcher ignores generated output but detects source edits, additions and deletions',()=>{
 execFileSync('python3',['-c',`import sys,tempfile
from pathlib import Path
sys.path.insert(0,'engine/bridge')
from source_watch import signature
with tempfile.TemporaryDirectory() as d:
 r=Path(d);(r/'pages').mkdir();p=r/'pages/home.html';p.write_text('old')
 before=signature(r)
 (r/'HTMLNativeStudio/iOS/build').mkdir(parents=True);(r/'HTMLNativeStudio/iOS/build/export.swift').write_text('generated')
 assert signature(r)==before
 (r/'qa').mkdir();(r/'qa/reference.png').write_bytes(b'qa');assert signature(r)==before
 (r/'assets/qa').mkdir(parents=True);(r/'assets/qa/icon.png').write_bytes(b'asset');assert signature(r)!=before
 before=signature(r)
 p.write_text('new');assert signature(r)!=before
 before=signature(r);q=r/'pages/new.html';q.write_text('new');assert signature(r)!=before
 before=signature(r);q.unlink();assert signature(r)!=before
`],{cwd:new URL('..',import.meta.url),stdio:'pipe'});
});
