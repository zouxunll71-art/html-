import json,os,shutil,socket,subprocess,sys,tempfile,time,unittest,urllib.request,urllib.error
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class BrowserPreviewTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.root=Path(cls.tmp.name)/'engine';cls.root.mkdir()
  for name in ['Shared','Web','Protocol','scripts']:(cls.root/name).symlink_to(ROOT/'engine'/name,target_is_directory=True)
  shutil.copytree(ROOT/'engine/bridge',cls.root/'bridge',ignore=shutil.ignore_patterns('node_modules','__pycache__','config.json','token'))
  deps=ROOT/'engine/bridge/parser/node_modules'
  if deps.exists():(cls.root/'bridge/parser/node_modules').symlink_to(deps,target_is_directory=True)
  (cls.root/'artifacts').mkdir();(cls.root/'Workspace').mkdir()
  sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
  cls.base=f'http://127.0.0.1:{port}';cls.token='isolated-test-admin'
  (cls.root/'bridge/token').write_text(cls.token)
  (cls.root/'bridge/config.json').write_text(json.dumps(dict(port=port,node=shutil.which('node'),ios='NEVER-BOOT',developerDir='/unused')))
  cls.log=(cls.root/'artifacts/service.log').open('w+')
  cls.proc=subprocess.Popen([sys.executable,str(cls.root/'bridge/server.py')],stdout=cls.log,stderr=cls.log,env={**os.environ,'STUDIO_BROWSER_ONLY':'1'})
  for _ in range(100):
   try:cls.call('/health');break
   except Exception:time.sleep(.1)
  else:
   cls.log.seek(0);raise RuntimeError(cls.log.read())

 @classmethod
 def tearDownClass(cls):
  cls.proc.terminate();cls.proc.wait(timeout=10);cls.log.close();cls.tmp.cleanup()

 @classmethod
 def call(cls,path,body=None,key=None):
  req=urllib.request.Request(cls.base+path,data=json.dumps(body).encode() if body is not None else None,headers={'X-Studio-Token':key or cls.token,'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=20) as response:return json.load(response)
  except urllib.error.HTTPError as error:
   error.msg=error.read().decode();raise

 def fixture(self,name):
  dest=Path(self.tmp.name)/name;shutil.copytree(ROOT/'engine/Protocol/Starter',dest)
  app=json.loads((dest/'app.json').read_text());app['id']=name;app['name']=name
  app['pages'].append({'id':'detail','name':'Detail','role':'detail','html':'pages/detail.html','css':'pages/home/style.css','navigation':{'hidden':True}})
  (dest/'app.json').write_text(json.dumps(app))
  html='<ui-page id="home" style="background:#edf6ff"><ui-text id="label" text-key="browser.label" style="position:absolute;left:24;top:100;width:280;height:50"></ui-text><ui-button id="next" text-key="browser.next" action="next" style="position:absolute;left:24;top:180;width:200;height:50"></ui-button></ui-page>'
  (dest/'pages/home/page.html').write_text(html)
  (dest/'pages/detail.html').write_text('<ui-page id="detail"><ui-text id="title" text-key="browser.detail" style="width:200;height:50"></ui-text></ui-page>')
  (dest/'actions.json').write_text(json.dumps({'next':[{'type':'push','page':'detail'}]}))
  for lang in ['en','zh-Hans']:
   file=dest/'localization'/(lang+'.json');data=json.loads(file.read_text());data.update({'browser.label':'Browser test','browser.next':'Open detail','browser.detail':'Detail page'});file.write_text(json.dumps(data))
  info=self.call('/browser-attach',{'source':str(dest)});return dest,info,info['url'].split('#')[1]

 def test_shared_source_hot_reload_interaction_and_isolation(self):
  source,a,key=self.fixture('project-a');_,b,other=self.fixture('project-b')
  status=self.call('/status');self.assertIsNone(status['active']);self.assertEqual(status['enabledProjects'],[])
  self.assertFalse((self.root/'Workspace/project-devices.json').exists())
  first=self.call('/runtime',key=key);self.assertEqual(first['page']['id'],'home');self.assertFalse(first['editing']);self.assertFalse(first['linked'])
  second=self.call('/runtime',key=other);self.assertNotEqual(first['projectID'],second['projectID'])
  node=next(n['id'] for n in first['page']['nodes'] if n.get('text')=='Open detail')
  result=self.call('/event',{'event':{'node':node},'side':'web','projectID':a['projectID'],'returnRuntime':True},key)
  self.assertEqual(result['runtime']['page']['id'],'detail')
  record_path=self.root/'Workspace'/a['projectID']/'record.json';record=json.loads(record_path.read_text())
  self.assertEqual(record['sessions']['ios']['stack'][-1]['page'],'home');self.assertNotIn('_snapshotMode',record)
  self.assertEqual(self.call('/runtime',key=other)['page']['id'],'home')
  for endpoint,body in [('/export-start',{}),('/run-ios',{}),('/activate-project',{'id':b['projectID']}),('/event',{'side':'ios','event':{}}),('/event',{'projectID':b['projectID'],'event':{}})]:
   with self.assertRaises(urllib.error.HTTPError):self.call(endpoint,body,key)
  self.call('/event',{'event':{'type':'navigate','page':'home','preview':True}},key)
  record=json.loads(record_path.read_text());overrides={'removed-layer':{'type':'text','base':{},'patch':{'x':75}}};record['overrides']=overrides;record_path.write_text(json.dumps(record))
  file=source/'pages/home/page.html';valid=file.read_text();file.write_text(valid.replace('left:24;top:100','left:42;top:100'))
  for _ in range(60):
   fresh=self.call('/runtime',key=key)
   if any(n.get('text')=='Browser test' and n['x']==42 for n in fresh['page']['nodes']):break
   time.sleep(.1)
  else:self.fail('source watcher did not reload')
  saved=json.loads(record_path.read_text());self.assertEqual(saved['model']['hash'],fresh['modelHash']);self.assertEqual(saved['overrides'],overrides);self.assertEqual(saved['sessions']['ios']['stack'][-1]['page'],'home')
  file.write_text('<ui-page><invalid-widget/></ui-page>')
  for _ in range(60):
   state=self.call('/runtime',key=key)
   if state['browserInfo']['error']:break
   time.sleep(.1)
  else:self.fail('compile error not exposed')
  self.assertEqual(state['modelHash'],fresh['modelHash'])
  file.write_text(valid)
  for _ in range(60):
   if not self.call('/runtime',key=key)['browserInfo']['error']:break
   time.sleep(.1)
  else:self.fail('compile recovery failed')
  attached=self.call('/browser-attach',{'source':str(source)})
  self.assertEqual(attached['projectID'],a['projectID'])
  self.assertEqual(self.call('/status')['enabledProjects'],[])
  type(self).proc.terminate();type(self).proc.wait(timeout=10)
  type(self).proc=subprocess.Popen([sys.executable,str(self.root/'bridge/server.py')],stdout=self.log,stderr=self.log,env={**os.environ,'STUDIO_BROWSER_ONLY':'1'})
  for _ in range(100):
   try:self.call('/health');break
   except Exception:time.sleep(.1)
  restored=self.call('/runtime',key=key);self.assertEqual(restored['projectID'],a['projectID']);self.assertEqual(restored['modelHash'],json.loads(record_path.read_text())['model']['hash'])

if __name__=='__main__':unittest.main()
