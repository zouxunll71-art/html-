import sys,tempfile,json,unittest,hashlib,copy
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine/bridge'))
from record_cache import RecordCache
class RecordCacheTests(unittest.TestCase):
 def test_state_isolation_and_durable_write(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'record.json';cache=RecordCache();initial={'model':{'hash':'a','pages':{'home':{}}},'sessions':{'ios':{'n':0}},'name':'中文'}
   cache.write(p,initial);a=cache.read(p);b=cache.read(p);a['sessions']['ios']['n']=1
   self.assertEqual(b['sessions']['ios']['n'],0);cache.write(p,a)
   self.assertEqual(json.loads(p.read_text())['sessions']['ios']['n'],1)
   self.assertEqual(cache.read(p)['sessions']['ios']['n'],1)
 def test_external_replacement_and_compile_invalidation(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'record.json';c=RecordCache();c.write(p,{'model':{'hash':'a'},'state':0})
   replacement=Path(d)/'external';replacement.write_text(json.dumps({'model':{'hash':'b'},'state':2}));replacement.replace(p)
   r=c.read(p);self.assertEqual(r['model']['hash'],'b');r['model']={'hash':'c'};c.write(p,r)
   self.assertEqual(json.loads(p.read_text())['model']['hash'],'c')
 def test_eviction(self):
  with tempfile.TemporaryDirectory() as d:
   c=RecordCache(limit=2)
   for i in range(4):c.write(Path(d)/str(i),{'model':{'hash':str(i)},'state':i})
   self.assertEqual(len(c.entries),2);self.assertEqual(c.read(Path(d)/'0')['state'],0)
if __name__=='__main__':unittest.main()
