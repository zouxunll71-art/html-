"""Persistent per-project simulator assignments; never shuts down another device."""
import fcntl,json,os,re,subprocess,threading

# Match scripts/bootstrap.py; another app's booted phone is never a template
# preference or an assignment. Explicit installation metadata takes precedence.
DEFAULT_DEVICE_TYPE='com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'

class ProjectDevices:
 def __init__(self,root,config):
  self.path=root/'Workspace/project-devices.json';self.config=dict(config);self.lock=threading.RLock();self.templates={}
 def projects(self):
  with self.lock:return list(json.loads(self.path.read_text())) if self.path.exists() else []
 @staticmethod
 def _version(runtime):return tuple(int(v) for v in re.findall(r'\d+',runtime.get('version',runtime['identifier'])))
 def _template(self,pid,data,devices,runtimes):
  hint=self.templates.get(pid) or devices.get(self.config.get('ios'))
  preferred_runtime=self.config.get('iosRuntime') or (hint[0] if hint else None)
  preferred_type=self.config.get('iosDeviceType') or (hint[1].get('deviceTypeIdentifier') if hint else None) or DEFAULT_DEVICE_TYPE
  ordered=sorted(runtimes.values(),key=self._version,reverse=True)
  ordered.sort(key=lambda r:r['identifier']!=preferred_runtime)
  for runtime in ordered:
   types=runtime.get('supportedDeviceTypes',data.get('devicetypes',[]))
   if any(t.get('identifier')==preferred_type for t in types):return runtime['identifier'],preferred_type
  # Preserve an explicit/known device type instead of silently changing its
  # screen dimensions. Fresh installations may use an available iPhone type.
  if self.config.get('iosDeviceType') or hint:raise ValueError('缺少原项目对应的模拟器设备类型，请在 Xcode 安装兼容的 iOS 运行环境')
  for runtime in ordered:
   types=runtime.get('supportedDeviceTypes',data.get('devicetypes',[]))
   phone=next((t['identifier'] for t in types if t.get('productFamily')=='iPhone' or t.get('name','').startswith('iPhone ')),None)
   if phone:return runtime['identifier'],phone
  raise ValueError('无法找到可用的 iPhone 模拟器类型，请检查 Xcode 的 iOS 运行环境')
 def ensure(self,pid,name='Project'):
  with self.lock:
   if not isinstance(pid,str) or not pid:raise ValueError('Project ID is required')
   self.path.parent.mkdir(parents=True,exist_ok=True)
   # Separate service instances must not allocate duplicate devices or lose a
   # sibling project's mapping during concurrent startup.
   with self.path.with_suffix('.lock').open('a') as lease:
    fcntl.flock(lease,fcntl.LOCK_EX)
    saved=json.loads(self.path.read_text()) if self.path.exists() else {}
    env={**os.environ,'DEVELOPER_DIR':self.config['developerDir']}
    # This runs at activation/connect setup, not for each input event. Device
    # availability must be fresh after external deletion; only template hints
    # are cached, never the continued existence of an assigned UDID.
    data=json.loads(subprocess.check_output(['xcrun','simctl','list','--json'],env=env,timeout=20))
    devices={d['udid']:(runtime,d) for runtime,rows in data.get('devices',{}).items() for d in rows}
    runtimes={r['identifier']:r for r in data.get('runtimes',[]) if r.get('isAvailable') and '.iOS-' in r['identifier'] and self._version(r)>=(26,)}
    if not runtimes:raise ValueError('缺少可用的 iOS 26 或更新模拟器运行时，请在 Xcode 安装后重试')
    device=saved.get(pid);match=devices.get(device)
    if match and match[1].get('deviceTypeIdentifier'):self.templates[pid]=match
    if match and match[0] in runtimes and match[1].get('isAvailable') and not any(k!=pid and v==device for k,v in saved.items()):
     return {**self.config,'ios':device,'projectID':pid,'iosRuntime':match[0],'iosDeviceType':match[1]['deviceTypeIdentifier']}
    runtime,dtype=self._template(pid,data,devices,runtimes)
    # Always create a dedicated device. Even an empty mapping must not adopt an
    # existing template or unrelated booted simulator.
    device=subprocess.check_output(['xcrun','simctl','create','HTML Native Studio · '+name[:32]+' · '+pid[:8],dtype,runtime],env=env,text=True,timeout=30).strip()
    if not device or device in devices or device in saved.values():raise ValueError('模拟器创建未返回新的专用设备，请重试')
    saved[pid]=device
    temporary=self.path.with_suffix('.tmp');temporary.write_text(json.dumps(saved,indent=2));temporary.replace(self.path)
    self.templates[pid]=(runtime,{'deviceTypeIdentifier':dtype})
    return {**self.config,'ios':device,'projectID':pid,'iosRuntime':runtime,'iosDeviceType':dtype}

 def shutdown(self,pid):
  # Read the existing assignment only. Closing never allocates a device.
  with self.lock:
   saved=json.loads(self.path.read_text()) if self.path.exists() else {}
   device=saved.get(pid)
  if not device:return
  env={**os.environ,'DEVELOPER_DIR':self.config['developerDir']}
  result=subprocess.run(['xcrun','simctl','shutdown',device],env=env,capture_output=True,text=True,timeout=30)
  if result.returncode and not any(s in result.stderr for s in ['current state: Shutdown','Invalid device','Unable to shutdown device in current state: Shutdown']):
   raise ValueError('停止项目模拟器失败：'+result.stderr[-500:])
