#!/usr/bin/env python3
"""Audit only the explicit, clean distribution file set."""
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
EXCLUDED={'node_modules','__pycache__','.DS_Store','Workspace','Projects','artifacts','build'}
def files(root=ROOT):
 for name in ['README.md','AGENTS.md','Install.command','.gitignore','package.json','package-lock.json']:
  yield root/name
 yield from root.glob('*.mjs')
 for folder in ['web','native','scripts','tests','engine']:
  for file in (root/folder).rglob('*'):
   if not file.is_file() or any(p in EXCLUDED for p in file.relative_to(root).parts):continue
   if file.name in {'token','config.json','bridge-token.txt','symbols','ios-frames','windows'} or file.suffix in {'.pyc','.log'}:continue
   yield file

def audit(root=ROOT):
 selected=list(files(root));errors=[]
 for file in selected:
  if file.is_symlink():errors.append(str(file)+' is symlink');continue
  if file.suffix=='.icns':continue
  text=file.read_text(errors='replace')
  if re.search(r'/' + r'Users/(?![.…])[^\s/]+/',text):errors.append(str(file.relative_to(root))+': personal absolute home path')
  if re.search(r'gh[pousr]_[A-Za-z0-9]{30,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----',text):errors.append(str(file.relative_to(root))+': possible credential')
 if errors:raise RuntimeError('\n'.join(errors))
 print('Distribution audit passed:',len(selected),'files. No personal runtime configuration included.')
 return selected
if __name__=='__main__':audit()
