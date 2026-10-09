import ast,json,socket,threading,time,unittest,urllib.request,sys
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer

# Exercise the maintained response implementation without booting simulators or
# importing the engine service's process-starting module globals.
tree=ast.parse((Path(__file__).resolve().parents[1]/'engine/bridge/server.py').read_text())
handler=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Handler')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine/bridge'))
import performance_trace
scope={'BaseHTTPRequestHandler':BaseHTTPRequestHandler,'json':json,'performance_trace':performance_trace}
exec(compile(ast.Module(body=[handler],type_ignores=[]),'<bridge Handler>','exec'),scope)
Handler=scope['Handler']

class Responses(unittest.TestCase):
 def test_snapshot_is_frozen_before_unlock(self):
  value={'revision':1,'nested':{'ids':['a']}}
  response=Handler.respond(None,value);value['revision']=2;value['nested']['ids'].append('b')
  self.assertEqual(json.loads(response[0]),{'revision':1,'nested':{'ids':['a']}})
 def test_slow_reader_does_not_hold_other_requests(self):
  lock=threading.RLock();started=threading.Event()
  class Probe(Handler):
   def _handle_request(self):
    with lock:
     if self.path=='/slow':started.set();return self.respond({'data':'x'*16_000_000})
     return self.respond({'ok':True})
  server=ThreadingHTTPServer(('127.0.0.1',0),Probe)
  threading.Thread(target=server.serve_forever,daemon=True).start()
  slow=socket.socket();slow.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,1024)
  try:
   slow.connect(server.server_address);slow.sendall(b'GET /slow HTTP/1.0\r\nHost: localhost\r\n\r\n')
   self.assertTrue(started.wait(2));time.sleep(.2)
   # The 16 MB response cannot fit in the non-reading socket's tiny window.
   # A second request must finish before releasing that first connection.
   response=urllib.request.urlopen('http://127.0.0.1:'+str(server.server_port)+'/fast',timeout=1)
   self.assertEqual(json.load(response),{'ok':True})
  finally:slow.close();server.shutdown();server.server_close()
 def test_binary_errors_and_streams_keep_their_http_contract(self):
  class Probe(Handler):
   def _handle_request(self):
    if self.path=='/binary':return self.respond(b'\x00\xff',mime='application/octet-stream',cache='private, max-age=60')
    if self.path=='/error':return self.respond({'error':'invalid'},400)
    self.send_response(200);self.send_header('Content-Length','6');self.end_headers();self.wfile.write(b'stream')
  server=ThreadingHTTPServer(('127.0.0.1',0),Probe)
  threading.Thread(target=server.serve_forever,daemon=True).start()
  base='http://127.0.0.1:'+str(server.server_port)
  try:
   with urllib.request.urlopen(base+'/binary') as response:
    self.assertEqual(response.read(),b'\x00\xff');self.assertEqual(response.headers['Content-Length'],'2');self.assertEqual(response.headers['Cache-Control'],'private, max-age=60')
   with self.assertRaises(urllib.error.HTTPError) as error:urllib.request.urlopen(base+'/error')
   self.assertEqual(error.exception.code,400);self.assertEqual(json.load(error.exception),{'error':'invalid'})
   with urllib.request.urlopen(base+'/stream') as response:self.assertEqual(response.read(),b'stream')
  finally:server.shutdown();server.server_close()

if __name__=='__main__':unittest.main()
