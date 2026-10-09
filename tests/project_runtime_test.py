import ast,copy,json,sys,tempfile,unittest,time
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'engine/bridge'))
from project_devices import ProjectDevices
import performance_trace
class IsolationTests(unittest.TestCase):
 def test_distinct_persistent_devices(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);config={'ios':'device-a','developerDir':'/Xcode'}
   runtime='com.apple.CoreSimulator.SimRuntime.iOS-26-4';dtype='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'
   data={'runtimes':[{'identifier':runtime,'version':'26.4','isAvailable':True,'supportedDeviceTypes':[{'identifier':dtype}]}],'devices':{runtime:[{'udid':'device-a','deviceTypeIdentifier':dtype,'isAvailable':True}]}}
   def run(command,**kwargs):
    if command[2]=='list':return json.dumps(data).encode()
    device='dedicated-'+str(len(data['devices'][runtime]));data['devices'][runtime].append({'udid':device,'deviceTypeIdentifier':dtype,'isAvailable':True});return device+'\n'
   with patch('project_devices.subprocess.check_output',side_effect=run) as command:
    pool=ProjectDevices(root,config)
    self.assertEqual(pool.ensure('a')['ios'],'dedicated-1');self.assertEqual(pool.ensure('b')['ios'],'dedicated-2')
    self.assertEqual(ProjectDevices(root,config).ensure('a')['ios'],'dedicated-1');self.assertEqual(command.call_count,5)
    self.assertEqual(config['ios'],'device-a')
 def test_bound_event_does_not_use_active_project(self):
  nodes=ast.parse((ROOT/'engine/bridge/server.py').read_text()).body
  functions=[n for n in nodes if isinstance(n,ast.FunctionDef) and n.name in ('event','runtime','mode_for','local_navigation_host')]
  records={pid:{'id':pid,'model':{'hash':pid,'assets':[]},'sessions':{'ios':{'count':0},'web':{'count':0}},'runtimeMode':{'linked':True,'editing':False}} for pid in ['a','b']}
  env=dict(performance_trace=performance_trace,ACTIVE='a',LINKED=False,EDITING=True,REV=1,PROCESSED={},CHROME_TARGETS={},BROWSER_OPEN={},CLOSE_BROWSER=set(),copy=copy,time=time,read=lambda pid:copy.deepcopy(records[pid]),store=lambda r:records.update({r['id']:r}),bump=lambda:None,schedule_effects=lambda *a,**kw:None,eng=lambda op,**kw:{'count':kw['session']['count']+1},frame=lambda r,side:{'id':r['id'],'nodes':[]})
  exec(compile(ast.Module(body=functions,type_ignores=[]),'<runtime isolation>','exec'),env)
  env['event']({'projectID':'b','side':'ios','event':{'type':'navigate'},'eventID':'same'},'b')
  self.assertEqual(records['b']['sessions']['web']['count'],1);self.assertEqual(records['a']['sessions']['ios']['count'],0)
  snapshot=env['runtime']('ios',project_id='b');self.assertEqual(snapshot['projectID'],'b');self.assertFalse(snapshot['editing']);self.assertTrue(snapshot['linked'])
  with self.assertRaises(ValueError):env['event']({'projectID':'a','side':'ios','event':{'type':'navigate'}},'b')
 def test_stale_page_rejected_without_rendering_entire_scene(self):
  functions=[n for n in ast.parse((ROOT/'engine/bridge/server.py').read_text()).body if isinstance(n,ast.FunctionDef) and n.name=='event']
  record={'id':'a','sessions':{'web':{'stack':[{'page':'home'}]}}}
  env=dict(performance_trace=performance_trace,ACTIVE='a',PROCESSED={},read=lambda _:record,mode_for=lambda _:(True,False))
  exec(compile(ast.Module(body=functions,type_ignores=[]),'<page guard>','exec'),env)
  with self.assertRaisesRegex(ValueError,'页面已切换'):
   env['event']({'side':'web','projectID':'a','pageID':'old','event':{'type':'tab','page':'home'}})
 def test_event_can_return_project_bound_runtime_for_both_sides(self):
  import textwrap
  source=(ROOT/'engine/bridge/server.py').read_text()
  start=source.index("    if path=='/event':")
  end=source.index("    if path=='/ack':",start)
  calls=[]
  env={'performance_trace':performance_trace,'trace':None,'event':lambda body,bound,trace=None:{'ok':True},'runtime':lambda side,pid,model,bound,trace=None:calls.append((side,pid,model,bound)) or {'projectID':pid,'modelHash':model,'revision':8}}
  exec('def route(self,path,body,bound):\n'+textwrap.indent(textwrap.dedent(source[start:end]),' '),env)
  class Response:
   def respond(self,value):return value
  for side in ['ios','web']:
   reply=env['route'](Response(),'/event',{'side':side,'projectID':'b','modelHash':'hash-b','returnRuntime':True},'b')
   self.assertEqual(reply['runtime']['projectID'],'b');self.assertEqual(calls[-1],(side,'b','hash-b','b'))
  reply=env['route'](Response(),'/event',{'side':'ios','projectID':'b'},'b')
  self.assertNotIn('runtime',reply)
 def test_input_routes_keep_other_project_session_alive(self):
  import textwrap,threading
  source=(ROOT/'engine/bridge/server.py').read_text()
  start=source.index("    if path=='/ios-input-disconnect':")
  end=source.index("   if path=='/ios-window':",start)
  class Connection:
   def __init__(self,pid):self.lock=threading.RLock();self.session=pid;self.closed=False
   def close(self):self.closed=True;self.session=None
   def connect(self,pid):return {'session':self.session}
   def send(self,pid,session,events):
    if self.closed or self.session!=session:raise ValueError('expired')
    return {'ok':True}
  connections={pid:Connection(pid) for pid in ['a','b']}
  env={'require_workbench':lambda pid:None,'LOCK':threading.RLock(),'PROJECT_INPUTS':connections,'read':lambda pid:{'id':pid},'mode_for':lambda r:(False,False),'project_input':lambda pid:connections[pid]}
  code='def route(self,path,body):\n'+textwrap.indent(textwrap.dedent(source[start:end]),' ')
  exec(code,env)
  class Response:
   def respond(self,value):return value
  h=Response();route=env['route']
  route(h,'/ios-input-disconnect',{'session':'a'})
  self.assertTrue(route(h,'/ios-input',{'id':'b','session':'b','events':[]})['ok'])
  self.assertFalse(connections['b'].closed)
if __name__=='__main__':unittest.main()
