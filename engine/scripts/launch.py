#!/usr/bin/env python3
"""Desktop launch with source-aware rebuilds and versioned local service recovery."""
import subprocess,os,json,time,urllib.request,fcntl,signal,sys
from pathlib import Path
from source_stamp import fingerprint
# Legacy desktop shortcuts must open the installed current client, without restarting its engine.
client=Path('/Applications/HTML Native Studio.app')
if '--headless' not in sys.argv and client.is_dir():
 subprocess.run(['/usr/bin/open',str(client)],check=True)
 sys.exit(0)
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
config=json.loads((ROOT/'bridge/config.json').read_text());env=dict(os.environ,DEVELOPER_DIR=config['developerDir'])
(ROOT/'artifacts').mkdir(exist_ok=True);(ROOT/'build').mkdir(exist_ok=True)
lock=(ROOT/'artifacts/launch.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX)
def run(args,check=True,timeout=180):
 result=subprocess.run(list(map(str,args)),env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
 if check and result.returncode:raise RuntimeError(result.stdout.decode(errors='replace')[-8000:])
 return result

def request(path,body=None):
 req=urllib.request.Request('http://127.0.0.1:'+str(config['port'])+path,headers={'X-Studio-Token':(ROOT/'bridge/token').read_text().strip(),'Content-Type':'application/json'},data=json.dumps(body).encode() if body is not None else None)
 return json.load(urllib.request.urlopen(req,timeout=3))
def health():
 try:return request('/health')
 except Exception:return {}
def processes():
 rows=run(['/bin/ps','-ax','-o','pid=,ppid=,command=']).stdout.decode().splitlines();result=[]
 for row in rows:
  fields=row.strip().split(None,2)
  if len(fields)==3:result.append((int(fields[0]),int(fields[1]),fields[2]))
 return result
studio=ROOT/'build/studio/Build/Products/Debug-maccatalyst/HTMLNativeStudio.app'
runtime=ROOT/'build/runtime/Build/Products/Debug-iphonesimulator/HTMLNativeRuntime.app'
stamp_path=ROOT/'artifacts/build-source.json'
try:built=json.loads(stamp_path.read_text()).get('fingerprint')
except Exception:built=None
headless='--headless' in sys.argv
if headless:env['STUDIO_HEADLESS']='1'
needs_build=(not headless and not studio.exists()) or not runtime.exists() or not (ROOT/'build/ios-frames').exists() or not (ROOT/'build/ios-input').exists() or built!=fingerprint('build')
if needs_build:
 executable=str(studio/'Contents/MacOS/HTMLNativeStudio')
 if any(command==executable or command.startswith(executable+' ') for _,_,command in processes()):
  raise RuntimeError('工作台有源码更新。请先保存布局并退出当前 HTML 原生工作台，再双击桌面图标；随后会自动构建新版。')
 print('检测到更新，正在构建工作台。详细日志在 artifacts/studio-build.log 和 runtime-build.log…',flush=True)
 with (ROOT/'artifacts/build.lock').open('a') as build_lock:
  fcntl.flock(build_lock,fcntl.LOCK_EX);run(['/bin/zsh',ROOT/'scripts/build.sh'],timeout=1800)
loaded=health();restore=None
if loaded.get('ok') and loaded.get('version')!=fingerprint('service'):
 if loaded.get('root',str(ROOT))!=str(ROOT):raise RuntimeError('另一个安装目录正在使用本机服务端口，请先退出那个版本。')
 # Verify the old service command before terminating exactly this installation.
 services=[(pid,ppid,cmd) for pid,ppid,cmd in processes() if cmd.endswith(str(ROOT/'bridge/server.py')) and ('python' in cmd.split()[0].lower())]
 if len(services)!=1:raise RuntimeError('无法确认旧同步服务的进程归属，请手动退出旧版本后重开。')
 restore=request('/status');pid=services[0][0]
 children=[child for child,parent,cmd in processes() if parent==pid and str(ROOT/'bridge/engine_worker.js') in cmd]
 print('正在更新本机同步服务，保留项目和布局…',flush=True)
 os.kill(pid,signal.SIGTERM)
 for child in children:
  try:os.kill(child,signal.SIGTERM)
  except ProcessLookupError:pass
 for _ in range(50):
  if not health():break
  time.sleep(.1)
 if health():raise RuntimeError('旧同步服务仍在退出，请稍后重开。')
if not health().get('ok'):
 print('正在启动同步服务…',flush=True)
 with (ROOT/'artifacts/service.log').open('ab') as out:
  subprocess.Popen(['/usr/bin/python3',str(ROOT/'bridge/server.py')],env=env,stdout=out,stderr=out,start_new_session=True)
 for _ in range(100):
  if health().get('ok'):break
  time.sleep(.1)
 if not health().get('ok'):raise RuntimeError('同步服务未启动，请查看 artifacts/service.log')
if restore and restore.get('active'):
 request('/activate-project',{'id':restore['active']})
 # Restore flags without copying one side's session over the other.
 request('/restore-mode',{'linked':restore.get('linked',True),'editing':restore.get('editing',True)})
print('正在准备独立 iOS 模拟器…',flush=True)
devices=json.loads(run(['xcrun','simctl','list','devices','available','--json']).stdout)['devices']
device=next((d for group in devices.values() for d in group if d['udid']==config['ios']),None)
if not device:raise RuntimeError('找不到工作台专用模拟器，请检查安装配置。')
if device['state']!='Booted':run(['xcrun','simctl','boot',config['ios']])
run(['xcrun','simctl','bootstatus',config['ios'],'-b'],timeout=240)
run(['xcrun','simctl','status_bar',config['ios'],'override','--time','9:41','--batteryState','charged','--batteryLevel','100'])
run(['xcrun','simctl','terminate',config['ios'],'local.htmlnative.HTMLNativeRuntime'],False)
run(['xcrun','simctl','install',config['ios'],runtime]);run(['xcrun','simctl','launch',config['ios'],'local.htmlnative.HTMLNativeRuntime'])
# Codex companion: window visibility does not stop the service or simulator.
control=Path.home()/'Library/Application Support/HTMLNativeStudio-CodexControl'
preferences=ROOT/'artifacts/codex-window-preferences.json'
quiet=json.loads(preferences.read_text()).get('defaultHidden',True) if preferences.exists() else False
print('正在后台准备工作台…' if quiet else '正在打开 HTML 原生工作台…',flush=True)
if '--headless' not in sys.argv:
 run(['open','-gj',studio] if quiet else ['open',studio])
else:
 print('后台服务与模拟器已就绪，由新版客户端显示工作台。',flush=True)

