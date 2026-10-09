"""Project-bound HTML access to the existing compiler, records and renderer.

Browser credentials can operate only their HTML session, never a simulator,
another project, source files, iOS overrides or export. No desktop is required.
"""
import base64, json, mimetypes, secrets, subprocess, time
from pathlib import Path
from urllib.parse import urlencode


class BrowserPreview:
 def __init__(self, namespace):
  self.n=namespace;self.root=namespace['ROOT'];self.seen={};self.errors={};self.symbols={}
  self.file=self.root/'artifacts/browser-previews.json'
  try:self.keys=json.loads(self.file.read_text())
  except (OSError,ValueError):self.keys={}

 def owns(self,key):return isinstance(key,str) and key in self.keys

 def active_projects(self):
  now=time.monotonic()
  self.seen={pid:t for pid,t in self.seen.items() if now-t<30}
  return set(self.seen)

 def attach(self,source):
  n=self.n;source=Path(source).expanduser().resolve()
  model=n['compile_project'](source)
  # Register without changing the desktop selection or allocating a device.
  with n['LOCK']:
   record=next((n['read'](p.parent.name) for p in n['STORE'].glob('*/record.json') if json.loads(p.read_text())['source']==str(source)),None)
   previous_error=n['ERROR']
   try:
    if record:n['recompile'](record,model)
    else:
     n['all_base_nodes']({'model':model})
     record=dict(id=str(n['uuid'].uuid4()),source=str(source),model=model,sessions=n['sessions'](model),overrides={},additions={},conflicts=[],updated=time.time())
     n['publish_assets'](record);n['store'](record);n['bump']()
   finally:n['ERROR']=previous_error
   pid=record['id'];key=next((k for k,v in self.keys.items() if v==pid),None)
   if not key:
    key=secrets.token_urlsafe(32);self.keys[key]=pid
    self.file.parent.mkdir(parents=True,exist_ok=True)
    temporary=self.file.with_suffix('.tmp');temporary.touch(mode=0o600,exist_ok=True);temporary.chmod(0o600)
    temporary.write_text(json.dumps(self.keys));temporary.replace(self.file)
   self.errors.pop(pid,None);self.seen[pid]=time.monotonic()
   return {'projectID':pid,'sourcePath':str(source),'url':f"http://127.0.0.1:{n['CONFIG']['port']}/browser#{key}"}

 def runtime(self,pid,known_model=''):
  n=self.n;r=n['read'](pid);r['_snapshotMode']=(False,False)
  n['schedule_effects'](r,'web',browser=True)
  page=n['frame'](r,'web');seen=set(r.get('effectAcks',{}).get('web',[]))
  page['effects']=[e for e in page.get('effects',[]) if e['id'] not in seen]
  result=dict(revision=n['REV'],projectID=pid,page=page,session=r['sessions']['web'],editing=False,linked=False,modelHash=r['model']['hash'],sourceSignature='')
  if known_model==r['model']['hash']:result['reuseModel']=True
  else:result.update(model=r['model'],assets=r['model']['assets'])
  result['browserInfo']=dict(name=r['model']['name'],sourcePath=r['source'],error=self.errors.get(pid,''),pages=[{'id':k,'name':v.get('name',k)} for k,v in r['model']['pages'].items()])
  return result

 def request(self,handler,url,query,key):
  n=self.n;pid=self.keys[key];path=url.path;reply=handler.respond
  try:
   length=int(handler.headers.get('Content-Length','0'))
   if length<0 or length>1024*1024:raise ValueError('请求过大')
   body=json.loads(handler.rfile.read(length) or b'{}')
   if body.get('projectID',pid)!=pid or query.get('project',[pid])[0] not in ('',pid):raise ValueError('浏览器项目不匹配')
   if body.get('side','web')!='web':raise ValueError('浏览器仅能操作 HTML 端')
   origin=handler.headers.get('Origin')
   if origin and origin!=f"http://127.0.0.1:{n['CONFIG']['port']}":raise ValueError('浏览器来源不匹配')
   static={'/engine.js':'Shared/engine.js','/native-ui.js':'Web/native-ui.js','/preview.js':'Web/preview.js','/browser.js':'Web/browser.js'}
   if path in static and handler.command=='GET':return reply((self.root/static[path]).read_bytes(),mime='text/javascript')
   if path=='/asset' and handler.command=='GET':
    base=(n['folder'](pid)/'assets').resolve();file=(base/query['id'][0]).resolve()
    if not file.is_relative_to(base) or not file.is_file():raise ValueError('资源不存在')
    return reply(file.read_bytes(),mime=mimetypes.guess_type(str(file))[0] or 'application/octet-stream',cache='private, max-age=3600')
   if path=='/browser-symbol' and handler.command=='GET':
    name=query['name'][0];color=query['color'][0];cache_key=(name,color)
    if len(name)>160 or len(color)>9:raise ValueError('图标参数无效')
    if cache_key not in self.symbols:
     helper=self.root/'build/browser-symbols'
     if not helper.is_file():raise ValueError('浏览器原生图标服务未安装')
     data=subprocess.check_output([str(helper),name,color],timeout=10)
     if len(self.symbols)>512:self.symbols.clear()
     self.symbols[cache_key]=base64.b64decode(data)
    return reply(self.symbols[cache_key],mime='image/png',cache='private, max-age=3600')
   if path=='/runtime' and handler.command=='GET':
    with n['LOCK']:
     self.seen[pid]=time.monotonic()
     if query.get('after',['-1'])[0]==str(n['REV']):
      r=n['read'](pid)
      return reply({'revision':n['REV'],'browserInfo':{'name':r['model']['name'],'sourcePath':r['source'],'error':self.errors.get(pid,''),'pages':[{'id':k,'name':v.get('name',k)} for k,v in r['model']['pages'].items()]}})
     return reply(self.runtime(pid,query.get('model',[''])[0]))
   if path in ('/event','/ack','/ack-effects') and handler.command=='POST':
    with n['LOCK']:
     self.seen[pid]=time.monotonic()
     if path=='/event':
      body['projectID']=pid;body['side']='web'
      if body.get('event',{}).get('type')=='modelPaintStorage':
       e=body['event'];return reply(n['model_paint_storage'].exchange(n['folder'](pid)/'paintings',e.get('method','GET'),e.get('key',''),e.get('value'),e.get('knownRevision')))
      n['event'](body,pid,browser=True)
      return reply({'runtime':self.runtime(pid,body.get('modelHash',''))})
     if path=='/ack-effects':
      r=n['read'](pid);ids=set(map(str,body.get('ids',[])))
      r['sessions']['web']['effects']=[e for e in r['sessions']['web'].get('effects',[]) if e['id'] not in ids]
      n['store'](r)
     return reply({'ok':True})
   return reply({'error':'浏览器入口不允许此操作'},403)
  except Exception as error:return reply({'error':str(error)},400)
