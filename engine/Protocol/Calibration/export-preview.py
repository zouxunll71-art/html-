#!/usr/bin/env python3
"""Export an isolated HTML preview using the real Studio compiler and renderer.
Never activates a project or writes to its source, Workspace, or an iOS host.
"""
import argparse,json,shutil,sys,hashlib
from pathlib import Path
p=argparse.ArgumentParser()
p.add_argument('--engine',required=True);p.add_argument('--source',required=True);p.add_argument('--page',required=True)
p.add_argument('--output',required=True);p.add_argument('--width',type=int,required=True);p.add_argument('--height',type=int,required=True)
p.add_argument('--base-page',help='Explicit parent page for a detail navigation stack')
p.add_argument('--symbols',help='Optional directory with actual native symbol PNGs and manifest.json')
args=p.parse_args()
engine=Path(args.engine).resolve();source=Path(args.source).resolve();out=Path(args.output).resolve()
if out.exists():raise SystemExit('Output must be a new isolated directory')
if out==source or source in out.parents:raise SystemExit('Output must be outside business source')
if not 1<=args.width<=4096 or not 1<=args.height<=4096:raise SystemExit('Invalid dimensions')
sys.path.insert(0,str(engine/'bridge'))
from compiler import compile_project
model=compile_project(source)
if args.page not in model['pages']:raise SystemExit('Unknown page')
if args.base_page and args.base_page not in model['pages']:raise SystemExit('Unknown base page')
# This adapter does not pretend unsupported native effects/models are verified.
if model['pages'][args.page]['role']=='dialog':raise SystemExit('Dialog export requires an explicit underlying-state fixture; not implemented')
out.mkdir(parents=True);(out/'assets').mkdir();(out/'qa').mkdir();(out/'symbols').mkdir()
for asset in model['assets']:
 f=(source/asset['source']).resolve()
 if source not in f.parents:raise SystemExit('Asset escapes source')
 shutil.copy2(f,out/'assets'/asset['id'])
(out/'model.json').write_text(json.dumps(model,ensure_ascii=False))
shutil.copy2(engine/'Shared/engine.js',out/'engine.js')
shutil.copy2(engine/'Web/native-ui.js',out/'native-ui.js')
preview=(engine/'Web/preview.js').read_text()
start=preview.index('function api(path,body)');end=preview.index('\n',start)
preview=preview[:start]+'function api(path,body){return window.calibrationAPI(path,body)}'+preview[end:]
preview=preview.replace('/asset?project=${p.projectID}&id=${a.id}&token=${TOKEN}','assets/${a.id}').replace('/asset?project=${p.projectID}&id=${n.asset}&token=${TOKEN}','assets/${n.asset}')
preview=preview.replace('setInterval(poll,150);','')
(out/'preview.js').write_text(preview)
symbols=[]
if args.symbols:
 symbol_root=Path(args.symbols).resolve();symbols=json.loads((symbol_root/'manifest.json').read_text())
 for symbol in symbols:
  f=(symbol_root/symbol['file']).resolve()
  if symbol_root not in f.parents:raise SystemExit('Symbol escapes symbol directory')
  shutil.copy2(f,out/'symbols'/symbol['file'])
logical=model['viewport']['width'];scale=args.width/logical;height=args.height/scale
bootstrap='''const TOKEN='isolated-qa';
(async()=>{
 const model=await (await fetch('model.json')).json();
 const symbolManifest=SYMBOLS;
 let revision=1;
 const session={stack:STACK,modals:[],state:structuredClone(model.state),storage:{},scroll:{},tick:0,animation:null,locale:'en',effects:[],pendingEffects:{},chromeInsets:{},viewportHeight:HEIGHT};
 let current=session;
 window.calibrationAPI=async(path,body)=>{
  if(path.startsWith('/runtime'))return {projectID:model.id,model,session:current,page:StudioEngine.frame(model,current),assets:model.assets,editing:false,revision};
  if(path==='/event'){
   const event=body.event||{},declaration=StudioEngine.frame(model,current).events[event.node]||{};
   current=StudioEngine.reduce(model,current,{...declaration,...event});revision++;return {ok:true};
  }
  if(path==='/ack'||path==='/ack-effects')return {ok:true};
  throw Error('Unsupported isolated preview operation: '+path);
 };
 window.webkit={messageHandlers:{studio:{postMessage(message){
  if(message.type==='symbol'){
   const symbol=symbolManifest.find(s=>s.name===message.name&&s.color===message.color);
   if(!symbol){console.error('Missing native symbol: '+message.name+' '+message.color);return;}
   queueMicrotask(()=>window.studioSymbol(message.key,'symbols/'+symbol.file));
  }
  if(message.type==='rendered'){
   document.querySelectorAll('[data-node]').forEach(el=>{el.id='layer_'+Array.from(el.dataset.node).map(c=>c.codePointAt(0).toString(16)).join('_')});
   document.body.dataset.qaPage=message.route;document.body.dataset.qaReady='true';
  }
 }}}};
 for(const file of ['native-ui.js','preview.js'])await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src=file;script.onload=resolve;script.onerror=reject;document.head.append(script)});
})();'''.replace('SYMBOLS',json.dumps(symbols)).replace('STACK',json.dumps([{'page':v,'params':{}} for v in ([args.base_page,args.page] if args.base_page else [args.page])])).replace('HEIGHT',str(height))
(out/'bootstrap.js').write_text(bootstrap)
(out/'index.html').write_text('''<!doctype html><html><head><meta charset="utf-8"><link rel="icon" href="data:,"><style>
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden}#phone-stage{transform:none!important}#screen{position:relative;transform-origin:top left;transform:scale(SCALE)!important}body{user-select:none}input,textarea{user-select:text}button,input,textarea{font:inherit}
#error{position:fixed;bottom:0;background:#fff1ec;color:#9e2d13}
</style><link rel="stylesheet" href="qa/layout.css"></head><body><div id="phone-stage"><div id="screen"></div></div><div id="error"></div><script src="engine.js"></script><script src="bootstrap.js"></script></body></html>'''.replace('SCALE',str(scale)))
(out/'qa/layout.css').write_text('')
(out/'provenance.json').write_text(json.dumps({'adapter':'studio-renderer/1','page':args.page,'modelHash':model['hash'],'source':str(source),'referenceCanvas':{'width':args.width,'height':args.height},'logicalWidth':logical,'logicalHeight':height,'uniformScale':scale,'mapping':'Screen content rendered at reference canvas; no hardware shell or OS status/home indicator. Native page navigation remains.','rendererSHA256':hashlib.sha256((engine/'Web/preview.js').read_bytes()).hexdigest(),'limitations':['No iOS validation','No onEnter/delay effect fixture','No dialog fixture','No automatic declaration writeback; CSS candidates require mapping and re-export validation']},ensure_ascii=False,indent=2))
print(out)
