"""HTML Native contract compiler. Unrecognized input is an error, never a guess."""
import json,re,hashlib,copy
from functools import lru_cache
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from html.parser import HTMLParser
from font_metadata import postscript_name
import ios_rules
import structured_parser
TAGS={'ui-page':'container','ui-column':'container','ui-row':'container','ui-stack':'container','ui-grid':'container','ui-scroll':'scroll','ui-text':'text','ui-image':'image','ui-icon':'image','ui-button':'nativeButton','ui-input':'nativeTextField','ui-textarea':'nativeTextView','ui-switch':'nativeSwitch','ui-checkbox':'nativeCheckbox','ui-slider':'nativeSlider','ui-progress':'nativeProgress','ui-spinner':'nativeSpinner','ui-segment':'nativeSegment','ui-stepper':'nativeStepper','ui-use':'use'}
ATTRS={'id','name','class','style','asset','font','action','bind','when','repeat','key','group','component','placeholder','disabled','min','max','input-type','spans','options','step','styles','gradient','shadow','content','text-key','placeholder-key','option-keys','text-args','symbol','selected','semantic'}
NUM={'width','height','left','top','right','bottom','gap','padding','font-size','font-weight','line-height','letter-spacing','border-radius','border-width','opacity','rotation','scale','columns','row-height','flex-grow'}
ENUM={'display':{'flex','stack','grid'},'flex-direction':{'row','column'},'align-items':{'start','center','end','stretch'},'align-self':{'start','center','end','stretch'},'position':{'absolute','relative'},'overflow':{'hidden','visible'},'object-fit':{'fit','fill','stretch'},'text-align':{'left','center','right'},'font-family':{'sans','serif','monospace','cursive'}}
COLORS={'color','background','border-color'}
ACTION_FIELDS={'set':{'path','value'},'toggle':{'path'},'append':{'path','value'},'remove':{'path','key','value'},'update':{'path','key','id','value'},'if':{'when','then','else'},'push':{'page','params'},'replace':{'page','params'},'tab':{'page','params'},'back':set(),'present':{'page'},'dismiss':set(),'openURL':{'link'},'delay':{'duration','actions'},'persist':{'key','value'},'restore':{'path','key','default'},'reset':set(),'animate':{'duration','delay','curve','actions'}}
OPS={'eq','not','and','or','add','sub','gt','gte','lt','concat','length','if','trim','split','join','contains','map','filter','find','sum'}
OPS.update({'mul','div','round','number','min','max','abs','sqrt','atan2','format'})
ACTION_FIELDS.update({'generateID':{'path'},'forget':{'key'},'share':{'filename','content','mime'}})
TAGS.update({'ui-path':'path','ui-model':'model'})
ATTRS.update({'points','profile','angle','elevation','closed'})
ATTRS.add('placement')
OPS.add('revolveOBJ')
def fail(file,message,line=1):raise ValueError(f'{file}:{line}: {message}')
def load(path):
 def pairs(items):
  d={}
  for k,v in items:
   if k in d:fail(path,'重复字段 '+k)
   d[k]=v
  return d
 return json.loads(path.read_text(),object_pairs_hook=pairs,parse_constant=lambda v:fail(path,'无效数值 '+v))
def safe(root,p):
 f=(root/p).resolve()
 if not f.is_relative_to(root.resolve()) or not f.is_file():fail(p,'文件不存在或路径超出项目')
 return f

@lru_cache(maxsize=16384)
def asset_metadata(path,kind,stamp):
 f=Path(path);digest=hashlib.sha256()
 with f.open('rb') as stream:
  for block in iter(lambda:stream.read(1024*1024),b''):digest.update(block)
 digest=digest.hexdigest();name=digest[:16]+f.suffix.lower()
 result=dict(id=name,kind=kind,file=name,sha256=digest)
 if kind=='font':
  result['postscript']=postscript_name(f)
  if not result['postscript']:fail(f,'字体不可读')
 else:
  import subprocess
  check=subprocess.run(['/usr/bin/sips','-g','pixelWidth','-g','pixelHeight',str(f)],capture_output=True,text=True)
  if check.returncode or 'pixelWidth: ' not in check.stdout or '<nil>' in check.stdout:fail(f,'图片不可解码')
 st=f.stat()
 if stamp!=(st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns,st.st_ctime_ns):fail(f,'资源正在修改，请保存后重试')
 return result

def css(text,where,tokens):
 try:declarations=structured_parser.request('declarations',text=text)
 except ValueError as error:fail(where,str(error))
 return css_declarations(declarations,where,tokens)
def css_declarations(declarations,where,tokens):
 out={}
 for declaration in declarations:
  k,v=declaration['property'],declaration['value']
  if v.startswith('var('):
   key=v[4:-1].strip();v=str(tokens.get(key,''))
   if not v:fail(where,'未知 token '+key)
  if k in NUM:
   if v in ('fill','auto') and k in ('width','height'):out[k]=v;continue
   if not re.fullmatch(r'-?\d+(?:\.\d+)?(?:px|deg)?',v):fail(where,'只接受逻辑 px 数值：'+k)
   n=float(re.sub(r'px|deg','',v));out[k]=n
   if k in ('width','height','font-size','line-height','columns','row-height','scale') and n<=0:fail(where,k+' 必须大于 0')
   if k=='opacity' and not 0<=n<=1:fail(where,'opacity 必须为 0–1')
   if k=='columns' and int(n)!=n:fail(where,'columns 必须是整数')
  elif k in ENUM:
   if v not in ENUM[k]:fail(where,'未支持的 '+k+': '+v)
   out[k]=v
  elif k in COLORS:
   if v=='transparent':v='#00000000'
   if not re.fullmatch(r'#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?',v):fail(where,'颜色必须为 #RRGGBB 或 #RRGGBBAA')
   out[k]=v
  else:fail(where,'未支持的 CSS 属性 '+k)
 return out
class Parser(HTMLParser):
 def __init__(self,path,classes,tokens):super().__init__(convert_charrefs=True);self.path=str(path);self.classes=classes;self.tokens=tokens;self.stack=[];self.root=None;self.ids=set();self.tags=[]
 def feed(self,data):
  try:tokens=structured_parser.request('html',text=data)
  except ValueError as error:fail(self.path,str(error))
  for token in tokens:
   self._position=(token['line'],token['column']-1)
   if token['kind']=='start':
    if token.get('selfClosing'):self.handle_startendtag(token['tag'],token['attrs'])
    else:self.handle_starttag(token['tag'],token['attrs'])
   elif token['kind']=='end':self.handle_endtag(token['tag'])
   else:self.handle_data(token['text'])
 def getpos(self):return getattr(self,'_position',(1,0))
 def handle_starttag(self,tag,attrs):
  line=self.getpos()[0]
  if self.stack and self.stack[-1]['type'] not in ('container','scroll'):fail(self.path,'此元素不能包含子图层，请改用 ui-stack、ui-row 或 ui-column 组合',line)
  if tag not in TAGS:fail(self.path,'不支持标签 '+tag,line)
  if len(dict(attrs))!=len(attrs):fail(self.path,'重复属性',line)
  a=dict(attrs)
  if set(a)-ATTRS:fail(self.path,'不支持属性 '+','.join(set(a)-ATTRS),line)
  if 'placement' in a:
   if a['placement']!='viewport-background' or tag!='ui-image' or len(self.stack)!=1 or self.tags[0]!='ui-page':fail(self.path,'placement="viewport-background" 仅用于 ui-page 的直接 ui-image 子层',line)
   if any(k in a for k in ('action','bind','repeat','when','symbol')):fail(self.path,'全屏背景必须是独立且始终可见的图片层',line)
   if not a.get('asset'):fail(self.path,'全屏背景必须声明图片 asset',line)
  id=a.get('id','')
  if not re.fullmatch(r'[A-Za-z][\w.-]*',id) or id in self.ids:fail(self.path,'图层 ID 缺失、无效或重复 '+id,line)
  self.ids.add(id);st={}
  for c in a.get('class','').split():
   if c not in self.classes:fail(self.path,'未定义 class '+c,line)
   st.update(self.classes[c])
  st.update(css(a.get('style',''),self.path,self.tokens))
  if tag=='ui-row':st['flex-direction']='row'
  if tag=='ui-stack':st['display']='stack'
  if tag=='ui-grid':st['display']='grid'
  n=dict(id=id,type=TAGS[tag],style=st,children=[],text='',source={'file':self.path,'line':line})
  for k in ['name','asset','font','action','bind','key','group','component','placeholder','text-key','placeholder-key','symbol','semantic','placement']: 
   if k in a:n[k]=a[k]
  for k in ['when','repeat','disabled','spans','options','styles','gradient','shadow','content','option-keys','text-args','selected','points','profile','angle','elevation','closed']:
   if k in a:
    try:n[k]=json.loads(a[k])
    except Exception:fail(self.path,k+' 必须为 JSON 表达式',line)
  for k in ['min','max','step']:
   if k in a:n[k]=float(a[k])
  if 'input-type' in a:n['inputType']=a['input-type']
  if self.stack:self.stack[-1]['children'].append(n)
  elif self.root is not None:fail(self.path,'只能有一个根节点',line)
  else:self.root=n
  self.stack.append(n);self.tags.append(tag)
 def handle_endtag(self,tag):
  if not self.stack or self.tags[-1]!=tag:fail(self.path,'不匹配的结束标签 '+tag,self.getpos()[0])
  self.stack.pop();self.tags.pop()
 def handle_startendtag(self,tag,attrs):self.handle_starttag(tag,attrs);self.handle_endtag(tag)
 def handle_data(self,data):
  if self.stack:
   if data.strip() and self.stack[-1]['type'] not in ('text','nativeButton','nativeCheckbox'):fail(self.path,'此容器不能直接包含文案，请用 ui-text',self.getpos()[0])
   self.stack[-1]['text']+=data
  elif data.strip():fail(self.path,'根节点外有文本')
 def result(self):
  if self.stack or self.root is None:fail(self.path,'HTML 未闭合或为空')
  def clean(n):
   n['text']=n['text'].strip()
   for c in n['children']:clean(c)
  clean(self.root);return self.root

def compile_project(root):
 root=Path(root).resolve();app=load(safe(root,'app.json'))
 structured_parser.validate('app',app,root/'app.json')
 if app.get('protocol')!='html-native/1':fail('app.json','协议必须为 html-native/1')
 allowed={'protocol','id','name','entry','viewport','state','stateVersion','pages','components','actions','tokens','localization','ios','navigation','links'}
 if set(app)-allowed:fail('app.json','未支持字段 '+str(set(app)-allowed))
 v=app.get('viewport',{'width':402,'height':874})
 if set(v)!={'width','height'} or not all(type(x) in (int,float) and 240<=x<=2048 for x in v.values()):fail('app.json','无效画布')
 if not isinstance(app.get('state',{}),dict):fail('app.json','state 必须为对象')
 localization,ios,links=ios_rules.read_configuration(app,root,load,safe)
 tokens=load(safe(root,app['tokens'])) if app.get('tokens') else {}
 catalog=load(safe(root,'assets/catalog.json'));assets=[];seen=set();declared=set();jobs=[]
 structured_parser.validate('catalog',catalog,root/'assets/catalog.json')
 for a in catalog:
  if set(a)-{'id','path','kind'} or not all(k in a for k in ['id','path','kind']):fail('assets/catalog.json','资源只接受 id/path/kind')
  if a['id'] in seen:fail('assets/catalog.json','重复资源 ID '+a['id'])
  seen.add(a['id']);f=safe(root,a['path']);declared.add(f);kind=a['kind']
  if kind not in ('image','font') or f.suffix.lower() not in (('.png','.jpg','.jpeg','.webp') if kind=='image' else ('.ttf','.otf')):fail(f,'不支持的资源类型')
  st=f.stat();stamp=(st.st_dev,st.st_ino,st.st_size,st.st_mtime_ns,st.st_ctime_ns)
  jobs.append((a,f,kind,stamp))
 def inspect(job):
  a,f,kind,stamp=job;metadata=asset_metadata(str(f),kind,stamp)
  return dict(metadata,name=a['id'],source=a['path'])
 # Bound cold validation concurrency; unchanged files reuse verified metadata.
 with ThreadPoolExecutor(max_workers=4) as pool:assets=list(pool.map(inspect,jobs))
 for folder in (['assets'] if ios is not None else ['assets/shared','assets/pages','assets/fonts']):
  for f in (root/folder).rglob('*'):
   if f.is_file() and f.name!='.DS_Store' and f.resolve()!=(root/'assets/catalog.json').resolve() and f.resolve() not in declared:fail(f,'资源未登记在 catalog.json')
 def template(entry):
  classes={}
  if entry.get('css'):
   file=safe(root,entry['css'])
   try:rules=structured_parser.request('stylesheet',text=file.read_text())
   except ValueError as error:fail(file,str(error))
   for rule in rules:
    name=rule['name']
    if name in classes:fail(file,'重复 class '+name,rule['line'])
    classes[name]=css_declarations(rule['declarations'],str(file),tokens)
  path=safe(root,entry['html']);p=Parser(path,classes,tokens);p.feed(path.read_text());return p.result()
 if ios is not None:
  declared_templates={safe(root,entry[field]) for entry in list(app.get('pages',[]))+list(app.get('components',{}).values()) for field in ('html','css') if entry.get(field)}
  for folder in ('pages','components'):
   for file in (root/folder).rglob('*'):
    if file.is_file() and file.suffix.lower() in ('.html','.htm','.css','.js') and file.resolve() not in declared_templates:fail(file,'Source file is not declared by a page or component')
 components={k:template(v) for k,v in app.get('components',{}).items()};pages={};actions={'$dismiss':[{'type':'dismiss'}]}
 for file in app.get('actions',[]):
  declared_actions=load(safe(root,file));structured_parser.validate('actions',declared_actions,file)
  for key,val in declared_actions.items():
   if key in actions:fail(file,'重复动作 '+key)
   actions[key]=val
 def expand(n,chain=()):
  if n['type']=='use':
   instance_fields={'name','group','when','repeat','key','action','disabled','selected','styles'}
   unsupported=set(n)-{'id','type','style','children','text','source','component'}-instance_fields
   if unsupported:fail(n['source']['file'],'ui-use 不支持实例属性 '+', '.join(sorted(unsupported)),n['source']['line'])
   cid=n.get('component')
   if cid not in components or cid in chain:fail(n['source']['file'],'组件不存在或循环引用 '+str(cid))
   base=expand(copy.deepcopy(components[cid]),chain+(cid,));base['id']=n['id'];base['style'].update(n['style'])
   for key in instance_fields:
    if key in n:
     if key=='styles' and isinstance(base.get(key,{}),dict) and isinstance(n[key],dict):base[key]={**base.get(key,{}),**copy.deepcopy(n[key])}
     else:base[key]=copy.deepcopy(n[key])
   def shared(c,path):
    c['shared']='component.'+cid+'.'+path
    for child in c['children']:shared(child,path+'.'+child['id'])
   shared(base,'root');return base
  n['children']=[expand(c,chain) for c in n['children']];return n
 def expression(x):
  if isinstance(x,dict):
   if 'get' in x:
    if set(x)!={'get'} or not re.fullmatch(r'(state|params|item|event|storage|index)(\.[A-Za-z0-9_-]+)*',str(x['get'])):fail('expression','无效 get 路径')
   elif 't' in x:
    if 'args' in x and not isinstance(x['args'],dict):fail('expression','Translation args must be an object')
    if set(x)-{'t','args'}:fail('expression','Unsupported translation expression')
    ios_rules.check_key(localization,x['t'],'expression')
   elif 'op' in x:
    if x['op'] not in OPS or set(x)-{'op','args'}:fail('expression','不支持运算符')
   for value in x.values():expression(value)
  elif isinstance(x,list):
   for value in x:expression(value)
 def verify_node(n):
  ios_rules.verify_node(n,localization,ios,n['source']['file']+':'+str(n['source']['line']))
  for k in ('asset','font'):
   if k in n and '{{' not in n[k] and n[k] not in seen:fail(n['source']['file'],'未知资源 '+n[k],n['source']['line'])
  if 'styles' in n:
   if not isinstance(n['styles'],dict) or set(n['styles'])-NUM-COLORS-set(ENUM):fail(n['source']['file'],'styles 包含未支持样式')
   expression(n['styles'])
  if 'options' in n and (not isinstance(n['options'],list) or not n['options'] or not all(isinstance(x,str) for x in n['options'])):fail(n['source']['file'],'options 必须为非空字符串数组')
  if 'spans' in n:
   if not isinstance(n['spans'],list):fail(n['source']['file'],'spans 必须为数组')
   for span in n['spans']:
    if not isinstance(span,dict) or set(span)-{'start','end','fontSize','fontWeight','color','underline','italic'} or type(span.get('start'))!=int or type(span.get('end'))!=int or not 0<=span['start']<span['end']:fail(n['source']['file'],'富文本范围必须为有效 UTF-16 start/end')
    for field in ('fontSize','fontWeight'):
     if field in span and (type(span[field]) not in (int,float) or span[field]<=0):fail(n['source']['file'],'富文本字号与字重必须为正数')
    if 'color' in span:css('color:'+str(span['color']),n['source']['file'],{})
  if 'gradient' in n:
   g=n['gradient']
   if not isinstance(g,dict) or set(g)-{'colors','locations','start','end'} or not isinstance(g.get('colors'),list) or len(g['colors'])<2:fail(n['source']['file'],'gradient 需要至少两种颜色')
   for color in g['colors']:css('color:'+str(color),n['source']['file'],{})
   for key in ('start','end'):
    if key in g and (not isinstance(g[key],list) or len(g[key])!=2 or not all(type(x) in (int,float) and 0<=x<=1 for x in g[key])):fail(n['source']['file'],'gradient 起止点需为 0–1 坐标')
   if 'locations' in g and (len(g['locations'])!=len(g['colors']) or not all(type(x) in (int,float) and 0<=x<=1 for x in g['locations']) or g['locations']!=sorted(g['locations'])):fail(n['source']['file'],'gradient locations 无效')
  if 'shadow' in n:
   shadow=n['shadow']
   if not isinstance(shadow,dict) or set(shadow)-{'color','x','y','blur'}:fail(n['source']['file'],'shadow 字段无效')
   css('color:'+str(shadow.get('color','#00000033')),n['source']['file'],{})
   if not all(type(shadow.get(k,0)) in (int,float) for k in ('x','y','blur')) or shadow.get('blur',0)<0:fail(n['source']['file'],'shadow 数值无效')
  if n.get('inputType','text') not in ('text','number','password'):fail(n['source']['file'],'input-type 不支持')
  if n.get('step',1)<=0 or n.get('min',0)>=n.get('max',1):fail(n['source']['file'],'控件范围或 step 无效')
  if n.get('action') and n['action'] not in actions:fail(n['source']['file'],'未知动作 '+n['action'],n['source']['line'])
  if ios is not None and n.get('action') and not actions[n['action']]:fail(n['source']['file'],'Action has no steps: '+n['action'],n['source']['line'])
  if ios is not None and 'bind' in n:
   binding=n['bind']
   if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*(?:\.[A-Za-z0-9_-]+)*',binding) or any(k in ('__proto__','prototype','constructor') for k in binding.split('.')):fail(n['source']['file'],'Invalid state binding: '+binding,n['source']['line'])
   value=app.get('state',{})
   for part in binding.split('.'):
    if not isinstance(value,dict) or part not in value:fail(n['source']['file'],'Binding is missing from initial state: '+binding,n['source']['line'])
    value=value[part]
   expected={'nativeCheckbox':bool,'nativeSwitch':bool,'nativeTextField':str,'nativeTextView':str,'nativeSlider':(int,float),'nativeStepper':(int,float),'nativeProgress':(int,float),'nativeSegment':int}
   kind=expected.get(n['type'])
   if kind is None or (type(value) not in kind if isinstance(kind,tuple) else type(value) is not kind):fail(n['source']['file'],'Control binding has the wrong type: '+binding,n['source']['line'])

  if n.get('repeat') and not n.get('key'):fail(n['source']['file'],'repeat 必须有 key')
  if n['type']=='image' and not n.get('asset') and not n.get('symbol'):fail(n['source']['file'],'图片缺少 asset')
  if n['type']=='text' and not n.get('text') and 'content' not in n and 'text-key' not in n:fail(n['source']['file'],'文案为空')
  for k in ['when','repeat','disabled','spans','options','styles','gradient','shadow','content','option-keys','text-args','selected','points','profile','angle','elevation','closed']:expression(n.get(k))
  if n['type']=='path' and 'points' not in n:fail(n['source']['file'],'ui-path requires normalized points')
  if n['type']=='model' and 'profile' not in n:fail(n['source']['file'],'ui-model requires a radius/height profile')
  for child in n['children']:verify_node(child)
 for p in app.get('pages',[]):
  if set(p)-{'id','name','role','html','css','dismissOnBackdrop','navigation','onEnter'}:fail('app.json','页面声明存在未知字段')
  if p.get('onEnter') and p['onEnter'] not in actions:fail('app.json','Unknown onEnter action '+p['onEnter'])
  if p['id'] in pages:fail('app.json','页面 ID 重复')
  n=expand(template(p));verify_node(n);pages[p['id']]={**p,'root':n}
 if not pages or app.get('entry') not in pages:fail('app.json','缺少有效入口页')
 def check_actions(seq,depth=0):
  if not isinstance(seq,list) or depth>12:fail('actions','动作必须为有限数组')
  for a in seq:
   if not isinstance(a,dict):fail('actions','每一步必须为对象')
   if a.get('type') not in ACTION_FIELDS or set(a)-ACTION_FIELDS[a['type']]-{'type'}:fail('actions','不支持的动作或参数 '+str(a))
   required={'delay':{'duration','actions'},'openURL':{'link'},'set':{'path','value'},'toggle':{'path'},'append':{'path','value'},'remove':{'path','key','value'},'update':{'path','key','id','value'},'if':{'when','then'},'push':{'page'},'replace':{'page'},'tab':{'page'},'present':{'page'},'persist':{'key','value'},'restore':{'path','key','default'},'animate':{'duration','actions'}}
   if required.get(a['type'],set())-set(a):fail('actions','动作缺少必需字段 '+a['type'])
   if a['type']=='present' and pages.get(a.get('page'),{}).get('role')!='dialog':fail('actions','present 必须引用 dialog 页面')
   if a['type'] in ('push','replace','tab') and pages.get(a.get('page'),{}).get('role')=='dialog':fail('actions','普通路由不能引用 dialog 页面')
   if 'page'in a and a['page'] not in pages:fail('actions','不存在页面 '+a['page'])
   if 'path'in a and (not isinstance(a['path'],str) or any(k in a['path'].split('.') for k in ('__proto__','prototype','constructor'))):fail('actions','非法状态路径')
   if a['type']=='animate' and (not 0<=a.get('duration',0)<=10 or a.get('curve','ease') not in ['linear','ease','spring']):fail('actions','动画时长 0–10 秒；curve 为 linear/ease/spring')
   if a['type']=='delay' and (type(a.get('duration')) not in (int,float) or not 0<a['duration']<=60):fail('actions','delay duration must be 0-60 seconds')
   if a['type']=='openURL' and a.get('link') not in links:fail('actions','Unknown link '+str(a.get('link')))
   expression(a)
   for key in ('then','else','actions'):
    if key in a:check_actions(a[key],depth+1)
 for seq in actions.values():check_actions(seq)
 ios_rules.verify_navigation(app.get('navigation'),pages,localization,actions)
 for c in components.values():verify_node(expand(copy.deepcopy(c)))
 model=dict(protocol=app['protocol'],id=app['id'],name=app['name'],entry=app['entry'],viewport=v,state=app.get('state',{}),stateVersion=app.get('stateVersion',1),pages=pages,actions=actions,assets=assets,localization=localization,ios=ios,navigation=app.get('navigation'),links=links)
 model['hash']=hashlib.sha256(json.dumps(model,sort_keys=True).encode()).hexdigest();return model
