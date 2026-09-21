"""Project-independent source layer lookup and lossless visual copying."""
import copy,hashlib,json,math,uuid

def signature(page):
 return hashlib.sha256(json.dumps({k:v for k,v in page.items() if k not in ('effects','chromeHitTargets','browserOpen','closeBrowser')},sort_keys=True,ensure_ascii=False).encode()).hexdigest()

def copy_layers(raw,absolute,node_id,include_children=False,point=None):
 nodes={n['id']:n for n in raw['nodes']};placed={n['id']:n for n in absolute['nodes']}
 if node_id not in nodes:raise ValueError('HTML 页面已变化，请重新选择图层')
 chosen={node_id}
 if include_children:
  for n in raw['nodes']:
   if n.get('parent') in chosen:chosen.add(n['id'])
 root=placed[node_id];point=point or {'x':root['x'],'y':root['y']}
 if any(not isinstance(point.get(k),(int,float)) or not math.isfinite(point[k]) for k in ('x','y')):raise ValueError('放置坐标无效')
 ids={i:'import-'+uuid.uuid4().hex for i in chosen};group='group-'+uuid.uuid4().hex if len(chosen)>1 else ''
 result=[]
 for old in raw['nodes']:
  if old['id'] not in chosen:continue
  n=copy.deepcopy(old);oldid=n['id'];parent=n.get('parent','');n.update(id=ids[oldid],parent=ids.get(parent,''),sharedKey=None,groupID=group,locked=False)
  if parent not in chosen:n.update(x=point['x']+placed[oldid]['x']-root['x'],y=point['y']+placed[oldid]['y']-root['y'])
  n['name']=(old.get('text') or old.get('name') or oldid).strip()[:80]
  source_page=next((page for page in raw.get('modalPages',[]) if oldid==page or oldid.startswith(page+'/')),raw['id'])
  if not oldid.startswith('$shade'):n['origin']={'node':oldid,'page':source_page,'params':copy.deepcopy(raw.get('routeParams',{}))}
  if oldid in raw.get('events',{}):n['interaction']=copy.deepcopy(raw['events'][oldid])
  result.append(n)
 return result
