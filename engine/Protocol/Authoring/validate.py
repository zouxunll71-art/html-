#!/usr/bin/env python3
"""Run the installed contract compiler and shared layout engine without the GUI."""
import json,sys,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
PROJECT=HERE.parent.parent
try:
 config=json.loads((HERE/'system.json').read_text());system=Path(config['systemRoot'])
 if not (system/'bridge/compiler.py').is_file():raise ValueError('找不到 HTML Native Studio；请在新机器导入项目并重新安装编写规范')
 sys.path.insert(0,str(system/'bridge'))
 from compiler import compile_project
 model=compile_project(PROJECT)
 node=json.loads((system/'bridge/config.json').read_text())['node']
 initial=subprocess.run([node,str(system/'bridge/engine_worker.js')],input=json.dumps({'op':'initial','model':model})+'\n',text=True,capture_output=True,check=True)
 reply=json.loads(initial.stdout)
 if 'error' in reply:raise ValueError(reply['error'])
 session=reply['ok'];requests=[]
 labels=[]
 for locale in (['en','zh-Hans'] if model.get('localization') else ['en']):
  for pid in model['pages']:
   s={**session,'stack':[{'page':pid,'params':{}}],'locale':locale,'modals':[]}
   requests.append(json.dumps({'op':'frame','model':model,'session':s}));labels.append(locale+'/'+pid)
 process=subprocess.run([node,str(system/'bridge/engine_worker.js')],input='\n'.join(requests)+'\n',text=True,capture_output=True,check=True)
 frames=[json.loads(line) for line in process.stdout.splitlines()]
 if len(frames)!=len(requests):raise ValueError('布局引擎未返回所有页面')
 for page,result in zip(labels,frames):
  if 'error' in result:raise ValueError(page+': '+result['error'])
 print('PASS · html-native/1 · %d 页 · %d 个资源 · %d 个动作'%(len(model['pages']),len(model['assets']),len(model['actions'])-1))
 print('已校验结构、资源引用和各页双语初始布局。动态数据、交互与视觉效果仍需在两端运行验证。')
except Exception as error:
 print('FAIL · '+str(error),file=sys.stderr);sys.exit(1)
