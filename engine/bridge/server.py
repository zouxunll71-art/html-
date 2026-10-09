#!/usr/bin/env python3
from browser_preview import BrowserPreview
from record_cache import RecordCache
import performance_trace
RECORD_CACHE=RecordCache()
SUMMARY_CACHE={}
import host_export
import export_policy
from source_watch import signature
from state_defaults import fill_missing
import json,os,time,uuid,hashlib,threading,subprocess,shutil,mimetypes,copy,traceback,sys,signal,atexit
from pathlib import Path
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs,unquote
from compiler import compile_project
import authoring
import source_resources
import conversion_audit
import model_paint_storage
import asset_thumbnails
from asset_previews import PREVIEWS
import asset_compression
import ios_rules
import ios_export
import ios_runner
import export_jobs
from ios_input import SimulatorInput
from ios_frames import SimulatorFrames
from project_devices import ProjectDevices
from local_surface import LocalSurface
ROOT=Path(__file__).resolve().parents[1];STORE=ROOT/'Workspace';CONFIG=json.loads((ROOT/'bridge/config.json').read_text());TOKEN=(ROOT/'bridge/token').read_text().strip()
DEVICES=ProjectDevices(ROOT,CONFIG)
STARTED_DEVICES={} # project -> successfully scheduled device UDID
ENABLED_PROJECTS=set()
WORKBENCH_LOCK=threading.RLock()
def require_workbench(pid):
 if pid not in ENABLED_PROJECTS:raise ValueError("此项目工作台已关闭，请先点击开启工作台")

IOS_INPUT=SimulatorInput(ROOT,CONFIG)
PROJECT_INPUTS={}
PROJECT_DEVICE_CONFIGS={}
def project_input(pid):
 # Existing connections are a hot path: no inventory scan or process cleanup.
 with LOCK:
  require_workbench(pid)
  if pid in PROJECT_INPUTS:return PROJECT_INPUTS[pid]
 with WORKBENCH_LOCK:
  with LOCK:
   require_workbench(pid)
   if pid in PROJECT_INPUTS:return PROJECT_INPUTS[pid]
   config=PROJECT_DEVICE_CONFIGS.get(pid)
  if config is None:config=resolve_project_device(pid)
  with LOCK:
   require_workbench(pid)
   connection=SimulatorInput(ROOT,config);PROJECT_INPUTS[pid]=connection
   return connection
IOS_FRAMES=SimulatorFrames(ROOT,CONFIG)
LOCAL_SURFACE=LocalSurface(ROOT,CONFIG)
sys.path.insert(0,str(ROOT/'scripts'))
from source_stamp import fingerprint
SERVICE_VERSION=fingerprint('service')
LOCK=threading.RLock();ENGINE_LOCK=threading.Lock();REV=time.time_ns()//1000000;ACTIVE=None;ERROR='';ACK={};LINKED=True;EDITING=True;PROCESSED={};lastWatch={};CHROME_TARGETS={};BROWSER_OPEN={};CLOSE_BROWSER=set()
worker=subprocess.Popen([CONFIG['node'],str(ROOT/'bridge/engine_worker.js')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
ENGINE_MODEL_KEYS=[]
def eng(op,**args):
 global ENGINE_MODEL_KEYS
 with ENGINE_LOCK:
  model=args.get('model');key=json.dumps([model.get('id'),model['hash']]) if isinstance(model,dict) and model.get('hash') else None
  if key:
   args['modelKey']=key
   if key in ENGINE_MODEL_KEYS:args.pop('model')
  worker.stdin.write(json.dumps(dict(op=op,**args),ensure_ascii=False)+'\n');worker.stdin.flush();reply=json.loads(worker.stdout.readline())
  if key:
   if key in ENGINE_MODEL_KEYS:ENGINE_MODEL_KEYS.remove(key)
   ENGINE_MODEL_KEYS.append(key);ENGINE_MODEL_KEYS=ENGINE_MODEL_KEYS[-16:]
 if 'error'in reply:raise ValueError(reply['error'])
 return reply['ok']
def atomic(p,v,compact=False):p.parent.mkdir(parents=True,exist_ok=True);t=p.with_suffix('.tmp');t.write_text(json.dumps(v,ensure_ascii=False,**({'separators':(',',':')} if compact else {'indent':2})));t.replace(p)
def folder(pid):
 if not isinstance(pid,str) or not all(c in '0123456789abcdef-' for c in pid):raise ValueError('无效项目 ID')
 p=STORE/pid
 if not (p/'record.json').exists():raise ValueError('项目不存在')
 return p
def read(pid):return RECORD_CACHE.read(folder(pid)/'record.json')
def bump():
 global REV
 REV+=1

def sessions(model):return {s:eng('initial',model=model) for s in ['web','ios']}
def frame_arguments(r,side='ios',base=False):
 session=r['sessions'][side]
 if mode_for(r)[1]:session={**session,'editingPage':session['stack'][-1]['page']}
 if side=='ios' and not base:return dict(kind='compose',session=session,overrides=r.get('overrides',{}),additions=r.get('additions',{}))
 return dict(kind='frame',session=session)
def frame(r,side='ios',base=False):
 args=frame_arguments(r,side,base);kind=args.pop('kind')
 return eng(kind,model=r['model'],**args)

def project(r):
 pages=[]
 for pid,p in r['model']['pages'].items():
  session=eng('initial',model=r['model']);session['stack']=[{'page':pid,'params':{}}]
  temp={**r,'sessions':{'ios':session}};out=eng('editor',frame=frame(temp));out['paintOrderVersion']=1;pages.append(out)
 current=eng('editor',frame=frame(r));pages=[current if p['id']==current['id'] else p for p in pages]
 return dict(schemaVersion=1,id=r['id'],name=r['model']['name'],sourcePath=r['source'],package='',assets=r['model']['assets'],pages=pages,pageCandidates=[],updated=r['updated'],importMode='html',selectionColor=r.get('selectionColor','#147DF5'),compileRevision=r['model']['hash'])
def mode_for(r):
 if '_snapshotMode' in r:return r['_snapshotMode']
 return (LINKED,EDITING) if r['id']==ACTIVE else (r.get('runtimeMode',{}).get('linked',True),r.get('runtimeMode',{}).get('editing',False))
def resolve_project_device(pid):
 # Lifecycle callers enter without LOCK. Startup is serialized with activation
 # and disable, while inventory/process waits cannot block ordinary events.
 with WORKBENCH_LOCK:
  with LOCK:require_workbench(pid);name=read(pid)['model']['name']
  config=DEVICES.ensure(pid,name);old_input=None;close_frames=False
  with LOCK:
   require_workbench(pid)
   previous=PROJECT_DEVICE_CONFIGS.get(pid);connection=PROJECT_INPUTS.get(pid)
   old_ids=[previous.get('ios') if previous else None,connection.config.get('ios') if connection else None,STARTED_DEVICES.get(pid)]
   if any(value and value!=config['ios'] for value in old_ids):
    old_input=PROJECT_INPUTS.pop(pid,None);STARTED_DEVICES.pop(pid,None)
    LOCAL_SURFACE.invalidate(pid);ios_runner.cancel(pid)
   capture_config=IOS_FRAMES.config
   close_frames=capture_config.get('projectID')==pid and capture_config.get('ios')!=config['ios']
   PROJECT_DEVICE_CONFIGS[pid]=config
  if old_input:old_input.close()
  if close_frames:
   IOS_FRAMES.close()
   with LOCK:
    if ACTIVE==pid and IOS_FRAMES.config is capture_config:IOS_FRAMES.config=config
  return config

def start_resolved_device(pid,config,force=False):
 # Caller owns WORKBENCH_LOCK, never LOCK while starting the runner.
 with LOCK:
  require_workbench(pid)
  if not force and STARTED_DEVICES.get(pid)==config['ios']:return None
 job=ios_runner.start(pid,config,finish_ios_run)
 with LOCK:STARTED_DEVICES[pid]=config['ios']
 return job

def select_device(pid):
 with WORKBENCH_LOCK:
  config=resolve_project_device(pid)
  with LOCK:
   if ACTIVE!=pid:raise ValueError('项目已切换，请重新打开工作台')
  if IOS_FRAMES.config.get('ios')!=config['ios']:IOS_FRAMES.close()
  with LOCK:
   if ACTIVE!=pid:raise ValueError('项目已切换，请重新打开工作台')
   IOS_FRAMES.config=config
  start_resolved_device(pid,config)
  return config
def local_surface_device(pid):
 # Caller owns LOCK. Read an existing assignment only; a local preview never
 # creates/boots a device, and cannot subscribe to a different selected project.
 if not isinstance(pid,str) or not pid or pid!=ACTIVE:raise ValueError('Local surface requires the selected project')
 require_workbench(pid)
 # ProjectDevices publishes the mapping by atomic replace. A reader observes
 # either complete assignment; it must not wait on the inventory/create lock
 # while holding the editor state lock. Start rechecks this assignment below.
 try:saved=json.loads(DEVICES.path.read_text())
 except FileNotFoundError:saved={}
 device=saved.get(pid)
 if not device:raise ValueError('Project simulator has not been assigned')
 return device

def store(r):RECORD_CACHE.write(STORE/r['id']/'record.json',r)
def publish_assets(r):
 d=STORE/r['id']/'assets';d.mkdir(parents=True,exist_ok=True)
 for a in r['model']['assets']:
  if not (d/a['file']).exists():shutil.copy2(Path(r['source'])/a['source'],d/a['file'])
def import_project(path):
 global ACTIVE,ERROR
 source=Path(path).expanduser().resolve();model=compile_project(source)
 for p in STORE.glob('*/record.json'):
  r=json.loads(p.read_text())
  if r['source']==str(source):
   if ACTIVE!=r['id']:LOCAL_SURFACE.invalidate()
   ACTIVE=r['id'];recompile(r,model);return project(read(ACTIVE))
 all_base_nodes({'model':model})
 pid=str(uuid.uuid4());r=dict(id=pid,source=str(source),model=model,sessions=sessions(model),overrides={},additions={},conflicts=[],updated=time.time())
 (STORE/pid).mkdir();publish_assets(r);store(r);LOCAL_SURFACE.invalidate();ACTIVE=pid;ERROR='';bump();return project(r)
def all_base_nodes(r):
 nodes={}
 for pid in r['model']['pages']:
  session=eng('initial',model=r['model']);session['stack']=[{'page':pid,'params':{}}]
  base=eng('frame',model=r['model'],session=session)
  editor=eng('editor',frame=base)
  problems,_=conversion_audit.compare_frames(base,editor,editor=True)
  if problems:raise ValueError('转换完整性检查失败：'+pid+' · '+problems[0][0]+' · '+problems[0][1])
  for n in base['nodes']:nodes[n.get('sharedKey') or n['id']]=n
 return nodes

def recompile(r,model):
 global ERROR
 if model['hash']==r['model']['hash']:
  changed=False
  for s in r['sessions'].values():changed=fill_missing(s['state'],model['state']) or changed
  if changed:store(r);bump()
  ERROR='';return
 # Validate every page with initial data before making this revision visible.
 temp={**r,'model':model};new=all_base_nodes(temp);conflicts=[]
 for key,v in r['overrides'].items():
  n=new.get(key)
  if n is None:conflicts.append(dict(key=key,field='*',reason='源图层已删除',ios=v['patch']));continue
  if n['type']!=v['type']:conflicts.append(dict(key=key,field='*',reason='源组件类型已改变',ios=v['patch']))
  for field,value in v['patch'].items():
   old=v['base'].get(field);html=n.get(field)
   if html!=old and html!=value:conflicts.append(dict(key=key,field=field,base=old,html=html,ios=value,reason='HTML 与 iOS 修改了同一属性'))
 if model['stateVersion']!=r['model']['stateVersion']:raise ValueError('stateVersion 改变：先备份，再通过“重置运行状态”明确迁移；当前继续使用上一版')
 r['model']=model;r['conflicts']=conflicts
 for side,s in r['sessions'].items():
  fill_missing(s['state'],model['state'])
  s['stack']=[p for p in s['stack'] if p['page'] in model['pages']] or [{'page':model['entry'],'params':{}}]
  s['modals']=[p for p in s['modals'] if p in model['pages']]
 publish_assets(r);r['updated']=time.time();store(r);ERROR='';bump()
def update_edits(persist,body):
 r=read(body.get('id') or body['projectID'])
 if body.get('compileRevision') and body['compileRevision']!=r['model']['hash']:
  # Keep the rejected editor payload for recovery. Never apply old full-page snapshots to new HTML.
  if persist:
   digest=hashlib.sha256(json.dumps(body,sort_keys=True,ensure_ascii=False).encode()).hexdigest()[:20]
   backup=folder(r['id'])/'rejected-edits'/(digest+'.json')
   if not backup.exists():atomic(backup,dict(reason='source-revision-changed',savedAt=time.time(),projectID=r['id'],currentRevision=r['model']['hash'],draft=body))
  raise ValueError('HTML 已更新，旧编辑不会覆盖新源码；未保存调整已保留，请刷新编辑器')
 pages=body.get('pages') or [body['page']]
 if persist:atomic(folder(r['id'])/'versions'/f'{time.time_ns()}.json',r)
 for edit in pages:
  # Save only current visible page to avoid default data pages clobbering live state.
  if edit['id']!=r['sessions']['ios']['stack'][-1]['page']:continue
  raw=frame(r,base=True);base=eng('editor',frame=raw);rawmap={n['id']:n for n in raw['nodes']};basemap={n['id']:n for n in base['nodes']}
  # Reuse the editor snapshot already obtained above instead of sending the
  # same 2000-node frame through the JS worker for a second flatten/diff.
  ignored={'id','source','sharedKey','textKey','placeholderKey','symbol','selected'}
  diffs={}
  for edited in edit['nodes']:
   nid=edited['id'];old=basemap.get(nid)
   if old is None:diffs[nid]=edited;continue
   delta={k:v for k,v in edited.items() if k not in ignored and (k not in old or v!=old.get(k) or isinstance(v,bool)!=isinstance(old.get(k),bool))}
   delta=export_policy.meaningful_patch(delta,old)
   if delta:diffs[nid]=delta
  edited_ids={n['id'] for n in edit['nodes']}
  for nid in basemap:
   if nid not in edited_ids:diffs[nid]={'hidden':True}
  add=[]
  editmap={n['id']:n for n in edit['nodes']}
  # Invert editor page coordinates using this exact edit snapshot, including
  # moved parents and scroll offsets, not the unedited source hierarchy.
  for nid,edited in editmap.items():
   if nid not in rawmap:continue
   original=rawmap[nid];parent=editmap.get(edited.get('parent',''))
   patch=diffs.setdefault(nid,{})
   if edited.get('parent','')!=original.get('parent',''):patch['parent']=edited.get('parent','')
   for axis,offset in (('x','scrollX'),('y','scrollY')):
    value=edited[axis]-(parent[axis] if parent else 0)
    if parent and parent.get('type')=='scroll':value+=parent.get(offset,0) or 0
    if abs(value-original[axis])>0.000001:patch[axis]=value
    else:patch.pop(axis,None)
   # Scrolling is session state, never an appearance override.
   for field in ('scrollX','scrollY'):patch.pop(field,None)
  source_keys={n.get('sharedKey') or n['id'] for n in raw['nodes']}
  for key in list(r['overrides']):
   if key in source_keys:r['overrides'].pop(key)
  for nid,patch in diffs.items():
   if nid not in rawmap:add.append(patch);continue
   n=rawmap[nid]
   stable=n.get('sharedKey') or nid
   if patch:r['overrides'][stable]={'type':n['type'],'base':copy.deepcopy(n),'baseFrame':copy.deepcopy(basemap[nid]),'patch':patch}
  # New/copied nodes retain their hierarchy. The editor sends page coordinates.
  editmap={n['id']:n for n in edit['nodes']}
  addids={n['id'] for n in add}
  oldadd={n['id']:n for n in r.get('additions',{}).get(edit['id'],[])}
  displayed={n['id']:n for n in frame(r)['nodes']} if add else {}
  normalized=[]
  for n in add:
   n={**oldadd.get(n['id'],{}),**n};parent=n.get('parent','')
   if parent and parent in editmap:
    for axis in ('x','y'):n[axis]-=editmap[parent][axis]
    if editmap[parent]['type']=='scroll':
     n['x']+=editmap[parent].get('scrollX',0);n['y']+=editmap[parent].get('scrollY',0)
   elif parent:n['parent']=''
   old=displayed.get(n['id'],oldadd.get(n['id'],{}))
   if old.get('origin'):
    changed=set(n.get('manualFields',[]))|{k for k in ('text','placeholder','options','asset','symbol','fontName') if n.get(k)!=old.get(k)}
    n['manualFields']=sorted(changed)
    if changed & {'text','placeholder','options'}:n['manualContent']=True
   normalized.append(n)
  r['additions'][edit['id']]=normalized
 r['selectionColor']=body.get('selectionColor',r.get('selectionColor','#147DF5'));r['updated']=time.time();store(r);bump();return project(r) if persist else {'ok':True,'revision':REV}
def event(body,project_id=None,trace=None,browser=False):
 with performance_trace.span(trace,'event.validation'):
  pid=project_id or ACTIVE;r=read(pid);linked,editing=mode_for(r);side=body.get('side','web');eid=body.get('eventID');tag=(pid,side,eid)
  if browser:linked,editing=False,False;r['_snapshotMode']=(False,False)
  if trace:trace.bind(project_id=pid,event_id=eid,side=side,revision=REV)
  if eid and tag in PROCESSED:return {'revision':REV}
  if side not in ('web','ios'):raise ValueError('Unknown side')
  s=r['sessions'][side];e=body['event']
  if body.get('projectID',pid)!=pid:raise ValueError('项目已切换，操作已停止')
  if body.get('pageID') and body['pageID']!=s['stack'][-1]['page']:raise ValueError('页面已切换，操作已停止')
  if e.get('type') not in ('navigate','back','scroll','locale','chromeInsets','tab','popTo','effectComplete','photoResult'):
   interaction=eng('interaction',model=r['model'],node=e.get('node'),**frame_arguments(r,side));decl=interaction['declaration']
   if decl is None and side=='ios':
    added=next((n for n in r.get('additions',{}).get(interaction['pageID'],[]) if n['id']==e.get('node')),None)
    if added and not added.get('hidden') and not added.get('disabled'):
     field='text' if added['type'] in ('nativeTextField','nativeTextView') else 'isOn' if added['type'] in ('nativeCheckbox','nativeSwitch') else 'value'
     if 'value' in e:added[field]=e['value']
     with performance_trace.span(trace,'event.persist'):store(r)
     bump()
     if trace:trace.bind(revision=REV)
     return {'revision':REV}
   if decl is None or decl.get('disabled'):raise ValueError('图层不可交互或已失效')
   e={**decl,'value':e.get('value')}
  if e.get('preview') and not editing and not (browser and e.get('type')=='navigate'):raise ValueError('请先切换到选取与编辑模式')
  e={**e,'clock':{'now':time.time()*1000,'offsetMinutes':-time.localtime().tm_gmtoff/60}}
 with performance_trace.span(trace,'event.reducer'):s=eng('event',model=r['model'],session=s,event=e)
 r['sessions'][side]=s;r['modelCommandSide']=side
 if linked:r['sessions']['web' if side=='ios' else 'ios']=copy.deepcopy(s)
 r['updated']=time.time()
 r.pop('_snapshotMode',None)
 with performance_trace.span(trace,'event.persist'):store(r)
 bump();schedule_effects(r,side,browser=browser)
 if trace:trace.bind(revision=REV)
 if eid:PROCESSED[tag]=REV
 if len(PROCESSED)>1000:PROCESSED.clear()
 return {'revision':REV}
PENDING_TIMERS={}
def schedule_effects(record,side,browser=False):
 for eid,effect in record['sessions'][side].get('pendingEffects',{}).items():
  key=(record['id'],side,eid)
  if key in PENDING_TIMERS:continue
  def complete(key=key,browser=browser):
   try:
    with LOCK:
     if key[0] not in ENABLED_PROJECTS and not (browser and key[0] in BROWSER.active_projects()):return
     event({'side':key[1],'projectID':key[0],'event':{'type':'effectComplete','id':key[2]}},key[0],browser=browser)
   except Exception as error:
    global ERROR
    with LOCK:
     if ACTIVE==key[0]:ERROR='延时动作执行失败：'+str(error)
   finally:PENDING_TIMERS.pop(key,None)
  timer=threading.Timer(effect['duration'],complete);timer.daemon=True;PENDING_TIMERS[key]=timer;timer.start()
def runtime(side,known_project='',known_model='',project_id=None,trace=None):
 pid=project_id or ACTIVE
 if not pid:return dict(revision=REV,model=None)
 r=read(pid);linked,editing=mode_for(r);schedule_effects(r,side)
 with performance_trace.span(trace,'runtime.compose'):page=frame(r,side)
 seen=set(r.get('effectAcks',{}).get(side,[]));page['chromeHitTargets']=CHROME_TARGETS.get((pid,page['id']),[]) if side=='ios' else [];page['browserOpen']=BROWSER_OPEN.get(pid,False) if side=='ios' else False;page['closeBrowser']=pid in CLOSE_BROWSER if side=='ios' else False;page['effects']=[e for e in page.get('effects',[]) if e['id'] not in seen]
 for node in page.get('nodes',[]):
  if node.get('modelAsset'):node['paintCommandOwner']=r.get('modelCommandSide',side)
 result=dict(revision=REV,projectID=pid,session=r['sessions'][side],page=page,sourceSignature=source_resources.signature(page) if side=='web' and editing else '',editing=editing,linked=linked,modelHash=r['model']['hash'])
 if known_project==pid and known_model==r['model']['hash']:result['reuseModel']=True
 else:result.update(model=r['model'],assets=r['model']['assets'])
 return result
def export(r,progress=lambda stage,percent:None):
 progress("检查本地化、动作与路由",5)
 r,resolution=export_policy.prepare(r)
 issues=ios_rules.export_issues(r)
 if issues:raise ValueError('导出规则检查未通过：\n'+'\n'.join(issues[:12]))
 fresh=compile_project(r['source'])
 if fresh['hash']!=r['model']['hash']:raise ValueError('源码尚未同步，请等待同步完成后导出')
 progress('核对全部页面、弹窗和资源文件',15)
 audit=conversion_audit.inspect_project(r,folder(r['id'])/'assets',eng)
 errors=[i['message'] for i in audit['issues'] if i['level']=='error']
 if errors:raise ValueError('资源与页面检查未通过：\n'+'\n'.join(errors[:12]))
 name=''.join(c if c not in '/\\:' else '-' for c in r['model']['name']).strip('. ') or 'NativeApp'
 source=Path(r['source']).resolve()
 bundle=source.parent if source.name=='HTML' and source.parent.name=='HTMLNativeStudio' else source if source.name=='HTMLNativeStudio' else source/'HTMLNativeStudio'
 bundle=host_export.resolve_bundle(bundle)
 host_plan=host_export.inspect(bundle)
 (bundle/'iOS').mkdir(parents=True,exist_ok=True)
 if source != bundle/'HTML' and not (bundle/'HTML').exists():
  shutil.copytree(source,bundle/'HTML',ignore=shutil.ignore_patterns('HTMLNativeStudio','HTML','iOS','.git','node_modules','build','.DS_Store'))
 out=bundle/'iOS'/name;i=2
 while out.exists():out=bundle/'iOS'/f'{name}-{i}';i+=1
 staging=out.with_name('.'+out.name+'.partial-'+uuid.uuid4().hex)
 try:
  progress('生成原生工程和语言文件',30)
  target=ios_export.prepare(r,staging,ROOT,folder(r['id'])/'assets',progress)
  atomic(staging/'IOSExportResolution.json',resolution)
  progress('写入 Xcode 工程与导出清单',90)
  subprocess.run(['/usr/bin/python3',str(ROOT/'scripts/make_project.py'),str(staging),target,'App','Shared'],check=True,env={**os.environ,'STUDIO_BUNDLE_ID':'local.htmlnative.export.p'+hashlib.sha256(r['model']['id'].encode()).hexdigest()[:16],'STUDIO_MIN_IOS':'15.0','STUDIO_NATIVE_EXPORT':'1'})
  (staging/'README.md').write_text('Open '+target+'.xcodeproj. UIKit renders all declared pages and dialogs. Native navigation, actions, localization and image assets are included. No studio connection is required. Check ExportInventory.json for the complete inventory. This export has not been built automatically.\n')
  if out.exists():raise ValueError('导出目标刚刚被创建，请重新导出以使用新的序号')
  staging.rename(out)
 except Exception:
  if staging.exists():shutil.rmtree(staging)
  raise
 if host_plan:
  progress('迁移到外层 Xcode 工程（保留工程配置）',96)
  destination=host_export.migrate(host_plan,out,r['model']['ios']['classPrefix'])
 else:destination=str(out)
 return destination
def finish_ios_run(pid):
 with LOCK:
  require_workbench(pid)
  read(pid)
  if ACTIVE==pid:ACK.clear()
  bump();return {'revision':REV,'projectID':pid,'projectChanged':ACTIVE!=pid}

BROWSER=BrowserPreview(globals())

def watch():
 global ERROR
 while True:
  time.sleep(.25)
  with LOCK:targets=list(ENABLED_PROJECTS | BROWSER.active_projects())
  for pid in targets:
   try:
    with LOCK:r=read(pid)
    sig=signature(Path(r['source']))
    if sig==lastWatch.get(pid):continue
    lastWatch[pid]=sig;time.sleep(.15);started=time.monotonic();model=compile_project(r['source'])
    with LOCK:
     previous_error=ERROR
     try:
      if pid in ENABLED_PROJECTS or pid in BROWSER.active_projects():recompile(read(pid),model);BROWSER.errors.pop(pid,None)
     finally:
      if ACTIVE!=pid:ERROR=previous_error
    (ROOT/'artifacts/last-compile-ms.txt').write_text(str(round((time.monotonic()-started)*1000,1)))
   except Exception as e:
    with LOCK:
     BROWSER.errors[pid]=str(e)
     if ACTIVE==pid:ERROR=str(e)
class Handler(BaseHTTPRequestHandler):
 # Small interactive replies must not wait for TCP packet coalescing.
 disable_nagle_algorithm=True
 def log_message(self,*a):pass
 def respond(self,value,code=200,mime='application/json',cache='no-store'):
  # Freeze the response while the state lock still protects its values. Socket
  # writes happen only after the request handler unwinds every state lock.
  with performance_trace.span(getattr(self,'_performance_trace',None),'response.serialize'):
   raw=value if isinstance(value,bytes) else json.dumps(value,ensure_ascii=False).encode()
  return raw,code,mime,cache
 def do_GET(self):self.handle_request()
 def do_POST(self):self.handle_request()
 def handle_request(self):
  trace=performance_trace.begin(self.path,self.headers);self._performance_trace=trace
  code=500;disconnected=False
  try:
   response=self._handle_request()
   if response is None:return # Streaming endpoints own their response lifecycle.
   raw,code,mime,cache=response
   with performance_trace.span(trace,'response.write'):
    try:
     self.send_response(code);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control',cache);self.end_headers();self.wfile.write(raw)
    except (BrokenPipeError,ConnectionResetError):disconnected=True
  finally:
   # _handle_request has unwound every state lock. Diagnostic IO must not
   # compete with event mutation or delay this request's HTTP reply.
   if trace:trace.finish(code,disconnected)
   self._performance_trace=None
 def _handle_request(self):
  global ACTIVE,ERROR,LINKED,EDITING
  u=urlparse(self.path);q=parse_qs(u.query);path=u.path
  if path=='/browser' and self.command=='GET':
   html=(ROOT/'Web/index.html').read_text()
   start=html.index('<script>const TOKEN=');end=html.index('</script>',start)+len('</script>')
   bootstrap="<script>const TOKEN=location.hash.slice(1);const script=document.createElement('script');script.src='/browser.js?token='+encodeURIComponent(TOKEN);script.onerror=()=>{const e=document.getElementById('error');e.textContent='预览链接未绑定或已失效，请重新运行浏览器预览命令。';e.style.display='block'};document.head.append(script)</script>"
   return self.respond((html[:start]+bootstrap+html[end:]).encode(),mime='text/html; charset=utf-8')
  credential=self.headers.get('X-Studio-Token') or q.get('token',[''])[0]
  if BROWSER.owns(credential):return BROWSER.request(self,u,q,credential)
  if path in ('/model-paint.js','/model-vendor/three.module.js','/model-vendor/three.core.js','/model-vendor/GLTFLoader.js','/model-vendor/BufferGeometryUtils.js'):
   return self.respond((ROOT/'Web'/path.lstrip('/')).read_bytes(),mime='text/javascript')
  if self.headers.get('X-Studio-Token')!=TOKEN and q.get('token',[''])[0]!=TOKEN:return self.respond({'error':'Unauthorized'},403)
  try:
   trace=getattr(self,'_performance_trace',None)
   with performance_trace.span(trace,'request.decode'):
    body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or b'{}')
   if path=='/browser-attach':
    if self.command!='POST':raise ValueError('POST required')
    return self.respond(BROWSER.attach(body['source']))
   bound=self.headers.get('X-Studio-Project')
   if bound:read(bound)
   target=bound or ACTIVE
   if bound and body.get('projectID',bound)!=bound:raise ValueError('运行端项目不匹配')
   if path in ('/local-surface/start','/local-surface/ping','/local-surface/stop'):
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    pid=body.get('projectID');session=body.get('session')
    if not isinstance(pid,str) or not pid:raise ValueError('Local surface projectID is required')
    if path=='/local-surface/stop':return self.respond({'ok':True,'stopped':LOCAL_SURFACE.stop(pid,session)})
    with LOCK:
     device=local_surface_device(pid)
     if path=='/local-surface/ping':reply=LOCAL_SURFACE.ping(pid,session)
     else:ticket=LOCAL_SURFACE.reserve(pid,device,session,body.get('service'))
    if path=='/local-surface/ping':return self.respond(reply)
    try:
     executable=LOCAL_SURFACE.prepare(ticket) # boot-state check/build outside LOCK
     with LOCK:
      if local_surface_device(pid)!=ticket.device or not LOCAL_SURFACE.valid(ticket):raise ValueError('Local surface activation changed')
     # Manager generation is checked again during spawn. Selection/close hooks
     # cancel old tickets even if the user switched away and back during build.
     return self.respond(LOCAL_SURFACE.start(ticket,executable))
    except Exception:
     LOCAL_SURFACE.cancel(ticket);raise
   if path=='/workbench':
    if self.command!='POST' or not isinstance(body.get('enabled'),bool):raise ValueError('需要明确开启或关闭工作台')
    pid=body.get('id');read(pid)
    with WORKBENCH_LOCK:
     if body['enabled']:
      model=compile_project(read(pid)['source'])
      with LOCK:
       recompile(read(pid),model);ENABLED_PROJECTS.add(pid)
       if ACTIVE!=pid:LOCAL_SURFACE.invalidate()
       ACTIVE=pid;mode=read(pid).get('runtimeMode',{});LINKED=mode.get('linked',True);EDITING=mode.get('editing',True);lastWatch[pid]=signature(Path(read(pid)['source']));bump()
      try:
       select_device(pid)
       with LOCK:
        for side in ('ios','web'):schedule_effects(read(pid),side)
      except Exception:
       with LOCK:ENABLED_PROJECTS.discard(pid);LOCAL_SURFACE.invalidate(pid);bump()
       raise
     else:
      with LOCK:
       ENABLED_PROJECTS.discard(pid);LOCAL_SURFACE.invalidate(pid);STARTED_DEVICES.pop(pid,None);PROJECT_DEVICE_CONFIGS.pop(pid,None);ios_runner.cancel(pid);PREVIEWS.cancel(pid)
       model=read(pid)['model']
       if model.get('hash'):eng('forgetFrames',key=json.dumps([model.get('id'),model['hash']]))
       closing_input=PROJECT_INPUTS.pop(pid,None);closing_frames=IOS_FRAMES.config.get('projectID')==pid
       lastWatch.pop(pid,None)
       for key in list(PENDING_TIMERS):
        if key[0]==pid:PENDING_TIMERS.pop(key).cancel()
       bump()
      if closing_input:closing_input.close()
      if closing_frames:IOS_FRAMES.close()
      with ios_runner.device_lock(pid):DEVICES.shutdown(pid)
    return self.respond({'ok':True,'enabled':pid in ENABLED_PROJECTS,'id':pid})
   if path=='/ios-stream':
    require_workbench(ACTIVE)
    stream=IOS_FRAMES.frames()
    self.connection.settimeout(3)
    self.send_response(200);self.send_header('Content-Type','application/x-studio-frames');self.end_headers()
    try:
     for chunk in stream:self.wfile.write(chunk);self.wfile.flush()
    except (OSError,TimeoutError):pass
    finally:stream.close()
    return
   if path in ('/ios-input-connect','/ios-input','/ios-input-disconnect'):
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    if path=='/ios-input-disconnect':
     with LOCK:connections=list(PROJECT_INPUTS.values())
     for connection in connections:
      with connection.lock:
       if body.get('session')==connection.session:connection.close()
     return self.respond({'ok':True})
    with LOCK:
     pid=body.get('id');require_workbench(pid);r=read(pid)
     if mode_for(r)[1]:raise ValueError('请在当前项目的「运行预览」模式操作模拟器')
    connection=project_input(pid)
    if path=='/ios-input-connect':
     result=connection.connect(pid)
     with LOCK:
      stale=pid not in ENABLED_PROJECTS or PROJECT_INPUTS.get(pid) is not connection or mode_for(read(pid))[1]
     if stale:connection.close();raise ValueError('项目或操作模式已切换')
     return self.respond(result)
    return self.respond(connection.send(pid,body.get('session'),body.get('events')))
   if path=='/ios-window':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    simulator=Path(CONFIG['developerDir'])/'Applications/Simulator.app'
    result=subprocess.run(['/usr/bin/open','-a',str(simulator),'--args','-CurrentDeviceUDID',select_device(ACTIVE)['ios']],capture_output=True,text=True,timeout=10)
    if result.returncode:raise ValueError('无法打开独立模拟器：'+result.stderr[-500:])
    return self.respond({'ok':True})
   if path=='/model-paint-data':
    project_id=q.get('project',[''])[0]
    read(project_id)
    return self.respond(model_paint_storage.exchange(folder(project_id)/'paintings',self.command,q.get('key',[''])[0],body))
   if path=='/export-start':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    with LOCK:
     if body.get('id')!=ACTIVE:raise ValueError('项目已切换，请重新导出')
     if ERROR:raise ValueError('请先修复源码错误：'+ERROR)
     update_edits(True,body);record=read(body['id'])
    return self.respond({'job':export_jobs.start(record,export)})
   if path=='/export-status':return self.respond(export_jobs.status(q['job'][0]))
   if path=='/run-ios':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    with LOCK:
     if body.get('id')!=ACTIVE:raise ValueError('项目已切换，请重新运行')
     if ERROR:raise ValueError('请先修复源码错误，再运行最新项目：'+ERROR)
     pid=ACTIVE;require_workbench(pid);r=read(pid)
    fresh=compile_project(r['source'])
    with LOCK:
     if ACTIVE!=pid:raise ValueError('项目已切换，请重新运行')
     recompile(read(pid),fresh)
    with WORKBENCH_LOCK:
     with LOCK:
      if ACTIVE!=pid:raise ValueError('项目已切换，请重新运行')
     config=resolve_project_device(pid)
     with LOCK:old_input=PROJECT_INPUTS.pop(pid,None)
     if old_input:old_input.close()
     job=start_resolved_device(pid,config,force=True)
    return self.respond({'job':job})
   if path=='/run-ios-status':return self.respond(ios_runner.status(q['job'][0]))
   if path=='/repair-sync':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    with LOCK:
     if body.get('id')!=ACTIVE:raise ValueError('项目已切换，请重新检查同步')
     require_workbench(ACTIVE);r=read(ACTIVE)
     if ERROR:raise ValueError('源码编译错误，请先修复：'+ERROR)
     if LINKED:r['sessions']['ios']=copy.deepcopy(r['sessions']['web']);store(r)
     ACK.clear();bump();repair_revision=REV;repair_project=ACTIVE
    with WORKBENCH_LOCK:
     with LOCK:
      if ACTIVE!=repair_project:raise ValueError('项目已切换，请重新检查同步')
     config=resolve_project_device(repair_project)
     job=start_resolved_device(repair_project,config)
     if job:return self.respond(dict(revision=repair_revision,linked=LINKED,ok=True,job=job))
     result=subprocess.run(['xcrun','simctl','launch',config['ios'],'local.htmlnative.HTMLNativeRuntime'],env=dict(os.environ,DEVELOPER_DIR=CONFIG['developerDir'],SIMCTL_CHILD_STUDIO_PROJECT_ID=repair_project),capture_output=True,text=True,timeout=12)
    if result.returncode:raise ValueError('无法启动 iOS 运行端：'+(result.stderr or result.stdout)[-1000:])
    return self.respond(dict(revision=repair_revision,linked=LINKED,ok=True))
   if path=='/compress-assets':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    with LOCK:source=read(body['id'])['source']
    return self.respond({'job':asset_compression.start(source,body.get('mode','lossless'))})
   if path=='/compression-status':return self.respond(asset_compression.status(q['job'][0]))
   if path=='/asset':
    # Disk IO, resizing and network writes must not hold the editor state lock.
    name=q['id'][0];base=folder(q['project'][0]);p=(base/'assets'/name).resolve()
    if not p.is_relative_to((base/'assets').resolve()):raise ValueError('Invalid asset')
    cache='private, max-age=31536000, immutable' if len(p.stem)==16 and all(c in '0123456789abcdef' for c in p.stem) else 'no-store'
    if 'thumbnail' in q:return self.respond(asset_thumbnails.thumbnail(p,base/'thumbnails',int(q['thumbnail'][0])),mime='image/png',cache=cache)
    if 'raster' in q or q.get('decode')==['fast']:
     fast=q.get('decode')==['fast'] and 'raster' not in q
     box=tuple(float(v) for v in q.get('raster',['0,0'])[0].split(','))
     display,ready=PREVIEWS.resolve(q['project'][0],p,base/'preview-rasters',box,q.get('fit',['contain'])[0],lambda:q['project'][0] in ENABLED_PROJECTS,fast=fast)
     try:raw=display.read_bytes()
     except FileNotFoundError:raw=p.read_bytes();ready=False
     return self.respond(raw,mime=mimetypes.guess_type(p.name)[0] or 'application/octet-stream',cache=cache if ready else 'no-store')
    return self.respond(p.read_bytes(),mime=mimetypes.guess_type(p.name)[0] or 'application/octet-stream',cache=cache)
   if path=='/conversion-audit':
    with LOCK:r=read(q['id'][0])
    return self.respond(conversion_audit.inspect_project(r,STORE/r['id']/'assets',eng))
   # Expensive catalog generation and socket writes must not own the mutation lock.
   if path in ('/projects','/project'):
    paths=sorted(STORE.glob('*/record.json'),key=lambda p:p.stat().st_mtime,reverse=True) if path=='/projects' else [folder(q['id'][0])/'record.json']
    if path=='/projects' and q.get('summary',[''])[0]=='1':
     result=[]
     for file in paths:
      with LOCK:
       stat=file.stat();stamp=(stat.st_ino,stat.st_mtime_ns,stat.st_size);entry=SUMMARY_CACHE.get(file)
       if not entry or entry[0]!=stamp:
        r=read(file.parent.name);entry=(stamp,dict(id=r['id'],name=r['model']['name'],sourcePath=r['source'],updated=r['updated'],compileRevision=r['model']['hash'],pages=[dict(id=pid,name=p.get('name',pid)) for pid,p in r['model']['pages'].items()]));SUMMARY_CACHE[file]=entry
       result.append(entry[1])
     for file in list(SUMMARY_CACHE):
      if file not in paths:SUMMARY_CACHE.pop(file,None)
     return self.respond(result)
    records=[]
    for file in paths:
     record=read(file.parent.name)
     with LOCK:record['_snapshotMode']=mode_for(record)
     records.append(record)
     time.sleep(0)
    if path=='/projects' and q.get('summary',[''])[0]=='1':
     result=[dict(id=r['id'],name=r['model']['name'],sourcePath=r['source'],updated=r['updated'],compileRevision=r['model']['hash'],pages=[dict(id=pid,name=p.get('name',pid)) for pid,p in r['model']['pages'].items()]) for r in records]
    else:result=[project(r) for r in records]
    return self.respond(result if path=='/projects' else result[0])
   if path=='/activate-project':
    with WORKBENCH_LOCK:
     with LOCK:
      pid=body['id'];r=read(pid)
      if ACTIVE==pid:return self.respond({'ok':True,'editing':EDITING})
      if ACTIVE!=pid:
       LOCAL_SURFACE.invalidate();ACTIVE=pid;mode=r.get('runtimeMode',{});LINKED=mode.get('linked',True);EDITING=mode.get('editing',True);bump()
      enabled=pid in ENABLED_PROJECTS;editing=EDITING
     if enabled:select_device(pid)
    return self.respond({'ok':True,'editing':editing})
   if path=='/mode':
    with WORKBENCH_LOCK:
     closing_input=None
     with LOCK:
      if 'linked'in body:
       LINKED=bool(body['linked']);r=read(ACTIVE)
       if LINKED:r['sessions']['web']=copy.deepcopy(r['sessions']['ios']);store(r)
      if 'editing'in body:
       EDITING=bool(body['editing'])
       if EDITING:
        closing_input=PROJECT_INPUTS.pop(ACTIVE,None)
        if ACTIVE:
         record=read(ACTIVE)
         for session in record['sessions'].values():
          page=session['stack'][-1]['page']
          if record['model']['pages'][page].get('presentation'):
           session['presentationPaused']=True;session['routeEpoch']=session.get('routeEpoch',0)+1
         store(record)
       if EDITING and BROWSER_OPEN.get(ACTIVE):CLOSE_BROWSER.add(ACTIVE)
       if not EDITING and ACTIVE:
        for side in ('ios','web'):
         session=read(ACTIVE)['sessions'][side];page=session.get('editingPage') or (session['stack'][-1]['page'] if session.get('presentationPaused') else None)
         if page:event({'side':side,'projectID':ACTIVE,'event':{'type':'navigate','page':page}})
      if ACTIVE:
       r=read(ACTIVE);r['runtimeMode']={'linked':LINKED,'editing':EDITING};store(r)
      bump()
     if closing_input:closing_input.close()
    return self.respond({'ok':True})
   with performance_trace.locked(LOCK,trace):
    if path=='/health':return self.respond({'ok':True,'root':str(ROOT),'version':SERVICE_VERSION})
    if path=='/projects':
     records=[json.loads(p.read_text()) for p in sorted(STORE.glob('*/record.json'),key=lambda p:p.stat().st_mtime,reverse=True)]
     if q.get('summary',[''])[0]=='1':return self.respond([dict(id=r['id'],name=r['model']['name'],sourcePath=r['source'],updated=r['updated'],compileRevision=r['model']['hash'],pages=[dict(id=pid,name=p.get('name',pid)) for pid,p in r['model']['pages'].items()]) for r in records])
     return self.respond([project(r) for r in records])
    if path=='/import':
     result=import_project(body['path']);return self.respond(result)
    if path=='/new':
     dest=authoring.new_project(body.get('name'));result=import_project(str(dest));return self.respond(result)
    if path=='/authoring-kit':
     pid=q.get('id',[None])[0];return self.respond(authoring.payload(read(pid)['source'] if pid else None))
    if path=='/install-authoring-kit':
     r=read(body['id']);authoring.install(r['source']);return self.respond(authoring.payload(r['source']))
    if path=='/restore-mode':
     if self.command!='POST':raise ValueError('POST required')
     LINKED=bool(body.get('linked',True));EDITING=bool(body.get('editing',True));bump();return self.respond({'ok':True})
    if path=='/status':
     active_record=read(ACTIVE) if ACTIVE else None
     return self.respond(dict(enabledProjects=sorted(ENABLED_PROJECTS),revision=REV,error=ERROR,active=ACTIVE,linked=LINKED,editing=EDITING,editingPage=active_record['sessions']['ios'].get('editingPage') if active_record else None,ack=ACK,conflicts=active_record['conflicts'] if active_record else [],simulatorFrames=IOS_FRAMES.status()))
    if path=='/editor-state':
     if q['id'][0]!=ACTIVE:raise ValueError('项目已切换')
     r=read(ACTIVE);current=frame(r);current['browserOpen']=BROWSER_OPEN.get(ACTIVE,False);current['chromeHitTargets']=CHROME_TARGETS.get((ACTIVE,current['id']),[])
     edited=eng('editor',frame=current);edited['paintOrderVersion']=1
     result=dict(revision=REV,projectID=ACTIVE,raw=current,page=edited,updated=r['updated'],selectionColor=r.get('selectionColor','#147DF5'))
     if q.get('compile',[''])[0]!=r['model']['hash']:result['project']=project(r)
     return self.respond(result)
    if path=='/project':return self.respond(project(read(q['id'][0])))
    if path=='/runtime':
     if (bound or q.get('project',[ACTIVE])[0]) not in ENABLED_PROJECTS:return self.respond({'revision':REV,'disabled':True})
     if int(q.get('after',['-1'])[0])==REV:return self.respond({'revision':REV})
     return self.respond(runtime(q.get('side',['ios'])[0],q.get('project',[''])[0],q.get('model',[''])[0],bound))
    if path=='/source-layers':
     r=read(ACTIVE);f=frame(r,'web',base=True);return self.respond(dict(projectID=r['id'],signature=source_resources.signature(f),frame=eng('editor',frame=f),raw=f,assets=r['model']['assets']))
    if path=='/copy-source':
     r=read(ACTIVE)
     if body.get('projectID')!=r['id']:raise ValueError('已切换项目，请重新选择 HTML 资源')
     target=r['sessions']['ios']['stack'][-1]['page']
     if body.get('targetPage')!=target:raise ValueError('iOS 页面已变化，请重新选择放置位置')
     f=frame(r,'web',base=True)
     if body.get('signature')!=source_resources.signature(f):raise ValueError('HTML 内容已更新，请重新选择资源再添加')
     copied=source_resources.copy_layers(f,eng('editor',frame=f),body['node'],bool(body.get('children')),body.get('point'))
     atomic(folder(r['id'])/'versions'/f'{time.time_ns()}.json',r)
     r['additions'].setdefault(target,[]).extend(copied);r['updated']=time.time();store(r);bump()
     return self.respond(dict(project=project(r),copiedIDs=[n['id'] for n in copied]))
    if path=='/browser-state':
     if self.command!='POST' or body.get('projectID')!=target:raise ValueError('项目已变化')
     opened=bool(body.get('open'))
     if BROWSER_OPEN.get(target,False)!=opened:BROWSER_OPEN[target]=opened;bump()
     if not opened:CLOSE_BROWSER.discard(target)
     return self.respond({'ok':True})
    if path=='/close-native-browser':
     if self.command!='POST' or body.get('id')!=target:raise ValueError('项目已变化')
     CLOSE_BROWSER.add(target);bump();return self.respond({'ok':True})
    if path=='/chrome-layout':
     if self.command!='POST':raise ValueError('POST required')
     if body.get('projectID')!=target or body.get('pageID')!=read(target)['sessions']['ios']['stack'][-1]['page']:raise ValueError('页面已切换')
     targets=body.get('targets',[])
     if not isinstance(targets,list) or len(targets)>30:raise ValueError('Invalid navigation targets')
     key=(target,body['pageID'])
     if CHROME_TARGETS.get(key)!=targets:CHROME_TARGETS[key]=targets;bump()
     return self.respond({'ok':True})
    if path=='/ack-effects':
     if self.command!='POST':return self.respond({'error':'POST required'},405)
     side=body.get('side');pid=body.get('projectID')
     if pid!=target or side not in ('web','ios'):raise ValueError('项目或同步端已变化')
     r=read(pid);acks=r.setdefault('effectAcks',{});seen=set(acks.get(side,[]));seen.update(str(i) for i in body.get('ids',[]))
     acks[side]=list(seen)
     for channel,session in r['sessions'].items():
      done=set(acks.get(channel,[])) if not mode_for(r)[0] else set(acks.get('web',[]))&set(acks.get('ios',[]))
      session['effects']=[e for e in session.get('effects',[]) if e['id'] not in done]
     pending_ids={e['id'] for session in r['sessions'].values() for e in session.get('effects',[])}
     for channel in list(acks):acks[channel]=[eid for eid in acks[channel] if eid in pending_ids]
     store(r);return self.respond({'ok':True})
    if path=='/event':
     e=body.get('event',{})
     if e.get('type')=='modelPaintStorage':
      project_id=body.get('projectID','');read(project_id)
      return self.respond(model_paint_storage.exchange(folder(project_id)/'paintings',e.get('method','GET'),e.get('key',''),e.get('value'),e.get('knownRevision')))
     result=event(body,bound,trace=trace)
     if body.get('returnRuntime') and body.get('side') in ('web','ios'):
      with performance_trace.span(trace,'runtime.response'):
       result['runtime']=runtime(body['side'],body.get('projectID',''),body.get('modelHash',''),bound,trace=trace)
     return self.respond(result)
    if path=='/ack':
     if target==ACTIVE:ACK[body.get('side','ios')]=body.get('revision')
     return self.respond({'ok':True})
    if path=='/reset':
     r=read(ACTIVE);model=compile_project(r['source']);atomic(folder(ACTIVE)/'versions'/f'{time.time_ns()}.json',r);r['model']=model;r['sessions']=sessions(model);r['effectAcks']={};store(r);ERROR='';bump();return self.respond({'ok':True})
    if path=='/preview':return self.respond(update_edits(False,body))
    if path=='/save':return self.respond(update_edits(True,body))
    if path=='/conflict':
     if body.get('projectID',ACTIVE)!=ACTIVE:raise ValueError('项目已切换，请重新打开冲突列表')
     if body.get('choice') not in ('ios','html'):raise ValueError('无效冲突处理选项')
     if not any(c['key']==body.get('key') and c['field']==body.get('field') for c in read(ACTIVE)['conflicts']):raise ValueError('此冲突已变化或已处理，请重新打开列表')
     r=read(ACTIVE);key=body['key'];field=body['field'];v=r['overrides'][key];base=all_base_nodes(r).get(key)
     if body['choice']=='html':
      if field=='*':r['overrides'].pop(key)
      else:v['patch'].pop(field,None)
     if body['choice']=='ios' and field=='*' and base is None:
      retained={**v.get('baseFrame',v['base']),**v['patch'],'parent':''};pid=retained['id'].split('/')[0]
      if pid not in r['model']['pages']:raise ValueError('源页面已删除，先新建目标页后再恢复该图层')
      r['additions'].setdefault(pid,[]).append(retained);r['overrides'].pop(key)
     elif body['choice']=='ios' and field=='*' and base is not None:v['patch']['type']=v['type']
     if base and key in r['overrides']:v['base']=base;v['type']=base['type']
     r['conflicts']=[c for c in r['conflicts'] if not(c['key']==key and (field=='*' or c['field']==field))];store(r);bump();return self.respond({'ok':True})
    if path=='/restore-follow':
     r=read(ACTIVE);r['overrides'].pop(body['key'],None);r['conflicts']=[c for c in r['conflicts'] if c['key']!=body['key']];store(r);bump();return self.respond({'ok':True})
    if path=='/export':update_edits(True,body);return self.respond({'path':export(read(body['id']))})
    if path=='/versions':return self.respond([{'file':p.name,'time':p.stat().st_mtime} for p in sorted((folder(q['id'][0])/'versions').glob('*.json'),reverse=True)])
    if path=='/new-page':
     r=read(body['id']);source=Path(r['source']);appfile=source/'app.json';app=json.loads(appfile.read_text());pid='page-'+uuid.uuid4().hex[:10]
     dest=source/'pages'/pid
     if not dest.resolve().is_relative_to(source.resolve()):raise ValueError('页面路径超出项目')
     dest.mkdir(parents=True);(dest/'page.html').write_text('<ui-page id="'+pid+'" style="background:#FFFFFF"></ui-page>');(dest/'style.css').write_text('')
     app['pages'].append({'id':pid,'name':body.get('name') or '新页面','role':'detail','html':'pages/'+pid+'/page.html','css':'pages/'+pid+'/style.css',**({'navigation':{'hidden':True}} if app.get('navigation') is not None else {})})
     atomic(folder(r['id'])/'versions'/f'{time.time_ns()}.json',r);atomic(appfile,app);recompile(r,compile_project(source));event({'side':'ios','event':{'type':'navigate','page':pid}});return self.respond(project(read(r['id'])))
    if path=='/restore':
     r=read(body['id']);name=body['file']
     if Path(name).name!=name:raise ValueError('Invalid version')
     old=json.loads((folder(r['id'])/'versions'/name).read_text());atomic(folder(r['id'])/'versions'/f'{time.time_ns()}.json',r);r['overrides']=old['overrides'];r['additions']=old['additions'];r['conflicts']=[];store(r);recompile(r,compile_project(r['source']));bump();return self.respond(project(r))
    if path=='/model-paint.js' or path.startswith('/model-vendor/'):
     p=(ROOT/'Web'/path.lstrip('/')).resolve()
     if not p.is_relative_to((ROOT/'Web').resolve()) or not p.is_file():raise ValueError('Invalid module path')
     return self.respond(p.read_bytes(),mime='text/javascript')
    if path in ('/web','/engine.js','/native-ui.js','/preview.js'):
     p={'/web':ROOT/'Web/index.html','/engine.js':ROOT/'Shared/engine.js','/native-ui.js':ROOT/'Web/native-ui.js','/preview.js':ROOT/'Web/preview.js'}[path]
     return self.respond(p.read_bytes(),mime='text/html' if path=='/web' else 'text/javascript')
    raise ValueError('未提供此接口 '+path)
  except (BrokenPipeError,ConnectionResetError):pass
  except Exception as e:return self.respond({'error':str(e)},400)
if __name__=='__main__':
 atexit.register(worker.terminate)
 signal.signal(signal.SIGTERM,lambda *_:sys.exit(0))
 STORE.mkdir(exist_ok=True)
 for pid in ([] if os.environ.get('STUDIO_BROWSER_ONLY')=='1' else DEVICES.projects()):
  try:DEVICES.shutdown(pid)
  except Exception as error:print('关闭默认停用工作台失败',pid,str(error),flush=True)
 threading.Thread(target=watch,daemon=True).start();ThreadingHTTPServer(('127.0.0.1',CONFIG['port']),Handler).serve_forever()
