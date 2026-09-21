#!/usr/bin/env python3
import shutil,zipfile,hashlib,json
from pathlib import Path
from check_distribution import ROOT,audit
selected=audit();out=ROOT/'dist';stage=out/'github-source';stage.mkdir(parents=True,exist_ok=True)
for file in selected:
 dest=stage/file.relative_to(ROOT);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(file,dest)
archive=out/'HTML-Native-Studio-source.zip'
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for file in selected:z.write(file,'HTML-Native-Studio/'+str(file.relative_to(ROOT)))
(out/'SHA256.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  '+archive.name+'\n')
print(archive)
