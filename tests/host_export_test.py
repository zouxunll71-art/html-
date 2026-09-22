import sys,tempfile,unittest,subprocess,json,shutil
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'engine/bridge'))
import host_export
class ExportTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve();self.bundle=self.root/'HTMLNativeStudio';self.target=self.root/'App';self.target.mkdir();(self.bundle/'iOS').mkdir(parents=True)
  subprocess.run([sys.executable,str(ROOT/'engine/scripts/make_project.py'),str(self.root),'Demo','App'],check=True,capture_output=True)
  (self.target/'ViewController.swift').write_text('import UIKit\nclass ViewController: UIViewController { override func viewDidLoad() { super.viewDidLoad() } }')
  (self.target/'Base.lproj').mkdir();(self.target/'Base.lproj/Main.storyboard').write_text('<viewController customClass="ViewController"/>')
  (self.target/'Info.plist').write_text('configuration sentinel')
  self.out=self.bundle/'iOS/export';(self.out/'App').mkdir(parents=True);(self.out/'Shared').mkdir()
  (self.out/'App/HNApp.swift').write_text('import UIKit\n@main final class HNNativeRuntimeApp {}\nfinal class HNNativeRuntimeController:UIViewController {}')
  (self.out/'App/contract.json').write_text('{}');(self.out/'Shared/engine.js').write_text('engine');(self.out/'App/AppInfo.plist').write_text('not copied')
 def tearDown(self):self.temp.cleanup()
 def migrate(self):return host_export.migrate(host_export.inspect(self.bundle),self.out,'HN')
 def test_repeat_export_preserves_settings_and_replaces_only_generated_files(self):
  before=host_export.inventory(self.root/'Demo.xcodeproj');self.migrate()
  (self.out/'Shared/new.swift').write_text('new');(self.out/'Shared/engine.js').unlink();self.migrate()
  self.assertEqual(before,host_export.inventory(self.root/'Demo.xcodeproj'));self.assertEqual((self.target/'Info.plist').read_text(),'configuration sentinel')
  self.assertFalse((self.target/'StudioGenerated/engine.js').exists());self.assertTrue((self.target/'StudioGenerated/new.swift').exists())
  self.assertNotIn('@main',(self.target/'StudioGenerated/HNApp.swift').read_text());self.assertFalse((self.target/'StudioGenerated/AppInfo.plist').exists())
 def test_custom_code_and_multiple_targets_are_not_overwritten(self):
  (self.target/'ViewController.swift').write_text('custom code')
  with self.assertRaises(ValueError):host_export.inspect(self.bundle)
  self.assertEqual((self.target/'ViewController.swift').read_text(),'custom code')
 def test_manual_generated_edit_blocks_repeat(self):
  self.migrate();(self.target/'StudioGenerated/contract.json').write_text('manual')
  with self.assertRaises(ValueError):self.migrate()
  self.assertEqual((self.target/'StudioGenerated/contract.json').read_text(),'manual')
 def test_install_failure_rolls_back(self):
  self.migrate();before=host_export.inventory(self.target);original=Path.replace
  def fail_entry(path,dest):
   if path.name=='ViewController.swift':raise OSError('simulated write failure')
   return original(path,dest)
  with patch.object(Path,'replace',fail_entry):
   with self.assertRaises(OSError):self.migrate()
  self.assertEqual(before,host_export.inventory(self.target))
 def test_no_host_keeps_standalone_export(self):
  shutil.rmtree(self.root/'Demo.xcodeproj');self.assertIsNone(host_export.inspect(self.bundle))
if __name__=='__main__':unittest.main()
