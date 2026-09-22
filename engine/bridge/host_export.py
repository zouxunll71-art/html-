"""Explicit export into a user's Xcode host; never rewrites project settings."""
import hashlib,json,plistlib,re,shutil,subprocess,tempfile,uuid
from pathlib import Path

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def inventory(root):
 if any(p.is_symlink() for p in root.rglob('*')):raise ValueError('导出目录不允许符号链接')
 return {str(p.relative_to(root)):digest(p) for p in root.rglob('*') if p.is_file()}
def inspect(bundle):
 bundle=Path(bundle).resolve();outer=bundle.parent
 projects=list(outer.glob('*.xcodeproj')) if bundle.name=='HTMLNativeStudio' else []
 if not projects:return None
 if len(projects)!=1:raise ValueError('外层存在多个 Xcode 工程，无法确定导出目标；外层文件未改动')
 project=projects[0];pbx=project/'project.pbxproj'
 data=json.loads(subprocess.check_output(['/usr/bin/plutil','-convert','json','-o','-',str(pbx)]));objects=data['objects']
 targets=[o for o in objects.values() if o.get('isa')=='PBXNativeTarget' and o.get('productType')=='com.apple.product-type.application']
 if len(targets)!=1:raise ValueError('自动迁移需要唯一的 iOS App target；外层文件未改动')
 groups=[objects[g] for g in targets[0].get('fileSystemSynchronizedGroups',[]) if g in objects]
 roots=[]
 for g in groups:
  path=Path(g.get('path',''))
  if g.get('sourceTree')=='<group>' and len(path.parts)==1 and path.name not in ['.','..','HTMLNativeStudio'] and (outer/path).is_dir():roots.append(outer/path)
 if len(roots)!=1:raise ValueError('自动迁移需要一个 Xcode 文件夹同步源码目录；当前工程结构不受支持，未改动外层文件')
 target=roots[0]
 if target.is_symlink() or project.is_symlink():raise ValueError('外层工程目录不能是符号链接')
 manifest=bundle/'iOS/host-export.json';old=json.loads(manifest.read_text()) if manifest.exists() else None
 entry=target/'ViewController.swift'
 if entry.is_symlink() or pbx.is_symlink():raise ValueError('导出入口不能是符号链接')
 if old:
  if old['target']!=target.name:raise ValueError('导出目标已变化，请先检查外层工程')
  if digest(entry)!=old['entryHash'] or inventory(target/'StudioGenerated')!=old['files']:raise ValueError('外层生成代码已被手动修改；为保留修改，本次未覆盖。请先将改动合并回工作区')
 else:
  if (target/'StudioGenerated').exists():raise ValueError('外层 StudioGenerated 已存在，不能覆盖未知文件')
  if not entry.is_file():raise ValueError('当前自动接入支持 UIKit Storyboard 空工程（ViewController.swift）；未修改外层工程')
  code=re.sub(r'//[^\n]*|/\*.*?\*/','',entry.read_text(),flags=re.S)
  if not re.fullmatch(r'\s*import UIKit\s+(?:final\s+)?class ViewController\s*:\s*UIViewController\s*\{\s*override func viewDidLoad\(\)\s*\{\s*super.viewDidLoad\(\)\s*\}\s*\}\s*',code):raise ValueError('ViewController 已有自定义代码，不能作为空工程自动覆盖')
  board=target/'Base.lproj/Main.storyboard'
  if not board.is_file() or 'customClass="ViewController"' not in board.read_text():raise ValueError('未找到空工程的 ViewController 启动页面')
 return dict(bundle=bundle,target=target,project=project,pbx=pbx,pbxHash=digest(pbx),entry=entry,entryHash=digest(entry),manifest=manifest,old=old)

def migrate(plan,exported,prefix):
 """Stage first, verify ownership, back up, then install with rollback."""
 if plan is None:return None
 bundle,target=plan['bundle'],plan['target'];exported=Path(exported).resolve()
 scratch=Path(tempfile.mkdtemp(prefix='.host-export-',dir=bundle/'iOS'))
 generated=scratch/'StudioGenerated';generated.mkdir()
 try:
  for folder in ['Shared','App']:
   for source in (exported/folder).iterdir():
    if source.name=='AppInfo.plist':continue
    dest=generated/source.name
    if dest.exists():raise ValueError('生成文件重名：'+source.name)
    if source.is_dir():shutil.copytree(source,dest)
    else:shutil.copy2(source,dest)
  app=generated/(prefix+'App.swift');code=app.read_text()
  start=code.index('@main final class ');end=code.index('final class '+prefix+'NativeRuntimeController',start)
  code=code[:start]+code[end:];code=code.replace('final class '+prefix+'NativeRuntimeController','class '+prefix+'NativeRuntimeController',1)
  # A production export never falls back to the development service.
  code=code.replace('}else{poll()}','}else{assertionFailure("Missing bundled app contract")}')
  app.write_text(code)
  entry=scratch/'ViewController.swift';entry.write_text('import UIKit\n\n// Generated only by explicit HTML Native Studio export.\nfinal class ViewController: '+prefix+'NativeRuntimeController {}\n')
  files=inventory(generated)
  if digest(plan['pbx'])!=plan['pbxHash'] or digest(plan['entry'])!=plan['entryHash']:raise ValueError('外层工程在导出期间发生变化，已停止迁移')
  if plan['old'] and inventory(target/'StudioGenerated')!=plan['old']['files']:raise ValueError('生成目录在导出期间发生变化，已停止迁移')
  if not plan['old'] and (target/'StudioGenerated').exists():raise ValueError('生成目录刚被创建，已停止迁移')
  backup=bundle/'iOS/HostBackups'/uuid.uuid4().hex;backup.mkdir(parents=True)
  shutil.copy2(plan['entry'],backup/'ViewController.swift')
  if plan['manifest'].exists():shutil.copy2(plan['manifest'],backup/'host-export.json')
  previous=target/'StudioGenerated';moved=False;installed=False
  try:
   if previous.exists():previous.rename(backup/'StudioGenerated');moved=True
   generated.rename(previous);installed=True
   entry.replace(plan['entry'])
   manifest=dict(version=1,target=target.name,entryHash=digest(plan['entry']),files=files,backup=str(backup.relative_to(bundle)),export=str(exported.relative_to(bundle)))
   temp=scratch/'manifest.json';temp.write_text(json.dumps(manifest,ensure_ascii=False,indent=2));temp.replace(plan['manifest'])
  except Exception:
   shutil.copy2(backup/'ViewController.swift',plan['entry'])
   if installed:shutil.rmtree(previous)
   if moved:(backup/'StudioGenerated').rename(previous)
   if (backup/'host-export.json').exists():shutil.copy2(backup/'host-export.json',plan['manifest'])
   raise
  return str(plan['project'])
 finally:shutil.rmtree(scratch,ignore_errors=True)
