"""Rebuild the served model bundle when its source changes. No network installs."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
web=root/'Web';inputs=[web/'model-paint.js',*sorted((web/'model-vendor').glob('*.js'))]
digest=hashlib.sha256(b''.join(p.read_bytes() for p in inputs)).hexdigest();manifest=web/'model-paint-build.json'
if manifest.exists() and json.loads(manifest.read_text()).get('sourceHash')==digest:
 bundle=(web/'model-paint.bundle.js').read_text()
else:
 binary=os.environ.get('ESBUILD_BIN') or shutil.which('esbuild')
 if not binary:raise SystemExit('Model source changed. Set ESBUILD_BIN to the local esbuild executable; no bundle was silently reused.')
 subprocess.run([binary,str(web/'model-paint.js'),'--bundle','--format=iife','--global-name=StudioModelPainting','--minify','--outfile='+str(web/'model-paint.bundle.js')],check=True)
 bundle=(web/'model-paint.bundle.js').read_text();manifest.write_text(json.dumps({'sourceHash':digest,'esbuild':'0.25.10'},indent=2)+'\n')
p=web/'native-ui.js';prefix=p.read_text().split('// MODEL_PAINT_BUNDLE',1)[0].rstrip();p.write_text(prefix+'\n\n// MODEL_PAINT_BUNDLE\n'+bundle)
print('Model bundle source verified')
