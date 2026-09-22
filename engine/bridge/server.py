#!/usr/bin/env python3
import host_export
import export_policy
from source_watch import signature
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
import asset_compression
import ios_rules
import ios_export
import ios_runner
import export_jobs
from ios_input import SimulatorInput
from ios_frames import SimulatorFrames
from project_devices import ProjectDevices
ROOT=Path(__file__).resolve().parents[1];STORE=ROOT/'Workspace';CONFIG=json.loads((ROOT/'bridge/config.json').read_text());TOKEN=(ROOT/'bridge/token').read_text().strip()
DEVICES=ProjectDevices(ROOT,CONFIG)
STARTED_DEVICES=set()
IOS_INPUT=SimulatorInput(ROOT,CONFIG)
IOS_FRAMES=SimulatorFrames(ROOT,CONFIG)
sys.path.insert(0,str(ROOT/'scripts'))
from source_stamp import fingerprint
SERVICE_VERSION=fingerprint('service')
LOCK=threading.RLock();ENGINE_LOCK=threading.Lock();REV=time.time_ns()//1000000;ACTIVE=None;ERROR='';ACK={};LINKED=True;EDITING=True;PROCESSED={};lastWatch={};CHROME_TARGETS={};BROWSER_OPEN={};CLOSE_BROWSER=set()
worker=subprocess.Popen([CONFIG['node'],str(ROOT/'bridge/engine_worker.js')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True,bufsize=1)
ENGINE_MODEL_KEY=None
def eng(op,**args):
 global ENGINE_MODEL_KEY
 with ENGINE_LOCK:
  model=args.get('model');key=json.dumps([model.get('id'),model['hash']]) if isinstance(model,dict) and model.get('hash') else None
  if key:
   args['modelKey']=key
   if key==ENGINE_MODEL_KEY:args.pop('model')
  worker.stdin.write(json.dumps(dict(op=op,**args),ensure_ascii=False)+'\n');worker.stdin.flush();reply=json.loads(worker.stdout.readline())
  if key:ENGINE_MODEL_KEY=key
 if 'error'in reply:raise ValueError(reply['error'])
 return reply['ok']
def atomic(p,v,compact=False):p.parent.mkdir(parents=True,exist_ok=True);t=p.with_suffix('.tmp');t.write_text(json.dumps(v,ensure_ascii=False,**({'separators':(',',':')} if compact else {'indent':2})));t.replace(p)
def folder(pid):
 if not isinstance(pid,str) or not all(c in '0123456789abcdef-' for c in pid):raise ValueError('无效项目 ID')
 p=STORE/pid
 if not (p/'record.json').exists():raise ValueError('项目不存在')
 return p
def read(pid):return json.loads((folder(pid)/'record.json').read_text())
def bump():
 global REV
 REV+=1

def sessions(model):return {s:eng('initial',model=model) for s in ['web','ios']}
def frame(r,side='ios',base=False):
 if side=='ios' and not base:return eng('compose',model=r['model'],session=r['sessions'][side],overrides=r.get('overrides',{}),additions=r.get('additions',{}))
 return eng('frame',model=r['model'],session=r['sessions'][side])

def project(r):
 pages=[]
 for pid,p in r['model']['pages'].items():
  session=eng('initial',model=r['model']);session['stack']=[{'page':pid,'params':{}}]
  temp={**r,'sessions':{'ios':session}};out=eng('editor',frame=frame(temp));out['paintOrderVersion']=1;pages.append(out)
 current=eng('editor',frame=frame(r));pages=[current if p['id']==current['id'] else p for p in pages]
 return dict(schemaVersion=1,id=r['id'],name=r['model']['name'],sourcePath=r['source'],package='',assets=r['model']['assets'],pages=pages,pageCandidates=[],updated=r['updated'],importMode='html',selectionColor=r.get('selectionColor','#147DF5'),compileRevision=r['model']['hash'])
def mode_for(r):
 return (LINKED,EDITING) if r['id']==ACTIVE else (r.get('runtimeMode',{}).get('linked',True),r.get('runtimeMode',{}).get('editing',False))
def select_device(pid):
 r=read(pid);config=DEVICES.ensure(pid,r['model']['name'])
 if IOS_FRAMES.config['ios']!=config['ios']:
  IOS_INPUT.close();IOS_FRAMES.close()
 IOS_INPUT.config=config;IOS_FRAMES.config=config
 if pid not in STARTED_DEVICES:
  STARTED_DEVICES.add(pid);ios_runner.start(pid,config,finish_ios_run)
 return config
def store(r):atomic(STORE/r['id']/'record.json',r,compact=True)
def publish_assets(r):
 d=STORE/r['id']/'assets';d.mkdir(parents=True,exist_ok=True)
 for a in r['model']['assets']:
  if not (d/a['file']).exists():shutil.copy2(Path(r['source'])/a['source'],d/a['file'])
def import_project(path):
 global ACTIVE,ERROR
 IOS_INPUT.close()
 source=Path(path).expanduser().resolve();model=compile_project(source)
 for p in STORE.glob('*/record.json'):
  r=json.loads(p.read_text())
  if r['source']==str(source):ACTIVE=r['id'];recompile(r,model);return project(read(ACTIVE))
 all_base_nodes({'model':model})
 pid=str(uuid.uuid4());r=dict(id=pid,source=str(source),model=model,sessions=sessions(model),overrides={},additions={},conflicts=[],updated=time.time())
 (STORE/pid).mkdir();publish_assets(r);store(r);ACTIVE=pid;ERROR='';bump();return project(r)
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
 if model['hash']==r['model']['hash']:ERROR='';return
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
  for key,val in model['state'].items():s['state'].setdefault(key,copy.deepcopy(val))
  s['stack']=[p for p in s['stack'] if p['page'] in model['pages']] or [{'page':model['entry'],'params':{}}]
  s['modals']=[p for p in s['modals'] if p in model['pages']]
 publish_assets(r);r['updated']=time.time();store(r);ERROR='';bump()
def update_edits(persist,body):
 r=read(body.get('id') or body['projectID'])
 if body.get('compileRevision') and body['compileRevision']!=r['model']['hash']:raise ValueError('HTML 已更新，请等待新版本后继续保存，旧编辑不会覆盖新源码')
 pages=body.get('pages') or [body['page']]
 if persist:atomic(folder(r['id'])/'versions'/f'{time.time_ns()}.json',r)
 for edit in pages:
  # Save only current visible page to avoid default data pages clobbering live state.
  if edit['id']!=r['sessions']['ios']['stack'][-1]['page']:continue
  raw=frame(r,base=True);base=eng('editor',frame=raw);rawmap={n['id']:n for n in raw['nodes']};basemap={n['id']:n for n in base['nodes']}
  # Reuse the editor snapshot already obtained above instead of sending the
  # same 2000-node frame through the JS worker for a second flatten/diff.
  ignored={'id','parent','source','sharedKey','textKey','placeholderKey','symbol','selected'}
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
   original=rawmap[nid];parent=editmap.get(original.get('parent',''))
   patch=diffs.setdefault(nid,{})
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
def event(body,project_id=None):
 pid=project_id or ACTIVE;r=read(pid);linked,editing=mode_for(r);side=body.get('side','web');eid=body.get('eventID');tag=(pid,side,eid)
 if eid and tag in PROCESSED:return {'revision':REV}
 if side not in ('web','ios'):raise ValueError('Unknown side')
 s=r['sessions'][side];e=body['event']
 if body.get('projectID',pid)!=pid:raise ValueError('项目已切换，操作已停止')
 if body.get('pageID') and body['pageID']!=frame(r,side)['id']:raise ValueError('页面已切换，操作已停止')
 if e.get('type') not in ('navigate','back','scroll','locale','chromeInsets','tab','popTo','effectComplete'):
  f=frame(r,side);decl=f['events'].get(e.get('node'))
  if decl is None and side=='ios':
   added=next((n for n in r.get('additions',{}).get(f['id'],[]) if n['id']==e.get('node')),None)
   if added and not added.get('hidden') and not added.get('disabled'):
    field='text' if added['type'] in ('nativeTextField','nativeTextView') else 'isOn' if added['type'] in ('nativeCheckbox','nativeSwitch') else 'value'
    if 'value' in e:added[field]=e['value']
    store(r);bump();return {'revision':REV}
  if decl is None or decl.get('disabled'):raise ValueError('图层不可交互或已失效')
  e={**decl,'value':e.get('value')}
 if e.get('preview') and not editing:raise ValueError('请先切换到选取与编辑模式')
 s=eng('event',model=r['model'],session=s,event=e)
 r['sessions'][side]=s;r['modelCommandSide']=side
 if linked:r['sessions']['web' if side=='ios' else 'ios']=copy.deepcopy(s)
 r['updated']=time.time();store(r);bump();schedule_effects(r,side)
 if eid:PROCESSED[tag]=REV
 if len(PROCESSED)>1000:PROCESSED.clear()
 return {'revision':REV}
PENDING_TIMERS={}
def schedule_effects(record,side):
 for eid,effect in record['sessions'][side].get('pendingEffects',{}).items():
  key=(record['id'],side,eid)
  if key in PENDING_TIMERS:continue
  def complete(key=key):
   try:
    with LOCK:
     event({'side':key[1],'projectID':key[0],'event':{'type':'effectComplete','id':key[2]}},key[0])
   except Exception as error:
    global ERROR
    with LOCK:
     if ACTIVE==key[0]:ERROR='延时动作执行失败：'+str(error)
   finally:PENDING_TIMERS.pop(key,None)
  timer=threading.Timer(effect['duration'],complete);timer.daemon=True;PENDING_TIMERS[key]=timer;timer.start()
def runtime(side,known_project='',known_model='',project_id=None):
 pid=project_id or ACTIVE
 if not pid:return dict(revision=REV,model=None)
 r=read(pid);linked,editing=mode_for(r);schedule_effects(r,side);page=frame(r,side);seen=set(r.get('effectAcks',{}).get(side,[]));page['chromeHitTargets']=CHROME_TARGETS.get((pid,page['id']),[]) if side=='ios' else [];page['browserOpen']=BROWSER_OPEN.get(pid,False) if side=='ios' else False;page['closeBrowser']=pid in CLOSE_BROWSER if side=='ios' else False;page['effects']=[e for e in page.get('effects',[]) if e['id'] not in seen]
 for node in page.get('nodes',[]):
  if node.get('modelAsset'):node['paintCommandOwner']=r.get('modelCommandSide',side)
 result=dict(revision=REV,projectID=pid,session=r['sessions'][side],page=page,sourceSignature=source_resources.signature(page) if side=='web' else '',editing=editing,linked=linked,modelHash=r['model']['hash'])
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
  read(pid)
  if ACTIVE==pid:ACK.clear()
  bump();return {'revision':REV,'projectID':pid,'projectChanged':ACTIVE!=pid}

def watch():
 global ERROR
 while True:
  time.sleep(.25)
  with LOCK:targets=list(dict.fromkeys(([ACTIVE] if ACTIVE else [])+DEVICES.projects()))
  for pid in targets:
   try:
    with LOCK:r=read(pid)
    sig=signature(Path(r['source']))
    if sig==lastWatch.get(pid):continue
    lastWatch[pid]=sig;time.sleep(.15);started=time.monotonic();model=compile_project(r['source'])
    with LOCK:
     previous_error=ERROR
     try:recompile(read(pid),model)
     finally:
      if ACTIVE!=pid:ERROR=previous_error
    (ROOT/'artifacts/last-compile-ms.txt').write_text(str(round((time.monotonic()-started)*1000,1)))
   except Exception as e:
    with LOCK:
     if ACTIVE==pid:ERROR=str(e)
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def respond(self,value,code=200,mime='application/json',cache='no-store'):
  raw=value if isinstance(value,bytes) else json.dumps(value,ensure_ascii=False).encode();self.send_response(code);self.send_header('Content-Type',mime);self.send_header('Content-Length',str(len(raw)));self.send_header('Cache-Control',cache);self.end_headers();self.wfile.write(raw)
 def do_GET(self):self.handle_request()
 def do_POST(self):self.handle_request()
 def handle_request(self):
  global ACTIVE,ERROR,LINKED,EDITING
  u=urlparse(self.path);q=parse_qs(u.query);path=u.path
  if path in ('/model-paint.js','/model-vendor/three.module.js','/model-vendor/three.core.js','/model-vendor/GLTFLoader.js','/model-vendor/BufferGeometryUtils.js'):
   return self.respond((ROOT/'Web'/path.lstrip('/')).read_bytes(),mime='text/javascript')
  if self.headers.get('X-Studio-Token')!=TOKEN and q.get('token',[''])[0]!=TOKEN:return self.respond({'error':'Unauthorized'},403)
  try:
   body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))) or b'{}')
   bound=self.headers.get('X-Studio-Project')
   if bound:read(bound)
   target=bound or ACTIVE
   if bound and body.get('projectID',bound)!=bound:raise ValueError('运行端项目不匹配')
   if path=='/ios-stream':
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
     with IOS_INPUT.lock:
      if body.get('session')==IOS_INPUT.session:IOS_INPUT.close()
     return self.respond({'ok':True})
    with LOCK:
     if body.get('id')!=ACTIVE or EDITING:raise ValueError('请在当前项目的「运行预览」模式操作模拟器')
     pid=ACTIVE
    if path=='/ios-input-connect':
     result=IOS_INPUT.connect(pid)
     with LOCK:
      if ACTIVE!=pid or EDITING:IOS_INPUT.close();raise ValueError('项目或操作模式已切换')
     return self.respond(result)
    return self.respond(IOS_INPUT.send(pid,body.get('session'),body.get('events')))
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
     pid=ACTIVE;r=read(pid)
    IOS_INPUT.close()
    fresh=compile_project(r['source'])
    with LOCK:
     if ACTIVE!=pid:raise ValueError('项目已切换，请重新运行')
     recompile(read(pid),fresh)
    return self.respond({'job':ios_runner.start(pid,DEVICES.ensure(pid,r['model']['name']),finish_ios_run)})
   if path=='/run-ios-status':return self.respond(ios_runner.status(q['job'][0]))
   if path=='/repair-sync':
    if self.command!='POST':return self.respond({'error':'POST required'},405)
    with LOCK:
     if body.get('id')!=ACTIVE:raise ValueError('项目已切换，请重新检查同步')
     r=read(ACTIVE)
     if ERROR:raise ValueError('源码编译错误，请先修复：'+ERROR)
     if LINKED:r['sessions']['ios']=copy.deepcopy(r['sessions']['web']);store(r)
     ACK.clear();bump();repair_revision=REV;repair_project=ACTIVE
    result=subprocess.run(['xcrun','simctl','launch',DEVICES.ensure(repair_project,r['model']['name'])['ios'],'local.htmlnative.HTMLNativeRuntime'],env=dict(os.environ,DEVELOPER_DIR=CONFIG['developerDir'],SIMCTL_CHILD_STUDIO_PROJECT_ID=repair_project),capture_output=True,text=True,timeout=12)
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
    return self.respond(p.read_bytes(),mime=mimetypes.guess_type(p.name)[0] or 'application/octet-stream',cache=cache)
   if path=='/conversion-audit':
    with LOCK:r=read(q['id'][0])
    return self.respond(conversion_audit.inspect_project(r,STORE/r['id']/'assets',eng))
   with LOCK:
    if path=='/health':return self.respond({'ok':True,'root':str(ROOT),'version':SERVICE_VERSION})
    if path=='/projects':
     records=[json.loads(p.read_text()) for p in sorted(STORE.glob('*/record.json'),key=lambda p:p.stat().st_mtime,reverse=True)]
     if q.get('summary',[''])[0]=='1':return self.respond([dict(id=r['id'],name=r['model']['name'],sourcePath=r['source'],updated=r['updated'],compileRevision=r['model']['hash'],pages=[dict(id=pid,name=p.get('name',pid)) for pid,p in r['model']['pages'].items()]) for r in records])
     return self.respond([project(r) for r in records])
    if path=='/import':
     result=import_project(body['path']);select_device(ACTIVE);return self.respond(result)
    if path=='/new':
     dest=authoring.new_project(body.get('name'));result=import_project(str(dest));select_device(ACTIVE);return self.respond(result)
    if path=='/authoring-kit':
     pid=q.get('id',[None])[0];return self.respond(authoring.payload(read(pid)['source'] if pid else None))
    if path=='/install-authoring-kit':
     r=read(body['id']);authoring.install(r['source']);return self.respond(authoring.payload(r['source']))
    if path=='/activate-project':
     IOS_INPUT.close();ACTIVE=body['id'];r=read(ACTIVE);mode=r.get('runtimeMode',{});LINKED=mode.get('linked',True);EDITING=mode.get('editing',True);select_device(ACTIVE);bump();return self.respond({'ok':True})
    if path=='/restore-mode':
     if self.command!='POST':raise ValueError('POST required')
     LINKED=bool(body.get('linked',True));EDITING=bool(body.get('editing',True));bump();return self.respond({'ok':True})
    if path=='/status':
     active_record=read(ACTIVE) if ACTIVE else None
     return self.respond(dict(revision=REV,error=ERROR,active=ACTIVE,linked=LINKED,editing=EDITING,editingPage=active_record['sessions']['ios'].get('editingPage') if active_record else None,ack=ACK,conflicts=active_record['conflicts'] if active_record else [],simulatorFrames=IOS_FRAMES.status()))
    if path=='/editor-state':
     if q['id'][0]!=ACTIVE:raise ValueError('项目已切换')
     r=read(ACTIVE);current=frame(r);current['browserOpen']=BROWSER_OPEN.get(ACTIVE,False);current['chromeHitTargets']=CHROME_TARGETS.get((ACTIVE,current['id']),[])
     edited=eng('editor',frame=current);edited['paintOrderVersion']=1
     result=dict(revision=REV,projectID=ACTIVE,raw=current,page=edited,updated=r['updated'],selectionColor=r.get('selectionColor','#147DF5'))
     if q.get('compile',[''])[0]!=r['model']['hash']:result['project']=project(r)
     return self.respond(result)
    if path=='/project':return self.respond(project(read(q['id'][0])))
    if path=='/runtime':
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
     return self.respond(event(body,bound))
    if path=='/ack':
     if target==ACTIVE:ACK[body.get('side','ios')]=body.get('revision')
     return self.respond({'ok':True})
    if path=='/mode':
     if 'linked'in body:
      LINKED=bool(body['linked']);r=read(ACTIVE)
      if LINKED:r['sessions']['web']=copy.deepcopy(r['sessions']['ios']);store(r)
     if 'editing'in body:
      EDITING=bool(body['editing'])
      if EDITING:IOS_INPUT.close()
      if EDITING and BROWSER_OPEN.get(ACTIVE):CLOSE_BROWSER.add(ACTIVE)
      if not EDITING and ACTIVE:
       for side in ('ios','web'):
        page=read(ACTIVE)['sessions'][side].get('editingPage')
        if page:event({'side':side,'projectID':ACTIVE,'event':{'type':'navigate','page':page}})
     if ACTIVE:
      r=read(ACTIVE);r['runtimeMode']={'linked':LINKED,'editing':EDITING};store(r)
     bump();return self.respond({'ok':True})
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
  except Exception as e:self.respond({'error':str(e)},400)
if __name__=='__main__':
 atexit.register(worker.terminate)
 signal.signal(signal.SIGTERM,lambda *_:sys.exit(0))
 STORE.mkdir(exist_ok=True);threading.Thread(target=watch,daemon=True).start();ThreadingHTTPServer(('127.0.0.1',CONFIG['port']),Handler).serve_forever()
