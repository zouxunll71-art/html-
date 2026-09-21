"""Create a separate, importable optimized project; never overwrite source files."""
import json,struct,zlib,shutil,subprocess,threading,uuid,time
from pathlib import Path
from compiler import compile_project
JOBS={};LOCK=threading.Lock()

def lossless_png(data):
 if not data.startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('Invalid PNG signature')
 chunks=[];offset=8;payload=[]
 while offset<len(data):
  if offset+12>len(data):raise ValueError('Truncated PNG')
  length=struct.unpack('>I',data[offset:offset+4])[0];end=offset+12+length
  if end>len(data):raise ValueError('Truncated PNG chunk')
  tag=data[offset+4:offset+8];body=data[offset+8:end-4]
  if zlib.crc32(tag+body)&0xffffffff != struct.unpack('>I',data[end-4:end])[0]:raise ValueError('PNG CRC mismatch')
  if tag==b'acTL':return data  # Preserve animation byte-for-byte.
  if tag==b'IHDR':
   width,height=struct.unpack('>II',body[:8])
   if width*height*8>128*1024*1024:return data
  if tag==b'IDAT':payload.append(body)
  chunks.append((tag,data[offset:end]));offset=end
 if not payload or chunks[-1][0]!=b'IEND':raise ValueError('Incomplete PNG')
 decoder=zlib.decompressobj();raw=decoder.decompress(b''.join(payload),128*1024*1024+1)
 if len(raw)>128*1024*1024 or not decoder.eof:raise ValueError('PNG decoded data exceeds safe limit')
 packed=zlib.compress(raw,9)
 if zlib.decompress(packed)!=raw:raise ValueError('Lossless verification failed')
 block=struct.pack('>I',len(packed))+b'IDAT'+packed+struct.pack('>I',zlib.crc32(b'IDAT'+packed)&0xffffffff)
 out=bytearray(data[:8]);added=False
 for tag,chunk in chunks:
  if tag==b'IDAT':
   if not added:out.extend(block);added=True
  else:out.extend(chunk)
 result=bytes(out)
 return result if len(result)<len(data) else data

def optimize(source,destination,mode='lossless',progress=lambda **kw:None):
 if mode not in ('lossless','visual'):raise ValueError('未知压缩方式')
 source=Path(source).resolve();destination=Path(destination)
 model=compile_project(source)
 if destination.resolve().is_relative_to(source):raise ValueError('压缩副本不能位于原项目内部')
 progress(stage='正在复制项目，保留原文件',total=len(model['assets']),done=0)
 shutil.copytree(source,destination,symlinks=False,ignore=shutil.ignore_patterns('.git','node_modules','.DS_Store','build','__pycache__'))
 before=after=changed=skipped=0;items=[]
 for i,asset in enumerate(model['assets']):
  path=destination/asset['source'];data=path.read_bytes();original=len(data);candidate=data;note='保持原文件'
  if asset['kind']=='image' and path.suffix.lower()=='.png':candidate=lossless_png(data);note='PNG 严格无损'
  elif asset['kind']=='image' and path.suffix.lower() in ('.jpg','.jpeg') and mode=='visual':
   temp=path.with_name(path.stem+'.compress-'+uuid.uuid4().hex+'.jpg')
   try:
    p=subprocess.run(['/usr/bin/sips','-s','format','jpeg','-s','formatOptions','85',str(path),'--out',str(temp)],capture_output=True,timeout=60)
    if p.returncode or not temp.is_file():raise ValueError('JPEG 压缩失败：'+asset['source'])
    candidate=temp.read_bytes();note='JPEG 质量 85（有损，请检查）'
   finally:temp.unlink(missing_ok=True)
  else:skipped+=1
  if len(candidate)<original:path.write_bytes(candidate);changed+=1
  else:candidate=data
  before+=original;after+=len(candidate);items.append(dict(source=asset['source'],before=original,after=len(candidate),method=note))
  progress(stage='正在压缩与校验',done=i+1,total=len(model['assets']),before=before,after=after)
 compile_project(destination)
 # Rebind authoring instructions to the new source location.
 import authoring
 authoring.install(destination)
 report=dict(path=str(destination),mode=mode,assets=len(model['assets']),changed=changed,unchanged=len(model['assets'])-changed,unsupportedOrFonts=skipped,before=before,after=after,saved=before-after,items=items,
 notice='这是 HTML 源项目副本，不包含工作台中尚未回写 HTML 的 iOS 编辑覆盖。原项目未修改。JPEG 视觉压缩需要人工检查；PNG 保留解压后字节与全部其他块。')
 (destination/'资源压缩报告.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 return report

def start(source,mode,desktop=None):
 with LOCK:
  if any(j['state']=='running' for j in JOBS.values()):raise ValueError('已有资源压缩任务正在进行')
  jid=uuid.uuid4().hex;JOBS[jid]=dict(state='running',stage='准备校验资源',done=0,total=0)
 def update(**kw):
  with LOCK:JOBS[jid].update(kw)
 def work():
  dest=None
  try:
   name=json.loads((Path(source)/'app.json').read_text()).get('name','App');name=''.join('-' if c in '/\\:' else c for c in name).strip('. ') or 'App'
   dest=Path(desktop or Path.home()/'Desktop')/(name+'-资源压缩-'+time.strftime('%Y%m%d-%H%M%S')+'-'+jid[:4])
   report=optimize(source,dest,mode,update);update(state='done',report=report,stage='压缩完成')
  except Exception as error:
   update(state='failed',error=str(error),path=str(dest or ''),stage='压缩失败；原项目未修改')
 threading.Thread(target=work,daemon=True).start();return jid

def status(jid):
 with LOCK:
  if jid not in JOBS:raise ValueError('任务不存在')
  result=dict(JOBS[jid])
  if 'report' in result:result['report']={k:v for k,v in result['report'].items() if k!='items'}
  return result
