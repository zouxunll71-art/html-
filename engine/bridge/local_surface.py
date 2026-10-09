"""Opt-in, leased local IOSurface producers. Never boots/deletes a simulator."""
import atexit,hashlib,json,os,re,subprocess,tempfile,threading,time,uuid
from dataclasses import dataclass
from pathlib import Path

PREFIX='local.studio.surface.'
TTL_SECONDS=6.0

def checked_uuid(value):
 if not isinstance(value,str):raise ValueError('Invalid local surface session/device')
 try:canonical=str(uuid.UUID(value))
 except (ValueError,AttributeError):raise ValueError('Invalid local surface session/device') from None
 if value.lower()!=canonical:raise ValueError('Invalid local surface session/device')
 return value

@dataclass(frozen=True)
class Reservation:
 generation:int
 project_id:str
 device:str
 session:str
 service:str

class LocalSurface:
 def __init__(self,root,config,clock=time.monotonic):
  self.root=Path(root);self.config=dict(config);self.clock=clock
  self.condition=threading.Condition(threading.RLock());self.build_lock=threading.Lock()
  self.generation=0;self.pending=None;self.active=None;self.retired=[];self.thread=None;self.closed=False
  atexit.register(self.close)

 def _wake(self):
  if self.thread is None:
   self.thread=threading.Thread(target=self._reap,daemon=True,name='studio-local-surface-lease');self.thread.start()
  self.condition.notify_all()

 def _invalidate(self):
  self.generation+=1;self.pending=None
  if self.active:self.retired.append(self.active['process']);self.active=None
  self._wake()

 def invalidate(self,project_id=None):
  # Called inside the bridge state lock: never compile, wait or signal here.
  with self.condition:
   if project_id is not None and not ((self.pending and self.pending.project_id==project_id) or (self.active and self.active['ticket'].project_id==project_id)):return
   if self.pending or self.active:self._invalidate()

 def reserve(self,project_id,device,session,service):
  checked_uuid(session);checked_uuid(device)
  if service!=PREFIX+session:raise ValueError('Local surface service does not match session')
  if not isinstance(project_id,str) or not project_id:raise ValueError('Local surface project is required')
  with self.condition:
   if self.closed:raise ValueError('Local surface service stopped')
   if self.active and self.active['process'].poll() is None and self.clock()<self.active['expires']:
    ticket=self.active['ticket']
    if (ticket.project_id,ticket.device,ticket.session,ticket.service)==(project_id,device,session,service):
     self.active['expires']=self.clock()+TTL_SECONDS;return ticket
    if ticket.session==session:raise ValueError('Local surface session belongs to another project/device')
   if self.pending and self.pending.session==session:
    raise ValueError('Local surface session is already preparing')
   self._invalidate()
   ticket=Reservation(self.generation,project_id,device,session,service);self.pending=ticket
   return ticket

 def valid(self,ticket):
  with self.condition:
   return not self.closed and ticket.generation==self.generation and (self.pending==ticket or (self.active and self.active['ticket']==ticket))

 def _env(self):return {**os.environ,'DEVELOPER_DIR':self.config['developerDir']}

 def _booted(self,device):
  raw=subprocess.check_output(['xcrun','simctl','list','devices','booted','--json'],env=self._env(),text=True,timeout=10)
  data=json.loads(raw)
  return any(d.get('udid','').lower()==device.lower() and d.get('state')=='Booted' for group in data.get('devices',{}).values() for d in group)

 def _build(self):
  source=self.root/'scripts/ios_surface.m';header=self.root/'scripts/ios_surface_wire.h';binary=self.root/'build/ios-surface';stamp=binary.with_suffix('.sha256')
  with self.build_lock:
   if not source.is_file() or not header.is_file():raise ValueError('Local surface helper source is unavailable')
   options=['-fobjc-arc','-fblocks','-O2','-framework','Foundation','-framework','IOSurface','-lbsm']
   digest=hashlib.sha256(source.read_bytes()+header.read_bytes()+json.dumps([options,self.config['developerDir']]).encode()).hexdigest()
   if binary.is_file() and os.access(binary,os.X_OK) and stamp.is_file() and stamp.read_text().strip()==digest:return binary
   binary.parent.mkdir(parents=True,exist_ok=True)
   fd,temp=tempfile.mkstemp(prefix='.ios-surface-',dir=binary.parent);os.close(fd)
   temporary=Path(temp);stamp_temp=Path(temp+'.sha256')
   try:
    result=subprocess.run(['xcrun','--sdk','macosx','clang',str(source),'-o',str(temporary),*options],env=self._env(),capture_output=True,text=True,timeout=45)
    if result.returncode:raise ValueError('Local surface helper build failed')
    if hashlib.sha256(source.read_bytes()+header.read_bytes()+json.dumps([options,self.config['developerDir']]).encode()).hexdigest()!=digest:raise ValueError('Local surface source changed during build')
    temporary.chmod(0o700);stamp_temp.write_text(digest+'\n');os.replace(temporary,binary);os.replace(stamp_temp,stamp)
   finally:
    temporary.unlink(missing_ok=True);stamp_temp.unlink(missing_ok=True)
   return binary

 def prepare(self,ticket):
  if not self.valid(ticket):raise ValueError('Local surface activation changed')
  if not self._booted(ticket.device):raise ValueError('Project simulator must already be booted')
  binary=self._build()
  if not self.valid(ticket):raise ValueError('Local surface activation changed')
  if not self._booted(ticket.device):raise ValueError('Project simulator is no longer booted')
  return binary

 def _qa_log_fd(self,ticket):
  # Only trusted process environment can allow-list this exact QA subscription.
  # No request-controlled path, token, content or private-framework stderr is logged.
  run=os.environ.get('STUDIO_SURFACE_QA_RUN','')
  if (os.environ.get('STUDIO_SURFACE_QA_PROJECT')!=ticket.project_id or
      os.environ.get('STUDIO_SURFACE_QA_DEVICE','').lower()!=ticket.device.lower() or
      not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,47}',run)):return None
  directory=None
  try:
   directory=os.open(self.root,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
   for part in ('artifacts','local-surface-qa',run):
    try:os.mkdir(part,0o700,dir_fd=directory)
    except FileExistsError:pass
    child=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC,dir_fd=directory)
    os.close(directory);directory=child
    st=os.fstat(directory)
    if st.st_uid!=os.getuid() or (part!='artifacts' and st.st_mode&0o077):return None
   return os.open(ticket.session.lower()+'-'+str(ticket.generation)+'.jsonl',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600,dir_fd=directory)
  except OSError:return None # Diagnostics must never prevent the normal transport.
  finally:
   if directory is not None:os.close(directory)

 def start(self,ticket,binary):
  # The caller revalidates ACTIVE/project/device under its state lock after
  # prepare(), then calls here outside that lock. An intervening selection or
  # close invalidates this generation before any producer can be published.
  with self.condition:
   if not self.valid(ticket):raise ValueError('Local surface activation changed')
   if self.active and self.active['ticket']==ticket and self.active['process'].poll() is None:
    self.active['expires']=self.clock()+TTL_SECONDS;return self._reply(self.active)
   if Path(binary)!=self.root/'build/ios-surface':raise ValueError('Unexpected local surface helper')
   diagnostic_fd=self._qa_log_fd(ticket);env=self._env();env.pop('STUDIO_SURFACE_QA_FD',None)
   if diagnostic_fd is not None:env['STUDIO_SURFACE_QA_FD']=str(diagnostic_fd)
   try:
    process=subprocess.Popen([str(binary),'--device',ticket.device,'--service',ticket.service,'--session',ticket.session],
     env=env,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,close_fds=True,pass_fds=() if diagnostic_fd is None else (diagnostic_fd,))
   finally:
    if diagnostic_fd is not None:os.close(diagnostic_fd)
   self.pending=None;self.active=dict(ticket=ticket,process=process,expires=self.clock()+TTL_SECONDS);self._wake()
   return self._reply(self.active)

 @staticmethod
 def _reply(active):
  ticket=active['ticket'];return dict(session=ticket.session,projectID=ticket.project_id,deviceUDID=ticket.device,pid=active['process'].pid)

 def ping(self,project_id,session):
  checked_uuid(session)
  with self.condition:
   if not self.active or (self.active['ticket'].project_id,self.active['ticket'].session)!=(project_id,session):raise ValueError('Local surface subscription expired')
   if self.active['process'].poll() is not None or self.clock()>=self.active['expires']:
    self._invalidate();raise ValueError('Local surface subscription expired')
   self.active['expires']=self.clock()+TTL_SECONDS;return self._reply(self.active)

 def stop(self,project_id,session):
  checked_uuid(session)
  with self.condition:
   active=self.active['ticket'] if self.active else self.pending
   if active and (active.project_id,active.session)==(project_id,session):self._invalidate();return True
   return False

 def cancel(self,ticket):
  with self.condition:
   if self.pending==ticket or (self.active and self.active['ticket']==ticket):self._invalidate()

 @staticmethod
 def _stop(process):
  # Only Popen objects created by this manager; no name/PID-wide kills.
  try:
   if process.stdin:process.stdin.close() # helper observes parent pipe EOF
   if process.poll() is None:process.terminate()
   try:process.wait(timeout=1)
   except subprocess.TimeoutExpired:process.kill();process.wait(timeout=1)
  except (OSError,subprocess.SubprocessError):pass

 def _reap(self):
  while True:
   with self.condition:
    if self.active and (self.active['process'].poll() is not None or self.clock()>=self.active['expires']):self._invalidate()
    retired,self.retired=self.retired,[]
    done=self.closed and not self.active and not self.pending
    if not retired and not done:self.condition.wait(timeout=.25 if self.active else None)
   for process in retired:self._stop(process)
   if done:return

 def close(self):
  with self.condition:
   if self.closed:return
   self.closed=True;self.generation+=1;self.pending=None
   retired,self.retired=self.retired,[]
   if self.active:retired.append(self.active['process']);self.active=None
   self.condition.notify_all()
  for process in retired:self._stop(process)
  if self.thread and self.thread is not threading.current_thread():self.thread.join(timeout=2)
