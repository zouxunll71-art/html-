import json,sys,tempfile,types,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'engine/bridge'))
import ios_runner as runner
class RuntimeReuseTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name)
  self.app=self.root/'build/runtime/Build/Products/Debug-iphonesimulator/HTMLNativeRuntime.app';self.app.mkdir(parents=True)
  (self.app/'HTMLNativeRuntime').write_bytes(b'program');(self.app/'bridge-token.txt').write_bytes(b'test-token');(self.root/'artifacts').mkdir()
  (self.root/'artifacts/build-source.json').write_text(json.dumps({'fingerprint':'current'}))
 def test_missing_binary_or_changed_source_requires_build(self):
  self.assertTrue(runner.build_is_current(self.root,'current'))
  self.assertFalse(runner.build_is_current(self.root,'changed'))
  (self.app/'HTMLNativeRuntime').unlink();self.assertFalse(runner.build_is_current(self.root,'current'))
 def test_bundle_content_not_version_controls_install(self):
  import shutil
  installed=self.root/'installed';shutil.copytree(self.app,installed)
  self.assertTrue(runner.same_runtime_bundle(self.app,installed))
  (installed/'bridge-token.txt').write_bytes(b'other-token');self.assertFalse(runner.same_runtime_bundle(self.app,installed))
  (installed/'bridge-token.txt').write_bytes(b'test-token');(installed/'extra.js').write_text('stale')
  self.assertFalse(runner.same_runtime_bundle(self.app,installed))
 def exercise(self,same):
  import shutil
  installed=self.root/'installed';shutil.copytree(self.app,installed)
  if not same:(installed/'HTMLNativeRuntime').write_bytes(b'outdated')
  runner.JOBS['test']={'projectID':'project-b','state':'running','logPath':str(self.root/'artifacts/run.log')}
  calls=[];finished=[]
  def command(args,**kwargs):calls.append((args,kwargs));return types.SimpleNamespace(returncode=0)
  with patch.object(runner,'ROOT',self.root),patch.dict(sys.modules,{'source_stamp':types.SimpleNamespace(fingerprint=lambda _: 'current')}),patch.object(runner.subprocess,'run',side_effect=command),patch.object(runner.subprocess,'check_output',side_effect=[json.dumps({'devices':{'ios':[{'udid':'device-b','state':'Booted'}]}}).encode(),str(installed).encode()]):
   runner.run('test',{'ios':'device-b','developerDir':'/Xcode'},lambda pid:finished.append(pid))
  self.assertEqual(runner.JOBS['test']['reusedBuild'],True);self.assertEqual(runner.JOBS['test']['reusedInstall'],same);self.assertEqual(runner.JOBS['test']['state'],'done');self.assertEqual(finished,['project-b'])
  self.assertFalse(any(args[0]=='xcodebuild' for args,_ in calls))
  self.assertEqual(any('install' in args for args,_ in calls),not same)
  self.assertTrue(any('launch' in args for args,_ in calls))
  for args,kwargs in calls:
   self.assertEqual(kwargs['env']['SIMCTL_CHILD_STUDIO_PROJECT_ID'],'project-b')
   if args[:2]==['xcrun','simctl']:self.assertEqual(args[3],'device-b')
 def test_current_bundle_skips_install_and_keeps_project_binding(self):self.exercise(True)
 def test_stale_installed_bundle_still_installs(self):self.exercise(False)
if __name__=='__main__':unittest.main()
