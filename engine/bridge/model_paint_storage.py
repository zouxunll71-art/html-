"""Local painting storage, isolated by project and content key."""
import base64,hashlib,json,os,re,struct,tempfile
from pathlib import Path

def exchange(root,method,key,body=None,known_revision=None):
 if not isinstance(key,str) or not 1<=len(key)<=240:raise ValueError('Invalid painting key')
 root=Path(root);name=hashlib.sha256(key.encode()).hexdigest()+'.json';dest=root/name
 if method=='GET':
  value=json.loads(dest.read_text()) if dest.exists() else None
  if value and known_revision and value.get('revision')==known_revision:return {'unchanged':True}
  return value
 if method!='POST':raise ValueError('Unsupported painting operation')
 body=body or {};png=body.get('png','')
 if not isinstance(png,str) or len(png)>8_000_000:raise ValueError('Painting exceeds storage limit')
 raw=base64.b64decode(png,validate=True)
 if raw[:8]!=b'\x89PNG\r\n\x1a\n' or len(raw)<24 or struct.unpack('>II',raw[16:24])!=(1024,1024):raise ValueError('Expected 1024px painting PNG')
 value={'png':png,'model':str(body.get('model',''))[:180],'version':1,'revision':hashlib.sha256(raw).hexdigest()}
 root.mkdir(parents=True,exist_ok=True)
 fd,tmp=tempfile.mkstemp(prefix='.paint-',dir=root)
 try:
  with os.fdopen(fd,'w') as stream:json.dump(value,stream)
  os.replace(tmp,dest)
 finally:
  if os.path.exists(tmp):os.unlink(tmp)
 return {'ok':True}
