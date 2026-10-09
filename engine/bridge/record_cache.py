"""Bounded record cache. Models are immutable between recompiles; sessions are detached.
Writes remain synchronous and atomic: an acknowledged edit is never only in RAM.
"""
import json,threading
from collections import OrderedDict

class RecordCache:
 def __init__(self,limit=16):self.entries=OrderedDict();self.limit=limit;self.lock=threading.RLock()
 def stamp(self,path):
  s=path.stat();return (s.st_ino,s.st_mtime_ns,s.st_size)
 def encode_state(self,record):return json.dumps({k:v for k,v in record.items() if k!='model'},ensure_ascii=False,separators=(',',':'))
 def remember(self,path,stamp,model,model_bytes,state_json):
  # Keep mutable state as serialized JSON. Decoding detaches nested lists and
  # dictionaries in C without walking the same tree repeatedly in deepcopy.
  self.entries[path]=(stamp,model,model_bytes,state_json);self.entries.move_to_end(path)
  while len(self.entries)>self.limit:self.entries.popitem(last=False)
 def read(self,path):
  with self.lock:
   stamp=self.stamp(path);entry=self.entries.get(path)
   if entry is None or entry[0]!=stamp:
    record=json.loads(path.read_text());self.remember(path,stamp,record['model'],None,self.encode_state(record));entry=self.entries[path]
   self.entries.move_to_end(path);return dict(json.loads(entry[3]),model=entry[1])
 def write(self,path,record):
  with self.lock:
   entry=self.entries.get(path);model=record['model']
   encoded=entry[2] if entry and entry[1] is model else None
   if encoded is None:encoded=json.dumps(model,ensure_ascii=False,separators=(',',':')).encode('utf-8')
   state=self.encode_state(record)
   # Reuse the immutable model's UTF-8 bytes. Write the same JSON document to
   # one temporary file without rebuilding/re-encoding its full model per event.
   # Closing and replacing remain synchronous; cache mutation follows success.
   path.parent.mkdir(parents=True,exist_ok=True);temp=path.with_suffix('.tmp')
   with temp.open('wb') as stream:
    stream.write(state[:-1].encode('utf-8'));stream.write(b',"model":');stream.write(encoded);stream.write(b'}')
   temp.replace(path)
   self.remember(path,self.stamp(path),model,encoded,state)
