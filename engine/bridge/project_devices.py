"""Persistent per-project simulator assignments; never shuts down another device."""
import json,os,subprocess,threading
class ProjectDevices:
 def __init__(self,root,config):
  self.path=root/'Workspace/project-devices.json';self.config=dict(config);self.lock=threading.RLock()
 def projects(self):
  with self.lock:return list(json.loads(self.path.read_text())) if self.path.exists() else []
 def ensure(self,pid,name='Project'):
  with self.lock:
   saved=json.loads(self.path.read_text()) if self.path.exists() else {}
   if pid in saved:return {**self.config,'ios':saved[pid],'projectID':pid}
   env={**os.environ,'DEVELOPER_DIR':self.config['developerDir']}
   data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json'],env=env,timeout=20))['devices']
   match=next(((runtime,d) for runtime,devices in data.items() for d in devices if d['udid']==self.config['ios']),None)
   if match is None:raise ValueError('无法找到模拟器模板，请检查 Xcode 的 iOS 运行环境')
   runtime,base=match
   if not saved:device=base['udid']
   else:
    device=subprocess.check_output(['xcrun','simctl','create','HTML Native Studio · '+name[:32]+' · '+pid[:8],base['deviceTypeIdentifier'],runtime],env=env,text=True,timeout=30).strip()
   saved[pid]=device;self.path.parent.mkdir(parents=True,exist_ok=True)
   temporary=self.path.with_suffix('.tmp');temporary.write_text(json.dumps(saved,indent=2));temporary.replace(self.path)
   return {**self.config,'ios':device,'projectID':pid}
