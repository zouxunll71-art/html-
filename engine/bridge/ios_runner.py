"""User-triggered runtime builds. Never erases a device or removes app data."""
import shutil,copy,fcntl,json,os,subprocess,threading,time,uuid,contextlib,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
JOBS={};LOCK=threading.RLock();ACTIVE={};CANCELLED=set();DEVICE_LOCKS={}
def device_lock(pid):
 with LOCK:return DEVICE_LOCKS.setdefault(pid,threading.RLock())
def cancel(pid):
 with LOCK:
  job=ACTIVE.get(pid)
  if job:CANCELLED.add(job)


def status(job):
 with LOCK:
  if job not in JOBS:raise ValueError('运行任务不存在，请重新点击运行 iOS')
  return copy.deepcopy(JOBS[job])

def start(project_id,config,finish):
 global ACTIVE
 with LOCK:
  previous=ACTIVE.get(project_id)
  if previous and previous not in CANCELLED and JOBS[previous]['state']=='running':return previous
  job=uuid.uuid4().hex;ACTIVE[project_id]=job
  JOBS[job]={'id':job,'projectID':project_id,'state':'running','stage':'等待构建','progress':0,'started':time.time(),'logPath':str(ROOT/'artifacts'/('run-ios-'+job+'.log'))}
 threading.Thread(target=run,args=(job,config,finish),daemon=True).start();return job

def build_is_current(root,fingerprint):
 runtime=root/'build/runtime/Build/Products/Debug-iphonesimulator/HTMLNativeRuntime.app'
 if not (runtime/'HTMLNativeRuntime').is_file():return False
 for name in ['runtime-source.json','build-source.json']:
  try:
   if json.loads((root/'artifacts'/name).read_text()).get('fingerprint')==fingerprint:return True
  except (OSError,ValueError,TypeError):pass
 return False

def same_runtime_bundle(expected,installed):
 """Compare installed executable and resources; never trust a version label."""
 try:
  def files(root):return {str(p.relative_to(root)):p for p in root.rglob('*') if p.is_file()}
  source=files(expected);target=files(installed)
  if not source or source.keys()!=target.keys():return False
  for key,path in source.items():
   other=target[key]
   if path.stat().st_size!=other.stat().st_size:return False
   if hashlib.sha256(path.read_bytes()).digest()!=hashlib.sha256(other.read_bytes()).digest():return False
  return True
 except OSError:return False

def run(job,config,finish):
 env={**os.environ,'DEVELOPER_DIR':config['developerDir'],'SIMCTL_CHILD_STUDIO_PROJECT_ID':JOBS[job]['projectID']}
 def update(**values):
  with LOCK:JOBS[job].update(values)
 def check_cancelled():
  if job in CANCELLED:raise ValueError('工作台已关闭，启动已取消')
 def command(args,stage,progress,timeout=180,allow_failure=False):
  check_cancelled()
  update(stage=stage,progress=progress)
  with Path(JOBS[job]['logPath']).open('ab') as log:
   log.write(('\n'+stage+'\n').encode());log.flush()
   with (device_lock(JOBS[job]['projectID']) if str(args[0])=='xcrun' and 'bootstatus' not in args else contextlib.nullcontext()):
    check_cancelled()
    result=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
   check_cancelled()
  if result.returncode and not allow_failure:
   with Path(JOBS[job]['logPath']).open('rb') as log:log.seek(max(0,log.seek(0,2)-16000));detail=log.read().decode(errors='replace')
   raise ValueError(stage+'失败。\n'+detail)
 try:
  (ROOT/'artifacts').mkdir(exist_ok=True);(ROOT/'build').mkdir(exist_ok=True)
  with (ROOT/'artifacts/build.lock').open('a') as build_lock:
   fcntl.flock(build_lock,fcntl.LOCK_EX)
   from source_stamp import fingerprint
   current_source=fingerprint('build');runtime=ROOT/'build/runtime/Build/Products/Debug-iphonesimulator/HTMLNativeRuntime.app'
   if build_is_current(ROOT,current_source):update(stage='复用当前 iOS 构建',progress=60,reusedBuild=True)
   else:
    update(reusedBuild=False)
    command(['/usr/bin/python3',ROOT/'scripts/make_project.py',ROOT,'HTMLNativeRuntime','Runtime','Shared'],'准备 iOS 运行工程',10)
    command(['xcodebuild','-project','HTMLNativeRuntime.xcodeproj','-scheme','HTMLNativeRuntime','-configuration','Debug','-sdk','iphonesimulator','-derivedDataPath','build/runtime','CODE_SIGNING_ALLOWED=NO','build'],'构建 iOS 运行端',20,900)
    if not runtime.is_dir():raise ValueError('构建没有生成 iOS App，请查看运行日志')
    if fingerprint('build')!=current_source:raise ValueError('构建期间源码发生变化，请重新运行 iOS')
    stamp=ROOT/'artifacts/runtime-source.json';temporary=stamp.with_suffix('.tmp');temporary.write_text(json.dumps({'fingerprint':current_source}));temporary.replace(stamp)
   snapshot=ROOT/'build'/('run-ios-'+job+'.app');shutil.copytree(runtime,snapshot);runtime=snapshot
  devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json'],env=env,timeout=20))
  device=next((d for group in devices['devices'].values() for d in group if d['udid']==config['ios']),None)
  if device is None:raise ValueError('工作台指定的 iOS 模拟器不存在，请重新完成安装配置')
  if device['state']!='Booted':command(['xcrun','simctl','boot',config['ios']],'启动专用 iOS 模拟器',65)
  command(['xcrun','simctl','bootstatus',config['ios'],'-b'],'等待 iOS 启动',72,240)
  command(['xcrun','simctl','terminate',config['ios'],'local.htmlnative.HTMLNativeRuntime'],'停止旧的 iOS 运行端',80,allow_failure=True)
  check_cancelled();reusable=False
  with device_lock(JOBS[job]['projectID']):
   try:
    installed=subprocess.check_output(['xcrun','simctl','get_app_container',config['ios'],'local.htmlnative.HTMLNativeRuntime','app'],env=env,stderr=subprocess.DEVNULL,timeout=20).decode().strip()
    reusable=same_runtime_bundle(runtime,Path(installed)) if installed else False
   except (subprocess.SubprocessError,OSError):pass
  update(reusedInstall=reusable)
  if reusable:update(stage='复用已安装的 iOS 运行端',progress=85)
  else:command(['xcrun','simctl','install',config['ios'],runtime],'安装更新（保留 App 数据）',85)
  command(['xcrun','simctl','launch',config['ios'],'local.htmlnative.HTMLNativeRuntime'],'重新启动 iOS App',93)
  update(stage='恢复页面与同步连接',progress=98)
  check_cancelled()
  result=finish(JOBS[job]['projectID'])
  update(state='done',stage='iOS 已启动，正在确认两端画面',progress=100,result=result,finished=time.time())
 except Exception as error:update(state='failed',stage='运行未完成',error=str(error),finished=time.time())
 finally:
  if 'snapshot' in locals():shutil.rmtree(snapshot,ignore_errors=True)
