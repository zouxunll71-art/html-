import ast,io,json,os,sys,tempfile,threading,time,unittest,urllib.error,urllib.request,uuid
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'engine/bridge'))
import performance_trace
from local_surface import LocalSurface,PREFIX,TTL_SECONDS

DEVICE='11111111-1111-4111-8111-111111111111'
OTHER='22222222-2222-4222-8222-222222222222'
SESSION='33333333-3333-4333-8333-333333333333'
SECOND='44444444-4444-4444-8444-444444444444'

class Process:
 def __init__(self,pid=9001):self.pid=pid;self.stdin=io.BytesIO();self.code=None;self.terminated=False;self.killed=False
 def poll(self):return self.code
 def terminate(self):self.terminated=True;self.code=0
 def kill(self):self.killed=True;self.code=-9
 def wait(self,timeout=None):return self.code

class SurfaceTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.now=100.
  self.manager=LocalSurface(self.root,{'developerDir':'/test/Xcode'},clock=lambda:self.now)
 def tearDown(self):self.manager.close();self.temp.cleanup()
 def reserve(self,session=SESSION,pid='a',device=DEVICE):return self.manager.reserve(pid,device,session,PREFIX+session)
 def start(self,ticket):
  process=Process()
  with patch('local_surface.subprocess.Popen',return_value=process) as popen:reply=self.manager.start(ticket,self.root/'build/ios-surface')
  return process,reply,popen.call_args
 def test_invalid_session_service_and_device_do_not_spawn(self):
  for session,service,device in [('bad',PREFIX+'bad',DEVICE),(SESSION,'another.service',DEVICE),(SESSION,PREFIX+SESSION,'bad')]:
   with self.assertRaises(ValueError):self.manager.reserve('a',device,session,service)
  self.assertIsNone(self.manager.active);self.assertIsNone(self.manager.pending)
 def test_start_is_idempotent_and_has_no_secret_or_shell(self):
  ticket=self.reserve();process,reply,args=self.start(ticket)
  self.assertEqual(reply,dict(session=SESSION,projectID='a',deviceUDID=DEVICE,pid=9001))
  self.assertEqual(args.args[0],[str(self.root/'build/ios-surface'),'--device',DEVICE,'--service',PREFIX+SESSION,'--session',SESSION])
  self.assertNotIn('shell',args.kwargs)
  again=self.reserve();self.assertEqual(again,ticket)
  with patch('local_surface.subprocess.Popen',side_effect=AssertionError('duplicate spawn')):self.assertEqual(self.manager.start(again,self.root/'build/ios-surface'),reply)
  with self.assertRaises(ValueError):self.manager.reserve('b',OTHER,SESSION,PREFIX+SESSION)
 def test_stop_ping_ttl_and_project_close_are_isolated(self):
  ticket=self.reserve();process,_,_=self.start(ticket)
  self.assertFalse(self.manager.stop('b',SESSION));self.assertFalse(self.manager.stop('a',SECOND))
  self.manager.invalidate('b');self.assertTrue(self.manager.valid(ticket))
  with self.assertRaises(ValueError):self.manager.ping('b',SESSION)
  self.now+=5;self.manager.ping('a',SESSION);self.now+=5;self.assertIsNone(process.poll())
  self.now+=2
  with self.assertRaises(ValueError):self.manager.ping('a',SESSION)
  deadline=time.monotonic()+1
  while process.poll() is None and time.monotonic()<deadline:time.sleep(.01)
  self.assertTrue(process.terminated);self.assertTrue(process.stdin.closed)
 def test_old_prepare_cannot_spawn_after_selection_away_and_back(self):
  old=self.reserve();self.manager.invalidate();new=self.reserve()
  self.manager.cancel(old);self.assertTrue(self.manager.valid(new))
  with patch('local_surface.subprocess.Popen',side_effect=AssertionError('stale spawn')):
   with self.assertRaises(ValueError):self.manager.start(old,self.root/'build/ios-surface')
  self.manager.invalidate('a');self.assertFalse(self.manager.valid(new))
 def test_prepare_only_lists_booted_devices_and_does_not_boot(self):
  ticket=self.reserve();binary=self.root/'build/ios-surface'
  data={'devices':{'runtime':[{'udid':DEVICE,'state':'Booted'}]}}
  with patch('local_surface.subprocess.check_output',return_value=json.dumps(data)) as command,patch.object(self.manager,'_build',return_value=binary):
   self.assertEqual(self.manager.prepare(ticket),binary)
   self.assertEqual(command.call_args.args[0],['xcrun','simctl','list','devices','booted','--json'])
  with patch('local_surface.subprocess.check_output',return_value=json.dumps({'devices':{}})),patch.object(self.manager,'_build',side_effect=AssertionError('shutdown build')):
   with self.assertRaises(ValueError):self.manager.prepare(ticket)
 def test_build_cache_includes_header_and_failed_build_preserves_old_binary(self):
  scripts=self.root/'scripts';scripts.mkdir();(scripts/'ios_surface.m').write_text('source');(scripts/'ios_surface_wire.h').write_text('header')
  calls=[]
  def compile(args,**kwargs):
   calls.append(args);Path(args[args.index('-o')+1]).write_bytes(b'binary');return type('Result',(),{'returncode':0})()
  with patch('local_surface.subprocess.run',side_effect=compile):
   binary=self.manager._build();self.assertEqual(self.manager._build(),binary);self.assertEqual(len(calls),1)
   (scripts/'ios_surface_wire.h').write_text('changed header');self.manager._build();self.assertEqual(len(calls),2)
  self.assertEqual(binary.stat().st_mode&0o777,0o700)
  (scripts/'ios_surface.m').write_text('broken source')
  with patch('local_surface.subprocess.run',return_value=type('Result',(),{'returncode':1})()):
   with self.assertRaises(ValueError):self.manager._build()
  self.assertEqual(binary.read_bytes(),b'binary');self.assertFalse(list(binary.parent.glob('.ios-surface-*')))

class RouteTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
  self.mapping=self.root/'devices.json';self.mapping.write_text(json.dumps({'a':DEVICE,'b':OTHER}))
  self.manager=LocalSurface(self.root,{'developerDir':'/test/Xcode'})
  tree=ast.parse((ROOT/'engine/bridge/server.py').read_text());definitions=[n for n in tree.body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in ('Handler','local_surface_device','require_workbench')]
  self.scope=dict(BROWSER=type("Browser",(),{"owns":lambda self,key:False})(),BaseHTTPRequestHandler=BaseHTTPRequestHandler,json=json,urlparse=urlparse,parse_qs=parse_qs,performance_trace=performance_trace,TOKEN='test-only-token',LOCK=threading.RLock(),ACTIVE='a',ENABLED_PROJECTS={'a','b'},LOCAL_SURFACE=self.manager,DEVICES=type('Devices',(),{'path':self.mapping,'lock':threading.RLock()})(),read=lambda pid:{'id':pid})
  exec(compile(ast.Module(body=definitions,type_ignores=[]),'<actual local surface routes>','exec'),self.scope)
  self.server=ThreadingHTTPServer(('127.0.0.1',0),self.scope['Handler']);threading.Thread(target=self.server.serve_forever,daemon=True).start();self.base='http://127.0.0.1:'+str(self.server.server_port)
 def tearDown(self):self.server.shutdown();self.server.server_close();self.manager.close();self.temp.cleanup()
 def request(self,path='/local-surface/start',body=None,token='test-only-token'):
  body=body if body is not None else {'projectID':'a','session':SESSION,'service':PREFIX+SESSION}
  request=urllib.request.Request(self.base+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json','X-Studio-Token':token})
  try:response=urllib.request.urlopen(request,timeout=3)
  except urllib.error.HTTPError as error:response=error
  with response:return response.status,json.load(response)
 def test_auth_explicit_selected_enabled_and_existing_assignment_required(self):
  with patch.object(self.manager,'prepare',side_effect=AssertionError('must reject before prepare')):
   self.assertEqual(self.request(token='wrong')[0],403)
   for body in [{},{'session':SESSION,'service':PREFIX+SESSION},{'projectID':'b','session':SESSION,'service':PREFIX+SESSION}]:self.assertEqual(self.request(body=body)[0],400)
   self.scope['ENABLED_PROJECTS'].remove('a');self.assertEqual(self.request()[0],400)
   self.scope['ENABLED_PROJECTS'].add('a');self.mapping.write_text('{}');self.assertEqual(self.request()[0],400)
 def test_compile_is_outside_lock_and_activation_is_revalidated(self):
  def prepare(ticket):
   self.assertFalse(self.scope['LOCK']._is_owned())
   with self.scope['LOCK']:self.scope['ACTIVE']='b';self.manager.invalidate()
   return self.root/'build/ios-surface'
  with patch.object(self.manager,'prepare',side_effect=prepare),patch('local_surface.subprocess.Popen',side_effect=AssertionError('stale start')):self.assertEqual(self.request()[0],400)
 def test_valid_start_ping_stop_and_stale_stop_do_not_cross_sessions(self):
  process=Process()
  with patch.object(self.manager,'prepare',return_value=self.root/'build/ios-surface'),patch('local_surface.subprocess.Popen',return_value=process):
   status,reply=self.request();self.assertEqual(status,200);self.assertEqual(reply['deviceUDID'],DEVICE)
  self.assertEqual(self.request('/local-surface/ping',{'projectID':'a','session':SESSION})[0],200)
  self.assertFalse(self.request('/local-surface/stop',{'projectID':'b','session':SESSION})[1]['stopped'])
  self.assertFalse(self.request('/local-surface/stop',{'projectID':'a','session':SECOND})[1]['stopped'])
  self.assertTrue(self.request('/local-surface/stop',{'projectID':'a','session':SESSION})[1]['stopped'])
  self.assertEqual(self.request('/local-surface/ping',{'projectID':'a','session':SESSION})[0],400)
 def test_ping_serialization_and_blocked_socket_write_do_not_hold_state_lock(self):
  process=Process()
  with patch.object(self.manager,'prepare',return_value=self.root/'build/ios-surface'),patch('local_surface.subprocess.Popen',return_value=process):
   self.assertEqual(self.request()[0],200)
  handler=self.scope['Handler'];original_respond=handler.respond;original_end_headers=handler.end_headers
  writing=threading.Event();release=threading.Event();observed=[];result={};lock=self.scope['LOCK']
  class SlowWriter:
   def __init__(self,stream):self.stream=stream
   def write(self,data):
    observed.append(('write',lock._is_owned()));writing.set()
    if not release.wait(2):raise TimeoutError('Test did not release slow writer')
    return self.stream.write(data)
   def __getattr__(self,name):return getattr(self.stream,name)
  def respond(instance,*args,**kwargs):
   if instance.path=='/local-surface/ping':observed.append(('serialize',lock._is_owned()))
   return original_respond(instance,*args,**kwargs)
  def end_headers(instance):
   original_end_headers(instance)
   if instance.path=='/local-surface/ping':instance.wfile=SlowWriter(instance.wfile)
  def request():
   try:result['response']=self.request('/local-surface/ping',{'projectID':'a','session':SESSION})
   except Exception as error:result['error']=error
  with patch.object(handler,'respond',respond),patch.object(handler,'end_headers',end_headers):
   client=threading.Thread(target=request);client.start()
   try:
    self.assertTrue(writing.wait(2))
    acquired=lock.acquire(timeout=.2)
    if acquired:lock.release()
    self.assertTrue(acquired,'Blocked ping socket must not block project state')
    self.assertEqual(observed,[('serialize',False),('write',False)])
   finally:release.set();client.join(3)
  self.assertFalse(client.is_alive());self.assertNotIn('error',result)
  self.assertEqual(result['response'][0],200)

if __name__=='__main__':unittest.main()
