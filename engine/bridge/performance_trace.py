"""Opt-in request diagnostics, never business data or a second state store.

Spans collect only monotonic wall/thread CPU timings in memory. The HTTP handler
finishes the record after releasing the state lock and writing its reply.
"""
import json,os,re,stat,tempfile,threading,time,uuid
from contextlib import AbstractContextManager
from pathlib import Path

ENABLED=os.environ.get('STUDIO_PERFORMANCE_TRACE')=='1'
OUTPUT=Path(os.environ.get('STUDIO_PERFORMANCE_TRACE_PATH',str(Path(tempfile.gettempdir())/'studio-service-performance.jsonl')))
MAX_FILE_BYTES=16*1024*1024
_ID=re.compile(r'[A-Za-z0-9_.:-]{1,160}\Z')
_WRITE_LOCK=threading.Lock()

def identifier(value):
 return value if isinstance(value,str) and _ID.fullmatch(value) else None

class _NoSpan(AbstractContextManager):
 def __enter__(self):return self
 def __exit__(self,*_):return False
_NO_SPAN=_NoSpan()

class _Span(AbstractContextManager):
 def __init__(self,trace,name):self.trace=trace;self.name=name
 def __enter__(self):
  self.wall=time.monotonic_ns();self.cpu=time.thread_time_ns();return self
 def __exit__(self,kind,*_):
  self.trace.add(self.name,self.wall,time.monotonic_ns(),time.thread_time_ns()-self.cpu,kind is not None)
  return False

class _Lock(AbstractContextManager):
 def __init__(self,lock,trace):self.lock=lock;self.trace=trace
 def __enter__(self):
  with self.trace.span('lock.wait'):self.lock.acquire()
  self.hold=self.trace.span('lock.hold');self.hold.__enter__();return self
 def __exit__(self,*error):
  try:return self.hold.__exit__(*error)
  finally:self.lock.release()

def locked(lock,trace):return _Lock(lock,trace) if trace else lock
def span(trace,name):return trace.span(name) if trace else _NO_SPAN

class RequestTrace:
 def __init__(self,trace_id):
  self.trace_id=trace_id;self.origin=time.monotonic_ns();self.origin_unix=time.time_ns();self.cpu=time.thread_time_ns()
  self.spans=[dict(phase='request.received',startNs=0,durationNs=0,threadCpuNs=0,failed=False)];self.metadata={};self.finished=False
 def span(self,name):return _Span(self,name)
 def add(self,name,start,end,cpu,failed=False):
  if len(self.spans)<64:
   self.spans.append(dict(phase=name,startNs=start-self.origin,durationNs=end-start,threadCpuNs=cpu,failed=failed))
 def bind(self,project_id=None,event_id=None,side=None,revision=None):
  for key,value in [('projectID',project_id),('eventID',event_id)]:
   safe=identifier(value)
   if safe:self.metadata[key]=safe
  if side in ('web','ios'):self.metadata['side']=side
  if isinstance(revision,int) and not isinstance(revision,bool):self.metadata['revision']=revision
 def finish(self,status,disconnected=False):
  if self.finished:return
  self.finished=True
  record=dict(schema='studio-service-trace/1',traceID=self.trace_id,endpoint='/event',pid=os.getpid(),threadID=threading.get_ident(),
   monotonicStartNs=self.origin,unixStartNs=self.origin_unix,durationNs=time.monotonic_ns()-self.origin,
   threadCpuNs=time.thread_time_ns()-self.cpu,status=status,disconnected=disconnected,spans=self.spans,**self.metadata)
  # Bounded, private, best-effort diagnostics. No directory creation, rotation,
  # business payload, exception text, headers, token or project source path.
  try:
   raw=(json.dumps(record,separators=(',',':'))+'\n').encode()
   with _WRITE_LOCK:
    fd=os.open(OUTPUT,os.O_WRONLY|os.O_APPEND|os.O_CREAT|os.O_NONBLOCK|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_CLOEXEC',0),0o600)
    try:
     info=os.fstat(fd)
     if stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and not info.st_mode&0o077 and info.st_size+len(raw)<=MAX_FILE_BYTES:os.write(fd,raw)
    finally:os.close(fd)
  except (OSError,ValueError):pass

def begin(path,headers):
 if path.partition('?')[0]!='/event':return None
 trace_id=identifier(headers.get('X-Studio-Trace-ID'))
 if not trace_id and not ENABLED:return None
 return RequestTrace(trace_id or uuid.uuid4().hex)
