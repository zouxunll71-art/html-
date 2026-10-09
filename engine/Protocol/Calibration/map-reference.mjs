import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

// Pure coordinate conversion. Does not alter source images, project files or native chrome.
export function mapReference(spec) {
 const finite=(v,name,min=-Infinity)=>{if(typeof v!=='number'||!Number.isFinite(v)||v<min)throw Error('Invalid '+name);return v;};
 const sw=finite(spec.sourceWidth,'sourceWidth',1),sh=finite(spec.sourceHeight,'sourceHeight',1);
 const tw=finite(spec.viewportWidth,'viewportWidth',1),scale=tw/sw;
 const top=finite(spec.contentInsets?.top??0,'contentInsets.top',0),bottom=finite(spec.contentInsets?.bottom??0,'contentInsets.bottom',0);
 const height=sh*scale;
 if(top+bottom>=height)throw Error('Insets consume the design canvas');
 if(spec.coordinateSpace!=='source-screen')throw Error('coordinateSpace must be source-screen: all source bounds measured from the full UI image origin');
 if(spec.viewportHeight!==undefined&&Math.abs(finite(spec.viewportHeight,'viewportHeight',1)-height)>0.01)throw Error('Aspect ratio mismatch: record a separate adaptation plan; do not stretch the design');
 if(!Array.isArray(spec.elements))throw Error('elements must be an array');
 const ids=new Map();
 for(const e of spec.elements){if(typeof e.id!=='string'||!e.id||ids.has(e.id))throw Error('Missing or duplicate element id');ids.set(e.id,e);}
 for(const e of spec.elements){
  let p=e,seen=new Set();
  while(p){if(seen.has(p.id))throw Error('Parent cycle: '+e.id);seen.add(p.id);
   if(p!==e&&((p.rotation??0)!==0||(p.scale??1)!==1||(p.scrollX??0)!==0||(p.scrollY??0)!==0))throw Error('Transformed or scrolled ancestor requires inverse-matrix measurement: '+p.id);
   if(!p.parentId)break;
   if(!ids.has(p.parentId))throw Error('Missing parent: '+p.parentId);p=ids.get(p.parentId);
  }
  if(e.placement!==undefined&&!['content','viewport-background'].includes(e.placement))throw Error('Unknown placement');
  if(e.placement==='viewport-background'&&e.parentId)throw Error('Viewport background must be a root element');
 }
 const round=v=>Math.round(v*1e6)/1e6;
 const elements=spec.elements.map(e=>{
  const x=finite(e.x,e.id+'.x'),y=finite(e.y,e.id+'.y'),w=finite(e.width,e.id+'.width',0),h=finite(e.height,e.id+'.height',0);
  const parent=e.parentId?ids.get(e.parentId):null;
  const parentX=parent?finite(parent.x,parent.id+'.x')*scale:0;
  const parentY=parent?finite(parent.y,parent.id+'.y')*scale:e.placement==='viewport-background'?0:top;
  const style={position:'absolute',left:round(x*scale-parentX),top:round(y*scale-parentY),width:round(w*scale),height:round(h*scale)};
  for(const [key,css] of [['fontSize','font-size'],['lineHeight','line-height'],['letterSpacing','letter-spacing'],['borderRadius','border-radius'],['borderWidth','border-width']])if(e[key]!==undefined)style[css]=round(finite(e[key],e.id+'.'+key)*scale);
  for(const key of ['rotation','opacity','scale'])if(e[key]!==undefined)style[key]=finite(e[key],e.id+'.'+key);
  if(style.opacity!==undefined&&(style.opacity<0||style.opacity>1))throw Error('Opacity must be in 0..1');
  if(style.scale!==undefined&&style.scale<=0)throw Error('Scale must be positive');
  return {id:e.id,parentId:e.parentId??null,placement:e.placement??'content',sourceBounds:{x,y,width:w,height:h},screenBounds:{x:round(x*scale),y:round(y*scale),width:style.width,height:style.height},style};
 });
 return {version:1,coordinateSpace:'design-local',scale,viewport:{width:tw,height:round(height)},contentInsets:{top,bottom},contentHeight:round(height-top-bottom),elements,notes:['Candidate geometry only; preserve existing native controls, actions, layer IDs and clipping declarations.','Insets subtracted once at content roots; children use parent-local coordinates.','Does not validate fonts, assets, visual fidelity, or device adaptation.']};
}
if(process.argv[1]&&path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{if(process.argv.length!==3)throw Error('Usage: map-reference.mjs template.json');process.stdout.write(JSON.stringify(mapReference(JSON.parse(fs.readFileSync(process.argv[2],'utf8'))),null,2)+'\n');}
 catch(e){console.error(e.message);process.exitCode=1;}
}
