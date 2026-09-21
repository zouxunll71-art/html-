"""One persistent, ordered HID connection to the configured simulator."""
import atexit,json,math,os,select,subprocess,threading,time,uuid
from pathlib import Path

class SimulatorInput:
 def __init__(self,root,config):
  self.root=Path(root);self.config=config;self.lock=threading.RLock();self.proc=None;self.session=None;self.project=None;self.buffer=b''
  atexit.register(self.close)
 def _read(self,timeout=4):
  deadline=time.monotonic()+timeout
  while b'\n' not in self.buffer:
   remaining=deadline-time.monotonic()
   if remaining<=0 or not select.select([self.proc.stdout],[],[],remaining)[0]:raise ValueError('模拟器输入连接超时，请点击「运行 / 重启 iOS」')
   chunk=os.read(self.proc.stdout.fileno(),65536)
   if not chunk:raise ValueError('模拟器输入连接已断开，请重新进入运行模式')
   self.buffer+=chunk
   if len(self.buffer)>65536:raise ValueError('模拟器输入回复无效')
  line,self.buffer=self.buffer.split(b'\n',1);result=json.loads(line)
  if result.get('error'):raise ValueError('模拟器直接操作不可用：'+result['error'])
  return result
 def _send(self,command):
  self.proc.stdin.write(json.dumps(command,ensure_ascii=False).encode()+b'\n');self.proc.stdin.flush();return self._read()
 def close(self):
  with self.lock:
   proc=self.proc;self.session=None;self.project=None;self.proc=None;self.buffer=b''
   if proc:
    try:proc.stdin.close();proc.wait(timeout=2.5)
    except (OSError,subprocess.TimeoutExpired):
     if proc.poll() is None:proc.kill()
    finally:
     if proc.stdout:proc.stdout.close()
 def connect(self,project):
  with self.lock:
   self.close();helper=self.root/'build/ios-input'
   if not helper.is_file():raise ValueError('模拟器直接操作组件尚未构建，请保存并退出工作台，再从桌面双击打开')
   env=dict(os.environ,DEVELOPER_DIR=self.config['developerDir'])
   try:
    self.proc=subprocess.Popen([str(helper),self.config['ios']],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=env,bufsize=0)
    result=self._read(8)
    if not result.get('ready'):raise ValueError('模拟器输入组件未就绪')
    self.session=uuid.uuid4().hex;self.project=project
    return {'session':self.session,'transport':result['transport']}
   except Exception:self.close();raise
 def send(self,project,session,events):
  with self.lock:
   if not self.session or session!=self.session or project!=self.project:raise ValueError('模拟器操作连接已过期，请重新进入运行模式')
   if not isinstance(events,list) or not 1<=len(events)<=32:raise ValueError('Invalid input batch')
   # Validate the entire batch before delivering any of it.
   for event in events:
    if not isinstance(event,dict) or event.get('kind') not in ('down','move','up','cancel','text','key','hide'):raise ValueError('Invalid input event')
    if event['kind'] in ('down','move','up'):
     if any(not isinstance(event.get(k),(int,float)) or not math.isfinite(event[k]) or not 0<=event[k]<=1 for k in ('x','y')):raise ValueError('Invalid coordinates')
    if event['kind']=='text' and (not isinstance(event.get('text'),str) or len(event['text'])>16384):raise ValueError('Invalid text')
    if event['kind']=='key' and event.get('code') not in (40,41,42,43):raise ValueError('Invalid key')
   try:
    for event in events:self._send(event)
    return {'ok':True}
   except Exception:self.close();raise
