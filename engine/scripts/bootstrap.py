"""Recipient-only setup: no developer paths, tokens, projects or simulator IDs."""
import os,sys,json,subprocess,shutil,secrets,fcntl,socket
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def run(args,env=None):
 p=subprocess.run(list(map(str,args)),env=env,capture_output=True,text=True,timeout=180)
 if p.returncode:raise RuntimeError((p.stderr or p.stdout)[-2400:])
 return p.stdout.strip()
def prepare(root=ROOT,launch=True):
 if sys.platform!='darwin':raise RuntimeError('需要使用 Mac。')
 (root/'artifacts').mkdir(exist_ok=True)
 candidates=[os.environ.get('DEVELOPER_DIR','')]
 p=subprocess.run(['xcode-select','-p'],capture_output=True,text=True);candidates.append(p.stdout.strip())
 candidates += [str(p/'Contents/Developer') for p in Path('/Applications').glob('Xcode*.app')]
 developer=next((p for p in candidates if p and (Path(p)/'Applications/Simulator.app').exists()),None)
 if not developer:raise RuntimeError('未找到完整 Xcode。请把 Xcode 安装到「应用程序」，打开一次完成初始化，并安装 iOS Simulator 运行时。仅 Command Line Tools 不够。')
 env=dict(os.environ,DEVELOPER_DIR=developer)
 print('正在检查 Xcode 和 Node.js…',flush=True)
 version=run(['xcodebuild','-version'],env)
 if int(version.splitlines()[0].split()[1].split('.')[0])<26:raise RuntimeError('需要 Xcode 26 或更新版本。')
 node=next((p for p in [shutil.which('node'),'/opt/homebrew/bin/node','/usr/local/bin/node'] if p and Path(p).is_file()),None)
 if not node:raise RuntimeError('未找到 Node.js。请从 https://nodejs.org 安装 Node.js 22 LTS 或更新版本，再重新打开工作台。')
 if int(run([node,'--version']).lstrip('v').split('.')[0])<22:raise RuntimeError('需要 Node.js 22 或更新版本。')
 conf=root/'bridge/config.json'
 old=json.loads(conf.read_text()) if conf.exists() else {}
 # Existing installation owns its fixed local port. Do not steal another instance's port.
 if not conf.exists():
  with socket.socket() as probe:
   try:probe.bind(('127.0.0.1',18775))
   except OSError:raise RuntimeError('本机 18775 端口被占用。请先退出其他版本的 HTML 原生工作台及其同步服务，再启动分享版。')
 devices=json.loads(run(['xcrun','simctl','list','devices','available','--json'],env))['devices']
 ids={d['udid'] for group in devices.values() for d in group}
 device=old.get('ios')
 if device not in ids:
  runtimes=json.loads(run(['xcrun','simctl','list','runtimes','--json'],env))['runtimes']
  runtimes=[r for r in runtimes if r.get('isAvailable') and 'iOS' in r['identifier'] and int(r['version'].split('.')[0])>=26]
  if not runtimes:raise RuntimeError('缺少 iOS 26 或更新的模拟器运行时。请打开 Xcode → Settings → Components 安装后重试。')
  runtime=max(runtimes,key=lambda r:tuple(map(int,r['version'].split('.'))))
  types=json.loads(run(['xcrun','simctl','list','devicetypes','--json'],env))['devicetypes']
  dtype=next((t['identifier'] for t in types if t['name']=='iPhone 16 Pro'),None)
  if not dtype:raise RuntimeError('当前 Xcode 缺少 iPhone 16 Pro 设备类型，请更新 Xcode。')
  print('正在创建工作台专用 iPhone 模拟器…',flush=True)
  device=run(['xcrun','simctl','create','HTML Native Studio iOS',dtype,runtime['identifier']],env)
 token=root/'bridge/token'
 if not token.exists():token.write_text(secrets.token_hex(32));token.chmod(0o600)
 for folder in ['Studio','Runtime']:(root/folder/'bridge-token.txt').write_text(token.read_text())
 for folder in ['Workspace','Projects','build','artifacts']:(root/folder).mkdir(exist_ok=True)
 conf.write_text(json.dumps(dict(port=18775,node=node,developerDir=developer,ios=device)))
 env['PATH']=str(Path(node).parent)+':'+env.get('PATH','/usr/bin:/bin')
 print('首次启动将编译工作台，可能需要几分钟…',flush=True)
 if launch:subprocess.run([sys.executable,str(root/'scripts/launch.py')],env=env,check=True)
 return dict(developerDir=developer,node=node)
if __name__=='__main__':
 try:
  with (ROOT/'.setup.lock').open('w') as lock:fcntl.flock(lock,fcntl.LOCK_EX);prepare()
 except Exception as e:print('启动未完成：'+str(e),flush=True);sys.exit(1)
