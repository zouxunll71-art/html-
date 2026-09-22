"""Prune generated output before traversal; watch source metadata only."""
import os,hashlib
from pathlib import Path

def signature(root):
 root=Path(root);out=[]
 ignored={'.git','node_modules','ios-overrides','.studio','build','__pycache__'}
 for directory,dirs,files in os.walk(root,followlinks=False):
  dirs[:]=[d for d in dirs if d not in ignored and not (Path(directory)==root and d=='HTMLNativeStudio')]
  for name in files:
   if name=='.DS_Store':continue
   p=Path(directory)/name
   try:
    st=p.stat();out.append((str(p.relative_to(root)),st.st_mtime_ns,st.st_ctime_ns,st.st_ino,st.st_size))
   except FileNotFoundError:continue
 return hashlib.sha256(repr(sorted(out)).encode()).hexdigest()
