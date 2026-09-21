"""Versioned, project-local authoring kit for humans and coding agents."""
import json,shutil,uuid,re,hashlib
from pathlib import Path
from compiler import TAGS,ATTRS,NUM,ENUM,COLORS,ACTION_FIELDS,OPS
ROOT=Path(__file__).resolve().parents[1]
START='<!-- HTML_NATIVE_STUDIO:BEGIN -->';END='<!-- HTML_NATIVE_STUDIO:END -->'
GUIDES=['HTML编写规范.md','iOS工程规则映射.md','验收清单.md','UI原图复刻规则.md']
def capabilities():
 return {'protocol':'html-native/1','rulesRevision':'native-rules/2','parserRevision':'structured/1','viewport':{'width':393,'height':852},'locales':['en','zh-Hans'],'nativeNavigation':['UINavigationController','UITabBarController'],'linkPresentation':'SFSafariViewController','minimumExportIOS':'15.0','tags':TAGS,'attributes':sorted(ATTRS),'numericStyles':sorted(NUM),'enumStyles':{k:sorted(v) for k,v in ENUM.items()},'colorStyles':sorted(COLORS),'actionFields':{k:sorted(v) for k,v in ACTION_FIELDS.items()},'expressionOperators':sorted(OPS),'images':['png','jpg','jpeg','webp'],'fonts':['ttf','otf'],'limitations':['不是任意 HTML/CSS/JavaScript 转换器','UIKit 弹簧与 HTML 近似曲线需实际两端核对','HTTPS 链接支持系统 Safari；任意网络 API、支付、Keychain 和设备能力尚不在协议中']}
def target(root,relative):
 p=root/relative
 if not p.resolve().is_relative_to(root.resolve()):raise ValueError('规范安装路径越出项目：'+relative)
 return p
def install(root):
 root=Path(root).resolve()
 if not (root/'app.json').is_file():raise ValueError('请先导入有效的 HTML Native 项目')
 # Resolve every destination before writing anything; never follow out-of-project symlinks.
 names=['.studio/authoring/schemas.json','AGENTS.md','CODEX_TASK.md','.studio/authoring/HTML编写规范.md','.studio/authoring/iOS工程规则映射.md','.studio/authoring/验收清单.md','.studio/authoring/capabilities.json','.studio/authoring/validate.py','.studio/authoring/system.json','.studio/authoring/examples']
 names+=['.studio/authoring/'+name for name in GUIDES if '.studio/authoring/'+name not in names]
 paths={n:target(root,n) for n in names}
 agents=paths['AGENTS.md'];existing=agents.read_text() if agents.exists() else ''
 if (START in existing)!=(END in existing):raise ValueError('AGENTS.md 规范区标记不完整，请先修复')
 block=START+'\n'+(ROOT/'Protocol/Authoring/AGENTS.md').read_text()+END
 if START in existing:
  start=existing.index(START);end=existing.index(END,start)+len(END);updated=existing[:start]+block+existing[end:]
 else:updated=existing.rstrip()+'\n\n'+block+'\n' if existing else block+'\n'
 for key,p in paths.items():
  if key!='.studio/authoring/examples':p.parent.mkdir(parents=True,exist_ok=True)
 agents.write_text(updated)
 task=paths['CODEX_TASK.md']
 if not task.exists():task.write_text((ROOT/'Protocol/Authoring/CODEX_TASK.md').read_text())
 for guide in GUIDES:paths['.studio/authoring/'+guide].write_text((ROOT/'Protocol/Authoring'/guide).read_text())
 paths['.studio/authoring/capabilities.json'].write_text(json.dumps(capabilities(),ensure_ascii=False,indent=2))
 paths['.studio/authoring/schemas.json'].write_text((ROOT/'bridge/parser/schemas.json').read_text())
 paths['.studio/authoring/system.json'].write_text(json.dumps({'systemRoot':str(ROOT),'protocol':'html-native/1'},ensure_ascii=False,indent=2))
 paths['.studio/authoring/validate.py'].write_text((ROOT/'Protocol/Authoring/validate.py').read_text())
 examples=paths['.studio/authoring/examples']
 # Install examples once; preserve any local annotations on subsequent installs.
 examples.mkdir(parents=True,exist_ok=True)
 for example in (ROOT/'Protocol/Examples').iterdir():
  if example.is_dir() and not (examples/example.name).exists():shutil.copytree(example,examples/example.name,ignore=shutil.ignore_patterns('.studio','.git','__pycache__','.DS_Store'))
 return root

def new_project(name=None):
 project_id='app-'+uuid.uuid4().hex[:12];dest=ROOT/'Projects'/project_id
 shutil.copytree(ROOT/'Protocol/Starter',dest)
 app=json.loads((dest/'app.json').read_text());app['id']=project_id
 if name:app['name']=str(name).strip()[:100] or app['name']
 words=re.findall(r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z][a-z]|$)',app['name'])
 letters=''.join(re.findall('[A-Za-z]',app['name']))
 prefix=(''.join(word[0] for word in words) if len(words)>=2 else letters)[:3].upper()
 if len(prefix)<2:prefix=''.join(chr(65+b%26) for b in hashlib.sha256(app['name'].encode()).digest()[:3])
 app['ios']['classPrefix']=prefix
 (dest/'app.json').write_text(json.dumps(app,ensure_ascii=False,indent=2))
 for rel in ['assets/shared','assets/pages/home','assets/fonts','components']:(dest/rel).mkdir(parents=True,exist_ok=True)
 install(dest)
 (dest/'README.md').write_text('# '+app['name']+'\n\n在 HTML Native Studio 导入本目录。将 CODEX_TASK.md 的内容交给 Codex，随后补充具体产品需求。Codex 应先读 AGENTS.md 与内置规范。\n\n校验：`python3 .studio/authoring/validate.py`。保存声明文件后，工作台自动同步当前项目。\n')
 return dest

def payload(source=None):
 prompt=(ROOT/'Protocol/Authoring/CODEX_TASK.md').read_text()
 if source:prompt='项目目录：'+str(source)+'\n请只在该项目目录完成任务。\n\n'+prompt
 return {'protocol':'html-native/1','source':str(source or ''),'guide':(ROOT/'Protocol/Authoring/HTML编写规范.md').read_text()+'\n\n'+(ROOT/'Protocol/Authoring/UI原图复刻规则.md').read_text(),'prompt':prompt,'capabilities':capabilities()}
