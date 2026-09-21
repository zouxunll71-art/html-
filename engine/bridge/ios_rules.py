"""Project-independent iOS contract validation. No business-page inference."""
import re
from urllib.parse import urlparse
LOCALES=('en','zh-Hans')
PERMISSIONS=('NSCameraUsageDescription','NSPhotoLibraryUsageDescription','NSMicrophoneUsageDescription','NSUserTrackingUsageDescription')
KEY=re.compile(r'[A-Za-z][A-Za-z0-9_.-]*\Z')
def require(ok,message):
 if not ok:raise ValueError('iOS rules: '+message)
def read_configuration(app,root,load,safe):
 spec=app.get('localization');localization=None
 if spec is not None:
  require(isinstance(spec,dict) and set(spec)=={'default','files'},'localization requires default and files')
  require(spec['default']=='en','default language must be en')
  require(isinstance(spec['files'],dict) and set(spec['files'])==set(LOCALES),'declare en and zh-Hans files')
  tables={lang:load(safe(root,path)) for lang,path in spec['files'].items()}
  for lang,table in tables.items():
   require(isinstance(table,dict) and all(isinstance(k,str) and KEY.fullmatch(k) and isinstance(v,str) and v.strip() for k,v in table.items()),lang+' must be a flat, nonempty-string key table')
   for key,value in table.items():
    require(not re.search(r'\bgame\b|游戏',value,re.I),'prohibited wording: '+key)
    if lang=='en':require(not re.search(r'[\u3400-\u9fff]',value),'English translation required: '+key)
  require(set(tables['en'])==set(tables['zh-Hans']),'en and zh-Hans keys differ')
  for key in tables['en']:
   placeholders=lambda value:set(re.findall(r'\{([A-Za-z][A-Za-z0-9_]*)\}',value))
   require(placeholders(tables['en'][key])==placeholders(tables['zh-Hans'][key]),'translation placeholders differ: '+key)
  localization={'default':'en','tables':tables}
 ios=app.get('ios')
 if ios is not None:
  require(isinstance(ios,dict) and not set(ios)-{'classPrefix','permissionKeys','currencySymbol'},'unsupported ios configuration')
  require(isinstance(ios.get('classPrefix'),str) and re.fullmatch('[A-Za-z]{2,3}',ios.get('classPrefix','')) is not None,'classPrefix must contain 2-3 ASCII letters')
  require(localization is not None,'declare both localization files')
  require(app.get('viewport',{}).get('width')==393,'new iOS contracts use a 393 pt design width')
  require(isinstance(app.get('navigation'),dict),'declare native navigation, even when tabs is empty')
  require(isinstance(ios.get('permissionKeys'),dict) and set(ios.get('permissionKeys',{}))==set(PERMISSIONS),'declare four permission localization keys')
  for key in ios['permissionKeys'].values():check_key(localization,key,'permission')
  if 'currencySymbol' in ios:require(isinstance(ios['currencySymbol'],str) and re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*',ios['currencySymbol']),'invalid currencySymbol')
 links=app.get('links',{})
 require(isinstance(links,dict),'links must be an object')
 for key,url in links.items():
  require(isinstance(key,str) and KEY.fullmatch(key) and isinstance(url,str),'invalid link declaration')
  parsed=urlparse(url);require(parsed.scheme=='https' and bool(parsed.hostname) and not parsed.username and not parsed.password,'links must be HTTPS URLs without credentials: '+key)
 return localization,ios,links

def check_key(localization,key,where):
 require(localization is not None and isinstance(key,str) and key in localization['tables']['en'],'unknown localization key at '+where+': '+str(key))

def verify_node(node,localization,ios,where):
 strict=ios is not None
 for attr in ('text-key','placeholder-key'):
  if attr in node:check_key(localization,node[attr],where)
 if 'option-keys' in node:require(isinstance(node['option-keys'],list) and bool(node['option-keys']),where+': option-keys must be a nonempty array')
 for key in node.get('option-keys',[]):check_key(localization,key,where)
 require(not ('text-key' in node and (node.get('text') or 'content' in node)),where+': text-key cannot be mixed with inline content')
 require(not ('placeholder-key' in node and node.get('placeholder')),where+': duplicate placeholder source')
 if 'text-args' in node:require(isinstance(node['text-args'],dict),where+': text-args must be an object')
 if 'symbol' in node:require(node['type']=='image' and not node.get('asset'),where+': symbol requires an icon without an asset')
 if 'semantic' in node:
  require(node['semantic']=='currency' and node['type']=='image',where+': semantic currency requires an image icon')
  require(ios and node.get('symbol')==ios.get('currencySymbol','c.circle'),where+': use the shared currency SF Symbol')
 if strict:
  require(not node.get('placeholder') and not node.get('options'),where+': use placeholder-key and option-keys')
  if node.get('text'):require(re.fullmatch(r'\{\{(?:state|params|item)\.[\w.]+\}\}',node['text']) is not None,where+': static UI copy requires text-key')
  if 'content' in node:require(isinstance(node['content'],dict) and ('get' in node['content'] or 't' in node['content']),where+': content must reference data or a localization key')
  if node['type']=='nativeButton':require(bool(node.get('action')),where+': button action is missing')
  if node['type'] in ('nativeCheckbox','nativeSwitch','nativeTextField','nativeTextView','nativeSlider','nativeSegment','nativeStepper'):require(bool(node.get('action') or node.get('bind')),where+': interactive control requires bind or action')
 if node.get('symbol'):require(re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*',node['symbol']) is not None,where+': invalid SF Symbol name')

def verify_navigation(nav,pages,localization,actions):
 if nav is None:return
 require(isinstance(nav,dict) and not set(nav)-{'tabs','tint','background'},'unsupported navigation configuration')
 for color in ('tint','background'):
  if color in nav:require(isinstance(nav[color],str) and re.fullmatch(r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?',nav[color]),'invalid navigation '+color)
 tabs=nav.get('tabs',[]);require(isinstance(tabs,list) and len(tabs)<=5,'native tabs require 0-5 items')
 ids=set()
 for tab in tabs:
  require(isinstance(tab,dict) and set(tab)=={'page','titleKey','symbol'},'tab requires page, titleKey, symbol')
  require(tab['page'] in pages and pages[tab['page']].get('role')!='dialog' and tab['page'] not in ids,'tab route missing, duplicated or a dialog');ids.add(tab['page'])
  check_key(localization,tab['titleKey'],'tab');require(isinstance(tab['symbol'],str) and re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*',tab['symbol']),'tab SF Symbol is required')
 for pid,page in pages.items():
  item=page.get('navigation',{})
  require(isinstance(item,dict) and not set(item)-{'titleKey','hidden','backTitleKey','buttons'},'unsupported page navigation: '+pid)
  for key in ('titleKey','backTitleKey'):
   if key in item:check_key(localization,item[key],pid)
  if not item.get('hidden') and page.get('role')!='dialog':check_key(localization,item.get('titleKey'),pid)
  require(type(item.get('hidden',False)) is bool,'navigation.hidden must be boolean')
  require(isinstance(item.get('buttons',[]),list),'navigation.buttons must be an array')
  seen=set()
  for button in item.get('buttons',[]):
   require(isinstance(button,dict) and not set(button)-{'id','titleKey','symbol','action','side'} and {'id','titleKey','action'}<=set(button),'invalid navigation button: '+pid)
   require(isinstance(button['id'],str) and KEY.fullmatch(button['id']) and button['id'] not in seen,'duplicate navigation button ID');seen.add(button['id'])
   check_key(localization,button['titleKey'],pid);require(button['action'] in actions and bool(actions[button['action']]),'navigation button action missing: '+pid)
   if 'symbol' in button:require(isinstance(button['symbol'],str) and re.fullmatch(r'[a-z0-9]+(?:[.-][a-z0-9]+)*',button['symbol']),'invalid navigation SF Symbol')
   require(button.get('side','right') in ('left','right'),'invalid button side')

def export_issues(record):
 model=record['model'];issues=[]
 if not model.get('ios'):issues.append('项目尚未采用 iOS 工程规则：请补齐本地化、原生导航和权限说明后导出。')
 for item in record.get('overrides',{}).values():
  if any(k in item.get('patch',{}) for k in ('text','placeholder','options','action')):issues.append('iOS 覆盖包含未本地化文案或独立动作，请回写 HTML 的 key / actions 后导出。');break
 for page,nodes in record.get('additions',{}).items():
  for n in nodes:
   if n.get('origin') and n['origin'].get('page') not in model['pages']:issues.append('复制图层的源页面已删除：'+page+'/'+n['id'])
   action=n.get('interaction',{}).get('action') or n.get('action')
   if action and action not in model['actions']:issues.append('新增图层引用了不存在的动作：'+page+'/'+n['id'])
   if n.get('manualContent') or (not n.get('origin') and (n.get('text') or n.get('placeholder') or n.get('options'))):issues.append('新增图层需要在 HTML 中登记本地化 key：'+page+'/'+n['id'])
   if n.get('type') in ('nativeButton','nativeCheckbox','nativeSwitch','nativeTextField','nativeTextView','nativeSlider','nativeSegment','nativeStepper') and not n.get('action') and not n.get('bind') and not n.get('interaction',{}).get('bind'):issues.append('新增控件需要在 HTML 中登记点击/绑定逻辑：'+page+'/'+n['id'])
 return issues
