"""Pinned parser service. No shell commands, install scripts, or silent fallback."""
import atexit,json,os,select,subprocess,threading,time,shutil
from functools import lru_cache
from pathlib import Path
ROOT=Path(__file__).resolve().parent
_lock=threading.RLock();_process=None;_buffer=b''
def close():
 global _process,_buffer
 with _lock:
  process,_process=_process,None;_buffer=b''
  if process:
   if process.poll() is None:process.terminate()
   try:process.wait(timeout=1)
   except subprocess.TimeoutExpired:process.kill();process.wait()
   process.stdin.close();process.stdout.close()
atexit.register(close)
def _exchange(encoded):
 global _process,_buffer
 with _lock:
  for attempt in range(2):
   try:
    if _process is None or _process.poll() is not None:
     close();config=ROOT/'config.json'
     node=json.loads(config.read_text()).get('node') if config.exists() else shutil.which('node')
     if not node:raise ValueError('Node runtime is unavailable; reopen the desktop launcher')
     _process=subprocess.Popen([node,str(ROOT/'parser/worker.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,bufsize=0)
    raw=encoded.encode()+b'\n'
    if len(raw)>16*1024*1024:raise ValueError('Source declaration exceeds the 16 MB limit')
    deadline=time.monotonic()+10
    sent=0;fd=_process.stdin.fileno()
    while sent<len(raw):
     remaining=deadline-time.monotonic()
     if remaining<=0 or not select.select([], [fd], [], remaining)[1]:raise TimeoutError('Parser write timeout')
     sent+=os.write(fd,raw[sent:sent+4096])
    while b'\n' not in _buffer:
     remaining=deadline-time.monotonic()
     if remaining<=0 or not select.select([_process.stdout],[],[],remaining)[0]:raise TimeoutError('Parser reply timeout')
     chunk=os.read(_process.stdout.fileno(),65536)
     if not chunk:raise EOFError('Parser service stopped; check bundled dependencies')
     _buffer+=chunk
     if len(_buffer)>32*1024*1024:
      close();raise ValueError('Parser response exceeds limit')
    line,_buffer=_buffer.split(b'\n',1);return line.decode()
   except (OSError,EOFError,TimeoutError):
    close()
    if attempt:raise ValueError('Parser service unavailable after automatic restart')
@lru_cache(maxsize=256)
def _cached_exchange(encoded):return _exchange(encoded)
def request(op,**args):
 encoded=json.dumps(dict(op=op,**args),ensure_ascii=False,sort_keys=True)
 # Cache small declarations only; whole-project payloads must not accumulate.
 result=json.loads((_cached_exchange if len(encoded.encode())<=65536 else _exchange)(encoded))
 if 'error' in result:raise ValueError(result['error'])
 return result['ok']
def validate(schema,value,source):
 try:request('validate',schema=schema,value=value)
 except ValueError as error:raise ValueError(str(source)+': '+str(error)) from error
