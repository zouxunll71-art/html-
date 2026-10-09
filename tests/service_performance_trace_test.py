import ast,copy,json,os,sys,tempfile,threading,time,unittest,urllib.error,urllib.request
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'engine/bridge'))
import performance_trace as perf

class TraceUnit(unittest.TestCase):
 def test_default_and_invalid_headers_do_not_read_clocks_or_write(self):
  with patch.object(perf,'ENABLED',False),patch.object(perf.time,'monotonic_ns',side_effect=AssertionError('disabled clock')):
   for path,headers in [('/event',{}),('/runtime',{'X-Studio-Trace-ID':'test'}),('/event',{'X-Studio-Trace-ID':'secret\nline'}),('/event',{'X-Studio-Trace-ID':'x'*161})]:
    self.assertIsNone(perf.begin(path,headers))
   lock=threading.RLock();self.assertIs(perf.locked(lock,None),lock)
   with perf.span(None,'ignored'):pass
 def test_monotonic_and_cpu_records_are_bounded_and_private(self):
  with tempfile.TemporaryDirectory() as folder,patch.object(perf,'OUTPUT',Path(folder)/'trace.jsonl'):
   trace=perf.begin('/event',{'X-Studio-Trace-ID':'x'*160});trace.bind('project-1','event-1','web',6)
   trace.bind('/private/test-project/source','body\nsecret','other',True)
   with trace.span('wait'):time.sleep(.005)
   trace.finish(200);trace.finish(201)
   record=json.loads(perf.OUTPUT.read_text());self.assertEqual(record['status'],200);self.assertEqual(record['projectID'],'project-1');self.assertEqual(record['revision'],6)
   self.assertGreater(record['monotonicStartNs'],0);wait=record['spans'][1]
   self.assertGreater(wait['durationNs'],wait['threadCpuNs']);self.assertGreaterEqual(wait['startNs'],0)
   self.assertEqual(os.stat(perf.OUTPUT).st_mode&0o777,0o600)
   size=perf.OUTPUT.stat().st_size
   with patch.object(perf,'MAX_FILE_BYTES',size):perf.RequestTrace('full').finish(200)
   self.assertEqual(perf.OUTPUT.stat().st_size,size)
   trace=perf.RequestTrace('bounded')
   for _ in range(100):
    with trace.span('bounded'):pass
   self.assertEqual(len(trace.spans),64)
 def test_environment_switch_and_log_errors_are_best_effort(self):
  with patch.object(perf,'ENABLED',True),patch.object(perf,'OUTPUT',Path('/no-such-diagnostic-directory/trace.jsonl')):
   trace=perf.begin('/event',{});self.assertIsNotNone(trace);trace.finish(400)
  with tempfile.TemporaryDirectory() as folder:
   target=Path(folder)/'target';target.write_text('preserve')
   link=Path(folder)/'link';link.symlink_to(target)
   with patch.object(perf,'OUTPUT',link):perf.RequestTrace('symlink').finish(200)
   self.assertEqual(target.read_text(),'preserve')
   fifo=Path(folder)/'fifo';os.mkfifo(fifo,0o600)
   with patch.object(perf,'OUTPUT',fifo):perf.RequestTrace('fifo').finish(200)
 def test_failed_span_releases_state_lock_and_does_not_swallow_error(self):
  trace=perf.RequestTrace('exception');lock=threading.RLock()
  with self.assertRaisesRegex(ValueError,'original'):
   with perf.locked(lock,trace):
    with trace.span('failure'):raise ValueError('original')
  self.assertFalse(lock._is_owned())
  self.assertTrue(next(s for s in trace.spans if s['phase']=='failure')['failed'])
  self.assertTrue(next(s for s in trace.spans if s['phase']=='lock.hold')['failed'])

def service():
 # Run the actual maintained handler/event/runtime functions, without importing
 # globals that launch the real Node worker, watcher or simulator services.
 tree=ast.parse((ROOT/'engine/bridge/server.py').read_text())
 names={'Handler','event','runtime','frame_arguments','local_navigation_host'}
 definitions=[n for n in tree.body if isinstance(n,(ast.ClassDef,ast.FunctionDef)) and n.name in names]
 record={'id':'project-1','model':{'hash':'model-1','assets':[]},'sessions':{'web':{'stack':[{'page':'home'}]},'ios':{'stack':[{'page':'home'}]}}}
 scope=dict(BROWSER=type("Browser",(),{"owns":lambda self,key:False})(),BaseHTTPRequestHandler=BaseHTTPRequestHandler,json=json,time=time,copy=copy,performance_trace=perf,urlparse=urlparse,parse_qs=parse_qs,
  TOKEN='test-token-never-log',ACTIVE='project-1',REV=1,PROCESSED={},LOCK=threading.RLock(),CHROME_TARGETS={},BROWSER_OPEN={},CLOSE_BROWSER=set())
 def read(pid):
  if pid!='project-1':raise ValueError('invalid private path /private/test-project')
  return copy.deepcopy(record)
 def store(value):record.clear();record.update(copy.deepcopy(value))
 def eng(op,**kwargs):
  if op=='event':return {'stack':[{'page':kwargs['event'].get('page','other')}],'value':kwargs['event'].get('value')}
  if op=='interaction':return {'declaration':{'action':'go','page':'other'},'pageID':'home'}
  raise AssertionError(op)
 def bump():scope['REV']+=1
 scope.update(read=read,store=store,eng=eng,bump=bump,mode_for=lambda r:(True,False),schedule_effects=lambda *args,**kwargs:None,
  frame=lambda r,side:{'id':r['sessions'][side]['stack'][-1]['page'],'nodes':[]},source_resources=type('Source',(),{'signature':staticmethod(lambda page:'signature')})())
 exec(compile(ast.Module(body=definitions,type_ignores=[]),'<actual bridge event handler>','exec'),scope)
 server=ThreadingHTTPServer(('127.0.0.1',0),scope['Handler']);threading.Thread(target=server.serve_forever,daemon=True).start()
 return server,scope,record

class TraceHandler(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.output=Path(self.temp.name)/'trace.jsonl'
  self.patch=patch.object(perf,'OUTPUT',self.output);self.patch.start()
  self.enabled=patch.object(perf,'ENABLED',False);self.enabled.start()
  self.server,self.scope,self.record=service();self.base='http://127.0.0.1:'+str(self.server.server_port)
 def tearDown(self):
  self.server.shutdown();self.server.server_close();self.enabled.stop();self.patch.stop();self.temp.cleanup()
 def request(self,trace=None,event_id='event-1',page_id='home',value='private-business-text'):
  headers={'Content-Type':'application/json','X-Studio-Token':'test-token-never-log'}
  if trace:headers['X-Studio-Trace-ID']=trace
  body={'side':'web','projectID':'project-1','eventID':event_id,'pageID':page_id,'event':{'type':'navigate','page':'other','value':value},'returnRuntime':True,'modelHash':'model-1'}
  request=urllib.request.Request(self.base+'/event',data=json.dumps(body).encode(),headers=headers)
  try:response=urllib.request.urlopen(request,timeout=3)
  except urllib.error.HTTPError as error:response=error
  with response:return response.status,json.load(response)
 def wait_records(self,count):
  deadline=time.monotonic()+2
  while time.monotonic()<deadline:
   try:rows=[json.loads(line) for line in self.output.read_text().splitlines()]
   except FileNotFoundError:rows=[]
   if len(rows)>=count:return rows
   time.sleep(.005)
  self.fail('missing trace records')
 def test_disabled_and_traced_event_preserve_state_and_http_results(self):
  status,result=self.request();self.assertEqual(status,200);self.assertFalse(self.output.exists())
  before=copy.deepcopy(self.record)
  status,traced=self.request('trace.duplicate');self.assertEqual(status,200);self.assertEqual(traced,result);self.assertEqual(self.record,before)
  self.wait_records(1)
 def test_complete_phases_and_lock_wait_cpu_are_measured_without_log_under_lock(self):
  lock=self.scope['LOCK'];logged=[];original=perf.RequestTrace.finish
  def finish(trace,*args):
   self.assertFalse(lock._is_owned());logged.append(True);return original(trace,*args)
  ready=threading.Event()
  def hold():
   with lock:ready.set();time.sleep(.06)
  thread=threading.Thread(target=hold);thread.start();ready.wait()
  with patch.object(perf.RequestTrace,'finish',finish):status,result=self.request('studio-perf:request-1');rows=self.wait_records(1)
  thread.join();self.assertEqual(status,200);self.assertTrue(logged)
  row=rows[0];phases={s['phase']:s for s in row['spans']}
  for phase in ['request.received','request.decode','lock.wait','lock.hold','event.validation','event.reducer','event.persist','runtime.compose','runtime.response','response.serialize','response.write']:self.assertIn(phase,phases)
  self.assertGreater(phases['lock.wait']['durationNs'],20_000_000)
  self.assertGreater(phases['lock.wait']['durationNs'],phases['lock.wait']['threadCpuNs'])
  self.assertGreaterEqual(phases['response.write']['startNs'],phases['lock.hold']['startNs']+phases['lock.hold']['durationNs'])
  self.assertEqual((row['traceID'],row['eventID'],row['projectID'],row['revision']),('studio-perf:request-1','event-1','project-1',result['revision']))
  raw=self.output.read_text()
  for secret in ['private-business-text','test-token-never-log','/private/test-project','model-1']:self.assertNotIn(secret,raw)
 def test_validation_failure_keeps_http_error_and_does_not_commit(self):
  before=copy.deepcopy(self.record);status,result=self.request('trace.error',page_id='stale')
  self.assertEqual(status,400);self.assertIn('error',result);self.assertEqual(before,self.record)
  row=self.wait_records(1)[0];phases={s['phase']:s for s in row['spans']}
  self.assertTrue(phases['event.validation']['failed']);self.assertNotIn('event.persist',phases)
  self.assertEqual(row['status'],400)

if __name__=='__main__':unittest.main()
