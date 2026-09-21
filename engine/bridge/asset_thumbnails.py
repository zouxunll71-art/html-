"""Disposable thumbnails; original resources are never changed."""
import subprocess,threading,uuid
from pathlib import Path
LIMIT=threading.BoundedSemaphore(3)
def thumbnail(source,cache,size):
 if size not in (192,384):raise ValueError('Unsupported thumbnail size')
 if source.suffix.lower() not in ('.png','.jpg','.jpeg','.webp'):raise ValueError('Not an image')
 cache.mkdir(parents=True,exist_ok=True);dest=cache/(source.name+'.'+str(size)+'.png')
 if dest.is_file():return dest.read_bytes()
 with LIMIT:
  if dest.is_file():return dest.read_bytes()
  temp=cache/(uuid.uuid4().hex+'.png')
  try:
   result=subprocess.run(['/usr/bin/sips','-s','format','png','-Z',str(size),str(source),'--out',str(temp)],capture_output=True,timeout=30)
   if result.returncode or not temp.is_file():raise ValueError('缩略图生成失败')
   temp.replace(dest);return dest.read_bytes()
  finally:temp.unlink(missing_ok=True)
