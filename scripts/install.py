#!/usr/bin/env python3
"""Install a clean checkout using only this Mac's paths and credentials."""
import argparse,os,sys,shutil,subprocess,importlib.util,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
 if sys.platform!='darwin':raise RuntimeError('目前仅支持 macOS，Windows/Linux 尚未提供。')
 node=shutil.which('node')
 if not node:raise RuntimeError('请先安装 Node.js 22 或更新版本。')
 if int(subprocess.check_output([node,'--version'],text=True).strip().lstrip('v').split('.')[0])<22:raise RuntimeError('需要 Node.js 22 或更新版本。')
 sys.path.insert(0,str(ROOT/'native'));from environment import developer_dir
 developer=developer_dir()
 codex_candidates=[os.environ.get('CODEX_BINARY','')]+[str(base/app/'Contents/Resources/codex') for base in [Path('/Applications'),Path.home()/'Applications'] for app in ['Codex.app','ChatGPT.app']]+[shutil.which('codex') or '']
 codex=next((p for p in codex_candidates if p and os.access(p,os.X_OK)),None)
 if not codex:raise RuntimeError('请先安装 Codex 桌面应用并登录自己的账号。')
 base=Path.home()/'Library/Application Support/HTMLNativeStudio';engine=base/'Engine';client=base/'Client';app=Path.home()/'Applications/HTML Native Studio.app'
 print('运行环境检查通过。');print('工作台文件：',base);print('应用：',app)
 if args.check:return
 # Refuse to mutate an engine while its local service is running.
 import socket
 for port in [18775,18777]:
  with socket.socket() as probe:
   if probe.connect_ex(('127.0.0.1',port))==0:raise RuntimeError('工作台服务正在运行。请退出已有版本及后台服务后再安装，避免影响当前项目。')
 base.mkdir(parents=True,exist_ok=True)
 for dest,source in [(engine,ROOT/'engine')]:shutil.copytree(source,dest,dirs_exist_ok=True,ignore=shutil.ignore_patterns('node_modules','__pycache__','config.json','token','bridge-token.txt'))
 client.mkdir(exist_ok=True)
 for file in ROOT.glob('*.mjs'):shutil.copy2(file,client/file.name)
 for name in ['package.json','package-lock.json']:shutil.copy2(ROOT/name,client/name)
 for name in ['web','native']:shutil.copytree(ROOT/name,client/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('__pycache__','symbols','ios-frames','windows'))
 env=dict(os.environ,DEVELOPER_DIR=developer,STUDIO_ROOT=str(engine),CODEX_BINARY=codex,STUDIO_APP_DEST=str(app))
 for directory in [client,engine/'bridge/parser']:subprocess.run(['npm','ci','--ignore-scripts'],cwd=directory,env=env,check=True)
 spec=importlib.util.spec_from_file_location('studio_bootstrap',engine/'scripts/bootstrap.py');bootstrap=importlib.util.module_from_spec(spec);spec.loader.exec_module(bootstrap)
 bootstrap.prepare(engine,launch=False)
 subprocess.run(['/bin/zsh',str(engine/'scripts/build.sh')],cwd=engine,env=env,check=True)
 subprocess.run([sys.executable,str(client/'native/build_all.py')],cwd=client,env=env,check=True)
 (base/'installation.json').write_text(json.dumps({'engine':str(engine),'client':str(client),'app':str(app)},ensure_ascii=False,indent=2))
 print('安装完成，请打开：',app)
if __name__=='__main__':
 try:main()
 except Exception as error:print('安装未完成：'+str(error),file=sys.stderr);sys.exit(1)
