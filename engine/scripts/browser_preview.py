#!/usr/bin/env python3
"""Print a project-bound Codex browser URL; no GUI, simulator or AI task starts."""
import argparse,json,os,subprocess,sys,urllib.request
from pathlib import Path

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--source',required=True,help='app.json 所在目录，或包含 HTMLNativeStudio/HTML 的项目目录')
 args=parser.parse_args();root=Path(__file__).resolve().parents[1]
 source=Path(args.source).expanduser().resolve()
 source=next((p for p in (source,source/'HTMLNativeStudio/HTML',source/'HTMLNativeStudio') if (p/'app.json').is_file()),source)
 if not (source/'app.json').is_file():raise ValueError('没有找到工作台 app.json；请先在此项目创建符合工作台规范的 HTML 源码。不会转换或覆盖普通 HTML。')
 subprocess.run([sys.executable,str(root/'scripts/launch.py'),'--browser-only'],check=True,stdout=sys.stderr)
 config=json.loads((root/'bridge/config.json').read_text())
 request=urllib.request.Request(f"http://127.0.0.1:{config['port']}/browser-attach",data=json.dumps({'source':str(source)}).encode(),headers={'Content-Type':'application/json','X-Studio-Token':(root/'bridge/token').read_text().strip()})
 with urllib.request.urlopen(request,timeout=120) as response:result=json.load(response)
 print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
 try:main()
 except Exception as error:print('浏览器预览未启动：'+str(error),file=sys.stderr);sys.exit(1)
