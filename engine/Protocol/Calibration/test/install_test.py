"""Validate actual authoring installation, preserving user rules and path boundaries."""
import sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[3]/'bridge'))
import authoring
class InstallTest(unittest.TestCase):
 def test_tools_and_user_rules(self):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d);(p/'app.json').write_text('{}');(p/'AGENTS.md').write_text('USER CUSTOM RULE\n');(p/'CODEX_TASK.md').write_text('USER CUSTOM TASK')
   authoring.install(p)
   for name in authoring.CALIBRATION_FILES:self.assertTrue((p/'.studio/authoring/calibration'/name).is_file())
   self.assertTrue((p/'.studio/authoring/自动参数校准.md').is_file())
   self.assertTrue((p/'.studio/authoring/生成素材规则.md').is_file())
   self.assertIn('generated-assets/1',authoring.payload()['guide'])
   for guide in ['模型彩绘扩展.md','图层运行时动效扩展.md']:
    self.assertTrue((p/'.studio/authoring'/guide).is_file())
   authoring.install(p)
   self.assertEqual((p/'AGENTS.md').read_text().count('USER CUSTOM RULE'),1)
   self.assertEqual((p/'CODEX_TASK.md').read_text(),'USER CUSTOM TASK')
 def test_symlink_preflight_writes_nothing(self):
  with tempfile.TemporaryDirectory() as d,tempfile.TemporaryDirectory() as outside:
   p=Path(d);(p/'app.json').write_text('{}');(p/'AGENTS.md').write_text('UNCHANGED');(p/'.studio/authoring').mkdir(parents=True)
   (p/'.studio/authoring/calibration').symlink_to(outside,target_is_directory=True)
   with self.assertRaises(ValueError):authoring.install(p)
   self.assertEqual((p/'AGENTS.md').read_text(),'UNCHANGED');self.assertEqual(list(Path(outside).iterdir()),[])
if __name__=='__main__':unittest.main()
