import os,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def developer_dir():
 candidates=[os.environ.get('DEVELOPER_DIR','')]
 result=subprocess.run(['xcode-select','-p'],capture_output=True,text=True)
 candidates.append(result.stdout.strip())
 candidates += [str(p/'Contents/Developer') for p in Path('/Applications').glob('Xcode*.app')]
 for candidate in candidates:
  if candidate and (Path(candidate)/'Applications/Simulator.app').exists():return candidate
 raise RuntimeError('未找到完整 Xcode，请设置 DEVELOPER_DIR 或安装 Xcode。')
def engine_root():
 if os.environ.get('STUDIO_ROOT'):return Path(os.environ['STUDIO_ROOT']).expanduser().resolve()
 current=Path.home()/'Library/Application Support/HTMLNativeStudio/Engine'
 if (current/'bridge/config.json').exists():return current
 legacy=Path.home()/'Library/Application Support/HTMLNativeStudio-Share-1.0.2'
 return legacy if (legacy/'bridge/config.json').exists() else ROOT/'engine'
def build_env():return dict(os.environ,DEVELOPER_DIR=developer_dir())
