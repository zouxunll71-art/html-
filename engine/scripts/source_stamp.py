"""Content fingerprints for builds and the loaded local service."""
import hashlib,json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def fingerprint(kind):
 folders=('Studio','Runtime','Shared') if kind=='build' else ('bridge','Web','Shared','Protocol')
 paths=[]
 for folder in folders:
  for p in (ROOT/folder).rglob('*'):
   if p.is_file() and '__pycache__' not in p.parts and p.suffix in ('.swift','.js','.mjs','.html','.css','.py','.json','.txt','.md') and p.name not in ('token','config.json'):paths.append(p)
 if kind=='build':paths += [ROOT/'scripts/build.sh',ROOT/'scripts/make_project.py',ROOT/'scripts/ios_frames.m',ROOT/'scripts/ios_input.m']
 digest=hashlib.sha256()
 for p in sorted(set(paths)):digest.update(str(p.relative_to(ROOT)).encode());digest.update(p.read_bytes())
 return digest.hexdigest()
if __name__=='__main__':
 current=fingerprint('build')
 if sys.argv[1:]==['--print']:print(current);sys.exit(0)
 if len(sys.argv)>1 and sys.argv[1]!=current:raise SystemExit('构建期间源码发生变化，请再次打开工作台以构建最新版本。')
 (ROOT/'artifacts').mkdir(exist_ok=True)
 (ROOT/'artifacts/build-source.json').write_text(json.dumps({'fingerprint':current}))
