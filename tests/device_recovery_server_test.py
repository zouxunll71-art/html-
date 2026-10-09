"""Execute candidate lifecycle/Handler code without importing service globals."""
import ast,copy,json,sys,tempfile,threading,unittest,urllib.request,urllib.error
from pathlib import Path
from types import SimpleNamespace
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'engine/bridge'))
import performance_trace

class RecoveryServerTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.lock=threading.RLock();self.calls=[];self.inventory={'a':'new-a','b':'same-b'}
  records={p:{'id':p,'source':'/'+p,'model':{'name':p,'hash':p,'pages':{'home':{}}},'sessions':{side:{'stack':[{'page':'home'}]} for side in ('ios','web')},'runtimeMode':{'linked':False,'editing':False}} for p in ('a','b')}
  test=self
  class Input:
   def __init__(self,root,config):self.config=config;self.closed=False;self.lock=threading.RLock();self.session=config['ios'];self.block=None
   def close(self):
    test.assertFalse(test.lock._is_owned(),'input close holds state LOCK')
    self.closed=True;test.calls.append(('close-input',self.config['ios']))
    if self.block:self.block()
   def connect(self,pid):return {'session':self.session}
   def send(self,pid,session,events):return {'ok':True}
  class Devices:
   path=self.root/'project-devices.json'
   lock=threading.RLock()
   def ensure(self,pid,name):
    test.assertFalse(test.lock._is_owned(),'inventory holds state LOCK');test.calls.append(('ensure',pid))
    return {'ios':test.inventory[pid],'projectID':pid,'developerDir':'/Xcode'}
   def shutdown(self,pid):test.assertFalse(test.lock._is_owned());test.calls.append(('shutdown',pid))
  class Frames:
   config={'ios':'old-a','projectID':'a'}
   def close(self):test.assertFalse(test.lock._is_owned(),'frame close holds state LOCK');test.calls.append(('close-frames',self.config['ios']))
  def start(pid,config,finish):
   test.assertFalse(test.lock._is_owned(),'runner start holds state LOCK');test.calls.append(('start',pid,config['ios']));return 'job-'+pid+'-'+config['ios']
  def run(command,**kwargs):
   test.assertFalse(test.lock._is_owned(),'simctl holds state LOCK');test.calls.append(('run',command));return SimpleNamespace(returncode=0,stdout='',stderr='')
  self.inputs={p:Input(self.root,{'ios':'old-a' if p=='a' else 'same-b','projectID':p}) for p in ('a','b')}
  self.scope=dict(BaseHTTPRequestHandler=BaseHTTPRequestHandler,json=json,urlparse=urlparse,parse_qs=parse_qs,performance_trace=performance_trace,TOKEN='fixture-only-token',LOCK=self.lock,WORKBENCH_LOCK=threading.RLock(),ACTIVE='a',ENABLED_PROJECTS={'a','b'},STARTED_DEVICES={'a':'old-a','b':'same-b'},PROJECT_INPUTS=dict(self.inputs),PROJECT_DEVICE_CONFIGS={p:dict(i.config) for p,i in self.inputs.items()},DEVICES=Devices(),SimulatorInput=Input,IOS_FRAMES=Frames(),LOCAL_SURFACE=SimpleNamespace(invalidate=lambda pid=None:self.calls.append(('surface',pid))),ios_runner=SimpleNamespace(start=start,cancel=lambda pid:self.calls.append(('cancel',pid)),device_lock=lambda pid:threading.RLock()),finish_ios_run=lambda pid:None,ROOT=self.root,Path=Path,CONFIG={'developerDir':'/Xcode'},read=lambda pid:records[pid],mode_for=lambda r:(False,False),ERROR='',EDITING=False,LINKED=False,REV=1,ACK={},bump=lambda:None,compile_project=lambda source:copy.deepcopy(records[source.strip('/')]['model']),recompile=lambda r,m:r.update(model=m),schedule_effects=lambda *args:None,signature=lambda source:'signature',lastWatch={},PENDING_TIMERS={},PREVIEWS=SimpleNamespace(cancel=lambda pid:None),eng=lambda *args,**kwargs:None,subprocess=SimpleNamespace(run=run),os=SimpleNamespace(environ={}),copy=copy)
  self.source=(ROOT/'artifacts/performance-pipeline-0930/device-recovery/engine/bridge/server.py').read_text()
  self.scope['DEVICES'].path.write_text(json.dumps({'a':'old-a','b':'same-b'}))
  names={'Handler','require_workbench','project_input','resolve_project_device','start_resolved_device','select_device','local_surface_device'}
  definitions=[n for n in ast.parse(self.source).body if isinstance(n,(ast.FunctionDef,ast.ClassDef)) and n.name in names]
  exec(compile(ast.Module(body=definitions,type_ignores=[]),'<candidate actual Handler>','exec'),self.scope)
  self.scope.update(store=lambda record:None,BROWSER_OPEN={},CLOSE_BROWSER=set())
  self.server=ThreadingHTTPServer(('127.0.0.1',0),self.scope['Handler']);threading.Thread(target=self.server.serve_forever,daemon=True).start();self.base='http://127.0.0.1:'+str(self.server.server_port)
 def tearDown(self):self.server.shutdown();self.server.server_close();self.temp.cleanup()
 def request(self,path,body):
  req=urllib.request.Request(self.base+path,data=json.dumps(body).encode(),headers={'Content-Type':'application/json','X-Studio-Token':'fixture-only-token'})
  try:response=urllib.request.urlopen(req,timeout=3)
  except urllib.error.HTTPError as error:response=error
  with response:return response.status,json.load(response)
 def test_only_replaced_project_caches_are_invalidated_and_input_hot_path_does_not_scan(self):
  self.scope['select_device']('a')
  self.assertTrue(self.inputs['a'].closed);self.assertFalse(self.inputs['b'].closed)
  self.assertEqual(self.scope['STARTED_DEVICES'],{'a':'new-a','b':'same-b'})
  self.assertEqual([c for c in self.calls if c[0]=='surface'],[('surface','a')])
  connection=self.scope['project_input']('a');before=len(self.calls)
  for _ in range(25):self.assertIs(self.scope['project_input']('a'),connection)
  self.assertEqual(len(self.calls),before)
 def test_blocked_old_input_cleanup_keeps_state_lock_and_other_input_available(self):
  started=threading.Event();release=threading.Event();errors=[]
  self.inputs['a'].block=lambda:(started.set(),release.wait(2))
  def resolve():
   try:self.scope['resolve_project_device']('a')
   except Exception as error:errors.append(error)
  thread=threading.Thread(target=resolve);thread.start()
  try:
   self.assertTrue(started.wait(1));acquired=self.lock.acquire(timeout=.2)
   if acquired:self.lock.release()
   self.assertTrue(acquired);self.assertIs(self.scope['project_input']('b'),self.inputs['b'])
  finally:release.set();thread.join(3)
  self.assertFalse(errors);self.assertFalse(thread.is_alive())
 def test_same_project_activation_is_still_a_noop(self):
  self.assertEqual(self.request('/activate-project',{'id':'a'})[0],200);self.assertEqual(self.calls,[])
 def test_activation_and_workbench_reentry_resolve_without_global_lock(self):
  self.scope['ACTIVE']='b'
  self.assertEqual(self.request('/activate-project',{'id':'a'})[0],200)
  self.assertEqual(self.request('/workbench',{'id':'a','enabled':True})[0],200)
  self.assertEqual(len([c for c in self.calls if c[0]=='start']),1)
 def test_run_ios_recovers_and_starts_exact_replacement(self):
  code,data=self.request('/run-ios',{'id':'a'})
  self.assertEqual(code,200,data);self.assertEqual(data['job'],'job-a-new-a');self.assertTrue(self.inputs['a'].closed)
  self.assertEqual(self.scope['STARTED_DEVICES']['b'],'same-b')
 def test_repair_on_empty_replacement_schedules_install_instead_of_launching_missing_app(self):
  code,data=self.request('/repair-sync',{'id':'a'})
  self.assertEqual(code,200,data);self.assertEqual(data['job'],'job-a-new-a')
  self.assertFalse(any(c[0]=='run' for c in self.calls))
 def test_repair_of_existing_started_device_keeps_launch_path(self):
  self.inventory['a']='old-a'
  code,data=self.request('/repair-sync',{'id':'a'})
  self.assertEqual(code,200,data);self.assertNotIn('job',data)
  self.assertEqual([c[1][3] for c in self.calls if c[0]=='run'],['old-a'])
 def test_disable_closes_only_its_resources_outside_state_lock(self):
  code,data=self.request('/workbench',{'id':'a','enabled':False})
  self.assertEqual(code,200,data);self.assertTrue(self.inputs['a'].closed);self.assertFalse(self.inputs['b'].closed)
  self.assertNotIn('a',self.scope['PROJECT_INPUTS']);self.assertNotIn('a',self.scope['PROJECT_DEVICE_CONFIGS']);self.assertEqual(self.scope['STARTED_DEVICES'],{'b':'same-b'})
  self.assertIn(('shutdown','a'),self.calls)
 def test_input_route_constructs_connection_outside_global_lock(self):
  self.scope['PROJECT_INPUTS'].pop('a');self.scope['PROJECT_DEVICE_CONFIGS'].pop('a')
  code,data=self.request('/ios-input-connect',{'id':'a'})
  self.assertEqual(code,200,data);self.assertEqual(data['session'],'new-a')
 def test_edit_mode_with_no_input_does_not_allocate_or_reverse_lock_order(self):
  self.scope['PROJECT_INPUTS'].pop('a');self.scope['PROJECT_DEVICE_CONFIGS'].pop('a')
  lifecycle=self.scope['WORKBENCH_LOCK'];attempted=threading.Event();result={}
  class ObservedLock:
   def __enter__(self):attempted.set();lifecycle.acquire();return self
   def __exit__(self,*args):lifecycle.release()
  self.scope['WORKBENCH_LOCK']=ObservedLock()
  lifecycle.acquire()
  def request():
   try:result['response']=self.request('/mode',{'editing':True})
   except Exception as error:result['error']=error
  client=threading.Thread(target=request);client.start()
  try:
   self.assertTrue(attempted.wait(1));acquired=self.lock.acquire(timeout=.2)
   if acquired:self.lock.release()
   self.assertTrue(acquired,'Mode must never hold LOCK while waiting for lifecycle lock')
  finally:lifecycle.release();client.join(3)
  self.assertFalse(client.is_alive());self.assertNotIn('error',result)
  self.assertEqual(result['response'][0],200,result);self.assertEqual(self.calls,[])
  self.assertNotIn('a',self.scope['PROJECT_INPUTS'])
 def test_edit_mode_closes_only_existing_input_outside_state_lock(self):
  code,data=self.request('/mode',{'editing':True})
  self.assertEqual(code,200,data);self.assertTrue(self.inputs['a'].closed);self.assertFalse(self.inputs['b'].closed)
  self.assertEqual(self.calls,[('close-input','old-a')])
 def test_project_change_during_inventory_cannot_rebind_other_preview(self):
  original=self.scope['DEVICES'].ensure
  def ensure(pid,name):
   config=original(pid,name)
   with self.lock:
    self.scope['ACTIVE']='b';self.scope['IOS_FRAMES'].config={'ios':'same-b','projectID':'b'}
   return config
  self.scope['DEVICES'].ensure=ensure
  with self.assertRaisesRegex(ValueError,'项目已切换'):self.scope['select_device']('a')
  self.assertEqual(self.scope['IOS_FRAMES'].config['projectID'],'b')
  self.assertFalse(any(c[0] in ('close-frames','start') for c in self.calls))
  self.assertFalse(self.inputs['b'].closed)
 def test_project_change_during_old_frame_cleanup_cannot_overwrite_new_binding(self):
  original=self.scope['IOS_FRAMES'].close
  def close():
   original()
   with self.lock:self.scope['ACTIVE']='b';self.scope['IOS_FRAMES'].config={'ios':'same-b','projectID':'b'}
  self.scope['IOS_FRAMES'].close=close
  with self.assertRaisesRegex(ValueError,'项目已切换'):self.scope['select_device']('a')
  self.assertEqual(self.scope['IOS_FRAMES'].config['projectID'],'b')
  self.assertFalse(any(c[0]=='start' for c in self.calls))
 def test_surface_ping_during_blocked_inventory_does_not_wait_on_device_or_state_lock(self):
  entered=threading.Event();release=threading.Event();replied=threading.Event();result={};errors=[]
  original=self.scope['DEVICES'].ensure
  def ensure(pid,name):
   with self.scope['DEVICES'].lock:
    entered.set();release.wait(3)
    return original(pid,name)
  self.scope['DEVICES'].ensure=ensure
  self.scope['LOCAL_SURFACE'].ping=lambda pid,session:{'ok':True,'projectID':pid,'session':session}
  def resolve():
   try:self.scope['resolve_project_device']('a')
   except Exception as error:errors.append(error)
  def ping():
   try:result['response']=self.request('/local-surface/ping',{'projectID':'a','session':'test-session'})
   except Exception as error:result['error']=error
   finally:replied.set()
  lifecycle=threading.Thread(target=resolve);lifecycle.start();client=None
  try:
   self.assertTrue(entered.wait(1));client=threading.Thread(target=ping);client.start()
   self.assertTrue(replied.wait(1),'Surface heartbeat must not wait for simulator inventory')
   acquired=self.lock.acquire(timeout=.2)
   if acquired:self.lock.release()
   self.assertTrue(acquired,'Simulator inventory must not hold up ordinary event mutation')
   self.assertNotIn('error',result);self.assertEqual(result['response'][0],200,result)
  finally:
   release.set();lifecycle.join(3)
   if client:client.join(3)
  self.assertFalse(errors);self.assertFalse(lifecycle.is_alive())
 def test_surface_atomic_assignment_read_keeps_selection_and_enabled_guards(self):
  lookup=self.scope['local_surface_device']
  with self.lock:
   self.assertEqual(lookup('a'),'old-a')
   with self.assertRaisesRegex(ValueError,'selected project'):lookup('b')
   self.scope['ENABLED_PROJECTS'].discard('a')
   with self.assertRaisesRegex(ValueError,'工作台已关闭'):lookup('a')
   self.scope['ENABLED_PROJECTS'].add('a')
   replacement=self.root/'replacement.json';replacement.write_text(json.dumps({'a':'new-a','b':'same-b'}));replacement.replace(self.scope['DEVICES'].path)
   self.assertEqual(lookup('a'),'new-a')
   self.scope['DEVICES'].path.unlink()
   with self.assertRaisesRegex(ValueError,'not been assigned'):lookup('a')

if __name__=='__main__':unittest.main()
