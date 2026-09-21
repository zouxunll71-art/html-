"""Versioned, explicit migration contract. Never infer missing pages or assets."""
import copy,hashlib,json,math,re,shutil,struct,time,uuid,zlib
from pathlib import Path
from font_metadata import postscript_name
S={'type':'string'}
ID={'type':'string','pattern':r'^[A-Za-z][A-Za-z0-9_.-]*$'}
COLOR={'type':'string','pattern':r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$'}
N={'type':'number'}
POS={'type':'number','exclusiveMinimum':0}
B={'type':'boolean'}
def obj(properties,required):return {'type':'object','properties':properties,'required':required,'additionalProperties':False}
def arr(items,minimum=0):return {'type':'array','items':items,'minItems':minimum}
def enum(*values):return {'enum':list(values)}
SPAN=obj(dict(start={'type':'integer','minimum':0},end={'type':'integer','minimum':1},fontSize=POS,fontWeight=N,color=COLOR,underline=B,italic=B),['start','end'])
NODE_PROPS=dict(id=ID,name=S,type=enum('image','text','shape'),x=N,y=N,width=POS,height=POS,rotation=N,opacity={'type':'number','minimum':0,'maximum':1},hidden=B,locked=B,asset=ID,text=S,fontAsset=ID,fontFamily=enum('serif','sans','monospace','cursive'),fontSize=POS,fontWeight={'type':'number','minimum':100,'maximum':900},italic=B,lineHeight=POS,letterSpacing=N,color=COLOR,fill=COLOR,strokeColor=COLOR,strokeWidth={'type':'number','minimum':0},cornerRadius={'type':'number','minimum':0},fit=enum('fit','fill','stretch','nineSlice'),capPixels={'type':'number','minimum':0},capPoints={'type':'number','minimum':0},alignment=enum('left','center','right'),textSpans=arr(SPAN),group=ID)
NODE=obj(NODE_PROPS,['id','name','type','x','y','width','height'])
OVERRIDE=obj({k:NODE_PROPS[k] for k in ['text','asset','color','fill','hidden']},[])
INSTANCE=obj(dict(component=ID,overrides={'type':'object','additionalProperties':OVERRIDE}),['component'])
ASSET=obj(dict(id=ID,name=S,kind=enum('image','font','reference'),path=S,sha256={'type':'string','pattern':'^[a-f0-9]{64}$'},pixelWidth={'type':'integer','minimum':1},pixelHeight={'type':'integer','minimum':1}),['id','name','kind','path','sha256'])
BINDING=obj(dict(layer=ID,field=enum('text','asset'),dataPath=S),['layer','field','dataPath'])
PAGE=obj(dict(id=ID,name=S,role=enum('startup','entry','primary','detail','dialog','state'),routes=arr(S,1),width=POS,height=POS,background=COLOR,referenceAsset=ID,groups=arr(obj(dict(id=ID,name=S),['id','name'])),layers=arr({'oneOf':[NODE,INSTANCE]},1),bindings=arr(BINDING)),['id','name','role','routes','width','height','background','referenceAsset','groups','layers','bindings'])
SCHEMA={'$schema':'https://json-schema.org/draft/2020-12/schema',**obj(dict(format=enum('studio.migration'),version=enum(1),app=obj(dict(id=ID,name=S),['id','name']),coverage=obj(dict(pageInventory=arr(S,1),complete=enum(True),unresolved=arr(S)),['pageInventory','complete','unresolved']),assets=arr(ASSET),components=arr(obj(dict(id=ID,name=S,nodes=arr(NODE,1)),['id','name','nodes'])),pages=arr(PAGE,1)),['format','version','app','coverage','assets','components','pages'])}

def check(value,schema,path='$'):
 errors=[]
 if 'oneOf' in schema:
  branches=[check(value,sub,path) for sub in schema['oneOf']]
  if sum(not e for e in branches)!=1:errors.append(path+': 图层必须为普通图层或公共组件引用；'+ '; '.join(min(branches,key=len)[:4]))
  return errors
 if 'enum' in schema and not any(type(value)==type(v) and value==v for v in schema['enum']):errors.append(path+': 值不在支持范围内');return errors
 t=schema.get('type');valid={'object':isinstance(value,dict),'array':isinstance(value,list),'string':isinstance(value,str),'boolean':isinstance(value,bool),'number':type(value) in (int,float) and math.isfinite(value),'integer':type(value)==int}.get(t,True)
 if not valid:return [path+': 类型错误，应为 '+t]
 if t=='object':
  for key in schema.get('required',[]):
   if key not in value:errors.append(path+'.'+key+': 缺少必填字段')
  for key,item in value.items():
   sub=schema.get('properties',{}).get(key,schema.get('additionalProperties',True))
   if sub is False:errors.append(path+'.'+key+': 未支持的字段，不允许静默忽略')
   elif isinstance(sub,dict):errors+=check(item,sub,path+'.'+key)
 if t=='array':
  if len(value)<schema.get('minItems',0):errors.append(path+': 清单不能为空')
  for i,item in enumerate(value):errors+=check(item,schema['items'],path+f'[{i}]')
 if t=='string' and 'pattern' in schema and not re.search(schema['pattern'],value):errors.append(path+': 格式错误')
 if t in ('number','integer'):
  for op,bad in [('minimum',lambda n:value<n),('maximum',lambda n:value>n),('exclusiveMinimum',lambda n:value<=n)]:
   if op in schema and bad(schema[op]):errors.append(path+': 超出允许范围')
 return errors

def png_size(raw):
 if raw[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('必须使用 PNG')
 offset=8;payload=[];header=None;ended=False
 while offset<len(raw):
  if len(raw)-offset<12:raise ValueError('PNG 文件截断')
  length=struct.unpack('>I',raw[offset:offset+4])[0];tag=raw[offset+4:offset+8];chunk=raw[offset+8:offset+8+length]
  if offset+12+length>len(raw) or zlib.crc32(tag+chunk)!=struct.unpack('>I',raw[offset+8+length:offset+12+length])[0]:raise ValueError('PNG 校验失败')
  if tag==b'IHDR':header=struct.unpack('>IIBBBBB',chunk)
  if tag==b'IDAT':payload.append(chunk)
  offset+=length+12
  if tag==b'IEND':ended=True;break
 if not ended or header is None or not payload:raise ValueError('PNG 缺少必要数据')
 w,h,depth,color,compression,filters,interlace=header
 channels={0:1,2:3,3:1,4:2,6:4}.get(color)
 allowed={0:(1,2,4,8,16),2:(8,16),3:(1,2,4,8),4:(8,16),6:(8,16)}
 if not channels or depth not in allowed[color] or compression or filters or interlace not in (0,1) or not (0<w<=32768 and 0<h<=32768):raise ValueError('PNG 参数不受支持')
 passes=[(0,0,1,1)] if not interlace else [(0,0,8,8),(4,0,8,8),(0,4,4,8),(2,0,4,4),(0,2,2,4),(1,0,2,2),(0,1,1,2)]
 rows=[]
 for x,y,dx,dy in passes:
  pw=max(0,(w-x+dx-1)//dx);ph=max(0,(h-y+dy-1)//dy)
  if pw and ph:rows.extend([1+(pw*channels*depth+7)//8]*ph)
 expected=sum(rows)
 if expected>128*1024*1024:raise ValueError('PNG 解码超过 128 MB，请分拆资源')
 decoder=zlib.decompressobj();pixels=decoder.decompress(b''.join(payload),expected+1)
 if len(pixels)!=expected or not decoder.eof:raise ValueError('PNG 像素数据不完整')
 cursor=0
 for row in rows:
  if pixels[cursor]>4:raise ValueError('PNG 滤波数据错误')
  cursor+=row
 return w,h

def validate(folder):
 folder=Path(folder).resolve();path=folder/'migration.json'
 def duplicates(pairs):
  out={}
  for k,v in pairs:
   if k in out:raise ValueError('JSON 重复字段：'+k)
   out[k]=v
  return out
 data=json.loads(path.read_text(),object_pairs_hook=duplicates)
 errors=check(data,SCHEMA)
 if errors:raise ValueError('迁移包格式校验失败：\n'+'\n'.join(errors[:40]))
 assets={};files={};components={};routes=[];pages=[];pageids=set();shared_sizes={}
 def issue(where,message):errors.append(where+': '+message)
 for asset in data['assets']:
  aid=asset['id'];where='assets.'+aid
  if aid in assets:issue(where,'资源 ID 重复')
  assets[aid]=asset
  relative=Path(asset['path']);target=(folder/relative).resolve()
  if relative.is_absolute() or '..' in relative.parts or not target.is_relative_to(folder):issue(where,'资源路径必须在迁移包内');continue
  if not target.is_file():issue(where,'文件不存在：'+asset['path']);continue
  files[aid]=target
  if hashlib.sha256(target.read_bytes()).hexdigest()!=asset['sha256']:issue(where,'SHA256 与文件不一致')
  if asset['kind']=='font':
   if target.suffix.lower() not in ('.ttf','.otf') or not postscript_name(target):issue(where,'无法读取字体 PostScript 名称，请提供有效 TTF/OTF')
  else:
   try:
    raw=target.read_bytes()
    if target.suffix.lower()!='.png':raise ValueError('必须使用 PNG')
    w,h=png_size(raw)
    if (w,h)!=(asset.get('pixelWidth'),asset.get('pixelHeight')):raise ValueError('PNG 尺寸与清单不一致')

   except Exception as e:issue(where,str(e))
 declared={p.resolve() for p in files.values()}
 for subdir in ['assets','fonts','references']:
  for file in (folder/subdir).rglob('*'):
   if file.is_file() and file.name!='.DS_Store' and file.resolve() not in declared:issue('assets', '资源目录中有未登记的文件：'+str(file.relative_to(folder)))
 for c in data['components']:
  if c['id'] in components:issue('components.'+c['id'],'ID 重复')
  components[c['id']]=c
 def layer(node,where,group_ids):
  n=copy.deepcopy(node)
  if n.get('group') and n['group'] not in group_ids:issue(where,'组合引用不存在')
  if n['type']=='image':
   if assets.get(n.get('asset'),{}).get('kind')!='image':issue(where,'图片图层必须引用 image 资源')
  if n['type']=='text':
   if not all(k in n for k in ['text','fontSize','color']):issue(where,'文字必须提供完整 text、fontSize 和 color')
   if ('fontAsset' in n)==('fontFamily' in n):issue(where,'fontAsset 和 fontFamily 必须且只能选择一个')
   if 'fontAsset' in n and assets.get(n['fontAsset'],{}).get('kind')!='font':issue(where,'字体引用无效')
   length=len(n.get('text','').encode('utf-16-le'))//2
   for span in n.get('textSpans',[]):
    if not 0<=span['start']<span['end']<=length:issue(where,'富文本范围越界，索引按 UTF-16')
  if n['type']=='shape' and 'fill' not in n:issue(where,'形状必须明确 fill')
  return n
 # Validate even unused public components; no silent unvisited declarations.
 for c in components.values():
  seen=set()
  for node in c['nodes']:
   if node['id'] in seen:issue('components.'+c['id'],'图层 ID 重复')
   seen.add(node['id']);layer(node,'components.'+c['id']+'.'+node['id'],set())
 for page in data['pages']:
  pid=page['id'];where='pages.'+pid
  if pid in pageids:issue(where,'页面 ID 重复')
  pageids.add(pid);routes+=page['routes']
  if any(not r.strip() for r in page['routes']):issue(where,'路由标识不能为空')
  ref=assets.get(page['referenceAsset'],{})
  if ref.get('kind')!='reference':issue(where,'必须引用 reference 对照截图')
  elif abs(ref['pixelWidth']/ref['pixelHeight']-page['width']/page['height'])>0.002:issue(where,'对照截图与画布宽高比不一致')
  gids=[g['id'] for g in page['groups']]
  if len(gids)!=len(set(gids)):issue(where,'组合 ID 重复')
  expanded=[];used=set();instances=set()
  for item in page['layers']:
   if 'component' not in item:expanded.append(layer(item,where+'.'+item['id'],set(gids)));continue
   cid=item['component'];component=components.get(cid)
   if not component:issue(where,'不存在公共组件 '+cid);continue
   if cid in instances:issue(where,'同一页面不能重复引用同一公共组件')
   instances.add(cid)
   size=(page['width'],page['height'])
   if cid in shared_sizes and shared_sizes[cid]!=size:issue(where,'公共组件要求相同画布尺寸；不同尺寸请另建组件')
   shared_sizes[cid]=size
   overrides=item.get('overrides',{})
   for key in overrides:
    if key not in {n['id'] for n in component['nodes']}:issue(where,'覆盖了不存在的组件图层 '+key)
   for base in component['nodes']:
    n=copy.deepcopy(base);n.update(overrides.get(n['id'],{}));n=layer(n,where+'.'+cid+'.'+n['id'],set())
    n['id']=cid+'.'+n['id'];n['sharedKey']='contract.'+n['id'];n['groupID']=pid+'.component.'+cid;expanded.append(n)
  for n in expanded:
   nid=n['id']
   if nid in used:issue(where,'展开后图层 ID 冲突 '+nid)
   used.add(nid)
   if 'group' in n:n['groupID']=pid+'.'+n.pop('group')
  for binding in page['bindings']:
   matches=[n for n in expanded if n['id']==binding['layer']]
   if not matches or matches[0]['type']!=('text' if binding['field']=='text' else 'image'):issue(where,'数据绑定必须引用相应类型的图层')
  pages.append((page,expanded))
 inventory=data['coverage']['pageInventory']
 if len(inventory)!=len(set(inventory)) or len(routes)!=len(set(routes)):issue('coverage','页面清单或模板 routes 重复')
 if set(inventory)!=set(routes):issue('coverage','pageInventory 与所有模板 routes 必须完全对应')
 if data['coverage']['unresolved']:issue('coverage','仍有未整理事项：'+'；'.join(data['coverage']['unresolved']))
 if errors:raise ValueError('迁移包内容校验失败（未导入）：\n'+'\n'.join(errors[:40]))
 return data,assets,files,pages

def import_package(folder,store,name=None):
 folder=Path(folder).resolve();data,assets,files,pages=validate(folder)
 digest=hashlib.sha256((folder/'migration.json').read_bytes()).hexdigest()
 for path in Path(store).glob('*/project.json'):
  old=json.loads(path.read_text())
  if old.get('importMode')=='manifest' and old.get('sourcePath')==str(folder) and old.get('manifestDigest')==digest:return old
 pid=str(uuid.uuid4());stage=Path(store)/('.migration-'+pid);dest=Path(store)/pid
 try:
  (stage/'assets').mkdir(parents=True);converted=[];mapping={}
  for aid,asset in assets.items():
   file=asset['sha256'][:16]+files[aid].suffix.lower();mapping[aid]=file
   shutil.copy2(files[aid],stage/'assets'/file)
   if not any(a['id']==file for a in converted):converted.append(dict(id=file,file=file,name=asset['name'],kind='font' if asset['kind']=='font' else 'image',source=asset['path'],sha256=asset['sha256']))
  output=[];references={};roles={}
  for page,nodes in pages:
   for n in nodes:
    n['id']=page['id']+'.'+n['id']
    if n.get('asset'):n['asset']=mapping[n['asset']]
    if n.get('fontAsset'):n['fontName']=postscript_name(files[n.pop('fontAsset')])
   output.append(dict(id=page['id'],name=page['name'],route=page['routes'][0],templateRoutes=page['routes'],width=page['width'],height=page['height'],background=page['background'],nodes=nodes,paintOrderVersion=1))
   references[page['id']]=mapping[page['referenceAsset']];roles[page['id']]=page['role']
  project=dict(schemaVersion=1,id=pid,name=(name or '').strip() or data['app']['name'],sourcePath=str(folder),package='',assets=converted,pages=output,pageCandidates=[],updated=time.time(),importMode='manifest',manifestDigest=digest,referenceAssets=references,pageRoles=roles)
  (stage/'project.json').write_text(json.dumps(project,ensure_ascii=False,indent=2))
  (stage/'manifest-layout.json').write_text(json.dumps(project,ensure_ascii=False,indent=2))
  shutil.copy2(folder/'migration.json',stage/'migration.json')
  (stage/'migration-validation.json').write_text(json.dumps(dict(valid=True,templates=len(output),routes=len(data['coverage']['pageInventory']),assets=len(assets),layers=sum(len(p['nodes']) for p in output),notice='校验清单和文件一致性，不代表已自动核对所有视觉差异'),ensure_ascii=False,indent=2))
  stage.rename(dest)
  return project
 except Exception:
  shutil.rmtree(stage,ignore_errors=True);raise

if __name__=='__main__':
 import sys
 try:
  data,assets,files,pages=validate(sys.argv[1]);print(f"校验通过：{len(pages)} 个页面模板，{len(data['coverage']['pageInventory'])} 个页面/状态，{len(assets)} 个资源")
 except Exception as error:print(str(error),file=sys.stderr);sys.exit(1)
