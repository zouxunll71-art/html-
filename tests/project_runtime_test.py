import ast,copy,json,sys,tempfile,unittest,time
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'engine/bridge'))
from project_devices import ProjectDevices
class IsolationTests(unittest.TestCase):
 def test_distinct_persistent_devices(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);config={'ios':'device-a','developerDir':'/Xcode'}
   data={'devices':{'runtime':[{'udid':'device-a','deviceTypeIdentifier':'phone'}]}}
   with patch('project_devices.subprocess.check_output',side_effect=[json.dumps(data).encode(),json.dumps(data).encode(),'device-b\n']) as command:
    pool=ProjectDevices(root,config)
    self.assertEqual(pool.ensure('a')['ios'],'device-a');self.assertEqual(pool.ensure('b')['ios'],'device-b')
    self.assertEqual(ProjectDevices(root,config).ensure('a')['ios'],'device-a');self.assertEqual(command.call_count,3)
    self.assertEqual(config['ios'],'device-a')
 def test_bound_event_does_not_use_active_project(self):
  nodes=ast.parse((ROOT/'engine/bridge/server.py').read_text()).body
  functions=[n for n in nodes if isinstance(n,ast.FunctionDef) and n.name in ('event','runtime','mode_for')]
  records={pid:{'id':pid,'model':{'hash':pid,'assets':[]},'sessions':{'ios':{'count':0},'web':{'count':0}},'runtimeMode':{'linked':True,'editing':False}} for pid in ['a','b']}
  env=dict(ACTIVE='a',LINKED=False,EDITING=True,REV=1,PROCESSED={},CHROME_TARGETS={},BROWSER_OPEN={},CLOSE_BROWSER=set(),copy=copy,time=time,read=lambda pid:copy.deepcopy(records[pid]),store=lambda r:records.update({r['id']:r}),bump=lambda:None,schedule_effects=lambda *a:None,eng=lambda op,**kw:{'count':kw['session']['count']+1},frame=lambda r,side:{'id':r['id'],'nodes':[]})
  exec(compile(ast.Module(body=functions,type_ignores=[]),'<runtime isolation>','exec'),env)
  env['event']({'projectID':'b','side':'ios','event':{'type':'navigate'},'eventID':'same'},'b')
  self.assertEqual(records['b']['sessions']['web']['count'],1);self.assertEqual(records['a']['sessions']['ios']['count'],0)
  snapshot=env['runtime']('ios',project_id='b');self.assertEqual(snapshot['projectID'],'b');self.assertFalse(snapshot['editing']);self.assertTrue(snapshot['linked'])
  with self.assertRaises(ValueError):env['event']({'projectID':'a','side':'ios','event':{'type':'navigate'}},'b')
if __name__=='__main__':unittest.main()
