import copy,json,subprocess,sys,tempfile,unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine/bridge'))
from project_devices import ProjectDevices,DEFAULT_DEVICE_TYPE

RUNTIME='com.apple.CoreSimulator.SimRuntime.iOS-26-4'
OLDER='com.apple.CoreSimulator.SimRuntime.iOS-26-3'
OTHER_TYPE='com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'

class Inventory:
 def __init__(self):
  self.types=[{'identifier':DEFAULT_DEVICE_TYPE,'name':'iPhone 16 Pro','productFamily':'iPhone'},{'identifier':OTHER_TYPE,'name':'iPhone 17 Pro','productFamily':'iPhone'}]
  self.data={'runtimes':[{'identifier':RUNTIME,'version':'26.4','isAvailable':True,'supportedDeviceTypes':self.types}],'devicetypes':self.types,'devices':{RUNTIME:[]}}
  self.commands=[];self.created=0;self.fail=False
 def add(self,udid,dtype=DEFAULT_DEVICE_TYPE,available=True):
  self.data['devices'][RUNTIME].append({'udid':udid,'deviceTypeIdentifier':dtype,'isAvailable':available,'state':'Booted'})
 def run(self,command,**kwargs):
  self.commands.append(command)
  if command==['xcrun','simctl','list','--json']:return json.dumps(self.data).encode()
  if command[:3]!=['xcrun','simctl','create']:raise AssertionError('No boot/shutdown/delete allowed: '+repr(command))
  if self.fail:raise subprocess.CalledProcessError(1,command)
  self.created+=1;device='new-device-'+str(self.created)
  self.data['devices'].setdefault(command[-1],[]).append({'udid':device,'deviceTypeIdentifier':command[-2],'isAvailable':True})
  return device+'\n'

class RecoveryTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.config={'ios':'deleted-template','developerDir':'/fixture/Xcode'};self.inventory=Inventory()
  self.mock=patch('project_devices.subprocess.check_output',side_effect=self.inventory.run);self.mock.start()
  self.pool=ProjectDevices(self.root,self.config)
 def tearDown(self):self.mock.stop();self.temp.cleanup()
 def saved(self,value=None):
  if value is not None:self.pool.path.parent.mkdir(parents=True,exist_ok=True);self.pool.path.write_text(json.dumps(value))
  return json.loads(self.pool.path.read_text()) if self.pool.path.exists() else {}
 def test_deleted_mapping_and_template_create_only_requested_project_with_installation_dimensions(self):
  self.saved({'a':'deleted-a','b':'deleted-b'});self.inventory.add('external-booted-phone',OTHER_TYPE)
  reply=self.pool.ensure('a','CampByte')
  self.assertEqual(reply['ios'],'new-device-1');self.assertEqual(reply['iosDeviceType'],DEFAULT_DEVICE_TYPE);self.assertEqual(reply['iosRuntime'],RUNTIME)
  self.assertEqual(self.saved(),{'a':'new-device-1','b':'deleted-b'});self.assertEqual(self.inventory.created,1)
  self.assertEqual(self.inventory.data['devices'][RUNTIME][0]['state'],'Booted')
  self.assertEqual(self.config,{'ios':'deleted-template','developerDir':'/fixture/Xcode'})
 def test_no_existing_device_uses_supported_runtime_types(self):
  self.assertEqual(self.pool.ensure('a')['iosDeviceType'],DEFAULT_DEVICE_TYPE)
  self.assertEqual(self.inventory.commands[-1][-2:],[DEFAULT_DEVICE_TYPE,RUNTIME])
 def test_empty_mapping_never_adopts_existing_template(self):
  self.inventory.add('deleted-template')
  self.assertEqual(self.pool.ensure('a')['ios'],'new-device-1')
  self.assertEqual(self.inventory.created,1)
 def test_existing_assignment_is_revalidated_after_external_delete_and_keeps_known_type(self):
  self.inventory.add('assigned',OTHER_TYPE);self.saved({'a':'assigned'})
  self.assertEqual(self.pool.ensure('a')['ios'],'assigned');self.assertEqual(self.inventory.created,0)
  self.inventory.data['devices'][RUNTIME]=[]
  self.assertEqual(self.pool.ensure('a')['iosDeviceType'],OTHER_TYPE);self.assertEqual(self.inventory.created,1)
 def test_unavailable_or_duplicate_assignment_is_not_reused(self):
  self.inventory.add('unavailable',available=False);self.saved({'a':'unavailable','b':'unavailable'})
  self.assertEqual(self.pool.ensure('a')['ios'],'new-device-1');self.assertEqual(self.saved()['b'],'unavailable')
  self.saved({'a':'new-device-1','b':'new-device-1'})
  self.assertEqual(self.pool.ensure('a')['ios'],'new-device-2');self.assertEqual(self.saved()['b'],'new-device-1')
 def test_explicit_type_runtime_override_an_unrelated_existing_phone(self):
  older=copy.deepcopy(self.inventory.data['runtimes'][0]);older.update(identifier=OLDER,version='26.3');self.inventory.data['runtimes'].append(older)
  self.inventory.add('unrelated');config={**self.config,'iosDeviceType':OTHER_TYPE,'iosRuntime':OLDER}
  result=ProjectDevices(self.root,config).ensure('a')
  self.assertEqual((result['iosDeviceType'],result['iosRuntime']),(OTHER_TYPE,OLDER))
 def test_concurrent_instances_create_one_device_per_project_without_lost_mappings(self):
  pools=[ProjectDevices(self.root,self.config) for _ in range(4)]
  with ThreadPoolExecutor(max_workers=4) as workers:results=list(workers.map(lambda item:item[0].ensure(item[1]),zip(pools,['a','a','b','b'])))
  self.assertEqual(results[0]['ios'],results[1]['ios']);self.assertEqual(results[2]['ios'],results[3]['ios']);self.assertNotEqual(results[0]['ios'],results[2]['ios'])
  self.assertEqual(self.inventory.created,2);self.assertEqual(set(self.saved()),{'a','b'})
 def test_failed_creation_preserves_all_existing_assignments(self):
  before={'a':'deleted-a','b':'deleted-b'};self.saved(before);self.inventory.fail=True
  with self.assertRaises(subprocess.CalledProcessError):self.pool.ensure('a')
  self.assertEqual(self.saved(),before)
 def test_unavailable_runtime_and_unsupported_explicit_type_fail_without_creation(self):
  self.inventory.data['runtimes'][0]['isAvailable']=False
  with self.assertRaisesRegex(ValueError,'iOS 26'):self.pool.ensure('a')
  self.inventory.data['runtimes'][0]['isAvailable']=True
  with self.assertRaisesRegex(ValueError,'设备类型'):ProjectDevices(self.root,{**self.config,'iosDeviceType':'missing-device-type'}).ensure('a')
  self.assertEqual(self.inventory.created,0);self.assertEqual(self.saved(),{})

if __name__=='__main__':unittest.main()
