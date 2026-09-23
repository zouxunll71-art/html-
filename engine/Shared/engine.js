/* Pure, deterministic engine shared by WebKit, JavaScriptCore and the compiler worker. */
(function(global){'use strict';
const clone=x=>JSON.parse(JSON.stringify(x)),get=(o,p)=>String(p||'').split('.').filter(Boolean).reduce((v,k)=>v==null?undefined:v[k],o);
function set(o,p,v){const keys=p.split('.');if(keys.some(k=>['__proto__','constructor','prototype'].includes(k)))throw Error('Unsafe state path');let t=o;keys.slice(0,-1).forEach(k=>{if(t[k]==null)t[k]={};t=t[k]});t[keys[keys.length-1]]=clone(v)}
function translate(c,key,args={}){const table=c.localization?.tables?.[c.locale]||c.localization?.tables?.en;if(!table||!(key in table))throw Error('Missing localization key '+key);return table[key].replace(/\{([A-Za-z][A-Za-z0-9_]*)\}/g,(_,name)=>{if(!(name in args))throw Error('Missing localization argument '+name+' for '+key);return String(args[name])})}
function expr(v,c){if(Array.isArray(v))return v.map(x=>expr(x,c));if(!v||typeof v!=='object')return v;
 if('t'in v)return translate(c,v.t,expr(v.args||{},c));
 if(v.op==='revolveOBJ'){const a=(v.args||[]).map(x=>expr(x,c));return revolveOBJ(a[0],Number(a[1]||1),Number(a[2]||1));}
 if('get'in v)return get(c,v.get)??null;if('op'in v){
 if(['map','filter','find'].includes(v.op)){const rows=expr(v.args?.[0],c);if(!Array.isArray(rows))throw Error(v.op+' needs array');const fn=(item,index)=>expr(v.args[1],{...c,item,index});return v.op==='map'?rows.map(fn):v.op==='filter'?rows.filter(fn):(rows.find(fn)??null)}
 const a=(v.args||[]).map(x=>expr(x,c));
 if(['mul','div','round','number','min','max','abs','sqrt','atan2','format'].includes(v.op)){
  const ns=a.map(Number);if(ns.some(x=>!Number.isFinite(x)))throw Error('Numeric expression requires finite values');
  let result;
  switch(v.op){case 'mul':result=ns.reduce((x,y)=>x*y,1);break;case 'div':if(ns[1]===0)throw Error('Division by zero');result=ns[0]/ns[1];break;case 'number':result=ns[0];break;case 'min':result=Math.min(...ns);break;case 'max':result=Math.max(...ns);break;case 'abs':result=Math.abs(ns[0]);break;case 'sqrt':result=Math.sqrt(ns[0]);break;case 'atan2':result=Math.atan2(ns[0],ns[1])*180/Math.PI;break;case 'round':case 'format':{const places=ns[1]??0;if(!Number.isInteger(places)||places<0||places>10)throw Error('Decimal places must be 0-10');result=v.op==='format'?ns[0].toFixed(places):Number(ns[0].toFixed(places));break;}}
  if(typeof result==='number'&&!Number.isFinite(result))throw Error('Non-finite numeric result');return result;
 }
 switch(v.op){case 'at':if(!Array.isArray(a[0])||!Number.isInteger(a[1]))throw Error('at needs array and integer');return a[0][a[1]]??null;case 'mod':return a[0]%a[1];case 'sum':if(!Array.isArray(a[0]))throw Error('sum needs array');if(a[0].some(x=>typeof x!=='number'||!Number.isFinite(x)))throw Error('sum needs finite numbers');return a[0].reduce((sum,x)=>sum+x,0);case 'trim':return String(a[0]??'').trim();case 'split':return String(a[0]??'').split(String(a[1]??'\n'));case 'join':if(!Array.isArray(a[0]))throw Error('join needs array');return a[0].join(String(a[1]??''));case 'contains':return String(a[0]??'').toLocaleLowerCase().includes(String(a[1]??'').toLocaleLowerCase());case 'eq':return a[0]===a[1];case 'not':return !a[0];case 'and':return a.every(Boolean);case 'or':return a.some(Boolean);case 'add':return a.reduce((x,y)=>x+Number(y),0);case 'sub':return a[0]-a[1];case 'gt':return a[0]>a[1];case 'gte':return a[0]>=a[1];case 'lt':return a[0]<a[1];case 'concat':return a.join('');case 'length':return a[0]?.length||0;case 'if':return a[0]?a[1]:a[2];default:throw Error('Unknown expression '+v.op)}}
 return Object.fromEntries(Object.entries(v).map(([k,x])=>[k,expr(x,c)]));}
function validatePoints(points){
 if(!Array.isArray(points)||points.length<2||points.length>256||points.some(p=>!Array.isArray(p)||p.length!==2||p.some(v=>typeof v!=='number'||!Number.isFinite(v))))throw Error('Points require 2-256 finite XY pairs');
}
function revolveGeometry(profile){
 if(!Array.isArray(profile)||profile.length<2||profile.length>64||profile.some(p=>!Number.isFinite(p.r)||!Number.isFinite(p.y)||p.r<0||p.r>10||p.y<0||p.y>1))throw Error('Invalid normalized revolution profile');
 for(let i=1;i<profile.length;i++)if(profile[i].y<=profile[i-1].y)throw Error('Profile heights must increase');
 const count=64,vertices=[],faces=[];
 for(const p of profile)for(let k=0;k<count;k++){const a=2*Math.PI*k/count;vertices.push([p.r*Math.cos(a),p.y*2-1,p.r*Math.sin(a)]);}
 for(let i=0;i<profile.length-1;i++)for(let k=0;k<count;k++){const a=i*count+k,b=i*count+(k+1)%count;faces.push([a,b,b+count,a+count]);}
 return {vertices,faces};
}
function revolveOBJ(profile,height,diameter){
 if(!Number.isFinite(height)||!Number.isFinite(diameter)||height<=0||diameter<=0)throw Error('Positive mesh dimensions required');
 const m=revolveGeometry(profile);return '# Generic surface of revolution; dimensions in centimeters\n'+m.vertices.map(v=>'v '+[v[0]*diameter/2,(v[1]+1)*height/2,v[2]*diameter/2].join(' ')).join('\n')+'\n'+m.faces.map(f=>'f '+f.map(i=>i+1).join(' ')).join('\n')+'\n';
}
function projectRevolve(profile,angle,elevation,color){
 if(!Number.isFinite(angle)||!Number.isFinite(elevation))throw Error('Finite camera angles required');
 const m=revolveGeometry(profile),a=angle*Math.PI/180,e=elevation*Math.PI/180;
 const vertices=m.vertices.map(([x,y,z])=>{const X=x*Math.cos(a)+z*Math.sin(a),Z=-x*Math.sin(a)+z*Math.cos(a);return [X,y*Math.cos(e)-Z*Math.sin(e),y*Math.sin(e)+Z*Math.cos(e)]});
 const rgb=[1,3,5].map(i=>parseInt(color.slice(i,i+2),16));
 return m.faces.map(f=>{const pts=f.map(i=>vertices[i]),u=pts[1].map((v,i)=>v-pts[0][i]),v=pts[3].map((x,i)=>x-pts[0][i]);const normal=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],len=Math.hypot(...normal)||1;const light=.38+.62*Math.abs((normal[0]*-.4+normal[1]*.5+normal[2]*.75)/len);const hex='#'+rgb.map(c=>Math.min(255,Math.round(c*light+18*light)).toString(16).padStart(2,'0')).join('');return {points:pts.map(p=>[.5+p[0]*.4,.5-p[1]*.4]),color:hex,depth:pts.reduce((s,p)=>s+p[2],0)/4};}).sort((a,b)=>a.depth-b.depth);
}
function text(value,c){return String(value??'').replace(/\{\{\s*([\w.]+)\s*\}\}/g,(_,p)=>String(get(c,p)??''))}
function initial(model){const session={stack:[{page:model.entry,params:{}}],modals:[],state:clone(model.state),storage:{},scroll:{},tick:0,animation:null,locale:model.localization?.default||'en',effects:[],pendingEffects:{},chromeInsets:{}};return model.pages[model.entry].onEnter?reduce(model,session,{action:model.pages[model.entry].onEnter}):session}
function context(s,item,event){return {state:s.state,params:event?.sourceParams||s.stack[s.stack.length-1].params,item:item||{},event:event||{},storage:s.storage}}
// Dialogs are keyed pages, not anonymous instances. Recover old duplicate stacks
// without discarding page data or edits, retaining the topmost occurrence.
function modalPages(model,session){
 const seen=new Set([session.stack[session.stack.length-1].page]),result=[];
 for(const id of [...(session.modals||[])].reverse()){
  if(!model.pages[id]||model.pages[id].role!=='dialog')throw Error('Unknown dialog in session: '+id);
  if(!seen.has(id)){seen.add(id);result.push(id)}
 }
 return result.reverse();
}
function reduce(model,session,event){if(event.requiresAnalysis){const v=event.value;if(!v||v.version!==1||!Array.isArray(v.regions)||v.regions.length!==12||v.regions.some(r=>!Number.isFinite(r.coverage)||r.coverage<0||r.coverage>1||!Number.isFinite(r.saturation)||r.saturation<0||r.saturation>1))throw Error('Invalid model analysis');}if(event.requiresValue&&(typeof event.value!=='string'||!event.value.trim()))throw Error('Model save requires a completed work identifier');const s=clone(session);s.modals=modalPages(model,s);if(event.disabled)return s;s.animation=null;s.effects=s.effects||[];const ctx=()=>({...context(s,event.item,event),localization:model.localization,locale:s.locale||'en'});let budget=256;
 if(['navigate','tab','back','popTo'].includes(event.type))s.routeEpoch=(s.routeEpoch||0)+1;
 function run(steps){for(const a of steps||[]){if(--budget<0)throw Error('Action sequence exceeds 256 steps');const val=()=>expr(a.value,ctx());switch(a.type){
 case 'call':run(model.actions[a.action]);break;
 case 'delay':{const id=String(s.tick+1)+':'+s.effects.length;const effect={type:'delay',duration:a.duration,id};s.pendingEffects=s.pendingEffects||{};s.pendingEffects[id]={...effect,actions:clone(a.actions),scope:a.scope,routeEpoch:s.routeEpoch||0,item:clone(event.item||{}),sourceParams:clone(ctx().params)};s.effects.push(effect);break}
 case 'openURL':{const url=model.links?.[a.link];if(!url)throw Error('Unknown link '+a.link);s.effects.push({type:'openURL',url,id:String(s.tick+1)+':'+s.effects.length});break}
 case 'set':set(s.state,a.path,val());break;
 case 'generateID':{const uuid=typeof global.crypto?.randomUUID==='function'?global.crypto.randomUUID():'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,k=>{const r=Math.floor(Math.random()*16);return (k==='x'?r:(r&3)|8).toString(16)});set(s.state,a.path,uuid);break;}
 case 'forget':delete s.storage[a.key];break;
 case 'share':{const filename=String(expr(a.filename,ctx())),content=String(expr(a.content,ctx())),mime=a.mime||'text/plain';if(!/^[A-Za-z0-9][A-Za-z0-9._-]{0,100}$/.test(filename))throw Error('Unsafe export filename');s.effects.push({type:'share',filename,content,mime,id:String(s.tick+1)+':'+s.effects.length});break;}
 case 'toggle':set(s.state,a.path,!get(s.state,a.path));break;
 case 'append':{const list=get(s.state,a.path);if(!Array.isArray(list))throw Error('Append needs array');list.push(val());break}
 case 'remove':{const list=get(s.state,a.path);set(s.state,a.path,list.filter(x=>get(x,a.key)!==val()));break}
 case 'update':{const list=get(s.state,a.path);const id=expr(a.id,ctx());list.forEach(x=>{if(get(x,a.key)===id)Object.assign(x,val())});break}
 case 'if':run(expr(a.when,ctx())?a.then:a.else);break;
 case 'push':case 'replace':case 'tab':{s.routeEpoch=(s.routeEpoch||0)+1;if(!model.pages[a.page]||model.pages[a.page].role==='dialog')throw Error('Unknown navigation page');const p={page:a.page,params:expr(a.params||{},ctx())};if(a.type==='tab')s.stack=[p];else if(a.type==='replace')s.stack[s.stack.length-1]=p;else s.stack.push(p);s.modals=[];if(model.pages[a.page].onEnter){const previous=event;event={...event,sourceParams:p.params};run(model.actions[model.pages[a.page].onEnter]);event=previous}break}
 case 'back':if(s.modals.length)s.modals.pop();else if(s.stack.length>1)s.stack.pop();break;
 case 'present':if(!model.pages[a.page]||model.pages[a.page].role!=='dialog')throw Error('Unknown dialog');if(s.modals.includes(a.page)||s.stack[s.stack.length-1].page===a.page)break;s.modals.push(a.page);if(model.pages[a.page].onEnter)run(model.actions[model.pages[a.page].onEnter]);break;
 case 'dismiss':s.modals.pop();break;
 case 'persist':s.storage[a.key]=val();break;
 case 'restore':set(s.state,a.path,clone(s.storage[a.key]??a.default));break;
 case 'reset':s.state=clone(model.state);s.pendingEffects={};s.effects=[];break;
 case 'animate':s.animation=clone(a);run(a.actions);break;
 default:throw Error('Unknown action '+a.type)
 }}}
 if(event.type==='effectComplete'){const pending=s.pendingEffects?.[event.id];if(!pending)return s;delete s.pendingEffects[event.id];s.effects=s.effects.filter(e=>e.id!==event.id);event={...event,item:pending.item||{},sourceParams:pending.sourceParams||{}};if(pending.scope!=='page'||(pending.routeEpoch===(s.routeEpoch||0)&&!s.editingPage))run(pending.actions)}
 else if(event.type==='locale'){if(!['en','zh-Hans'].includes(event.locale))throw Error('Unsupported locale');s.locale=event.locale}
 else if(event.type==='chromeInsets'){for(const key of ['top','bottom'])if(!Number.isFinite(event[key])||event[key]<0||event[key]>250)throw Error('Invalid safe area');s.chromeInsets={top:event.top,bottom:event.bottom};if(event.height!=null){if(!Number.isFinite(event.height)||event.height<240||event.height>4096)throw Error('Invalid viewport height');s.viewportHeight=event.height}}
 else if(event.type==='tab')run([{type:'tab',page:event.page}]);
 else if(event.type==='popTo'){if(!Number.isInteger(event.depth)||event.depth<1||event.depth>s.stack.length)throw Error('Invalid navigation depth');s.stack=s.stack.slice(0,event.depth);s.modals=[]}
 else if(event.type==='navigate'){if(!model.pages[event.page])throw Error('Unknown page');s.stack=[{page:event.page,params:{}}];s.modals=[];delete s.editingPage;delete s.presentationPaused;if(event.preview===true){s.editingPage=event.page;s.animation=null;s.effects=[];s.pendingEffects={}}else if(model.pages[event.page].onEnter)run(model.actions[model.pages[event.page].onEnter])}
 else if(event.type==='scroll')s.scroll[event.node]={x:event.x||0,y:event.y||0};
 else if(event.type==='back')run([{type:'back'}]);
 else {if(event.bind)set(s.state,event.bind,event.value);if(event.action){if(!model.actions[event.action])throw Error('Unknown action '+event.action);run(model.actions[event.action])}}
 s.tick++;return s;}
function style(raw,c){const st={...(raw.style||{}),...expr(raw.styles||{},c)};for(const [k,v] of Object.entries(st)){
 const numeric=['width','height','left','top','right','bottom','gap','padding','font-size','font-weight','line-height','letter-spacing','border-radius','border-width','opacity','rotation','scale','columns','row-height','flex-grow'];
 if(numeric.includes(k)&&!(['width','height'].includes(k)&&['fill','auto'].includes(v))&&(typeof v!=='number'||!Number.isFinite(v)))throw Error('Invalid dynamic style '+raw.id+'.'+k);
 if(['color','background','border-color'].includes(k)&&!/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(v))throw Error('Invalid color '+raw.id+'.'+k);
 }return st;}
function rawFrame(model,session,overrides){const nodes=[],nodeIDs=new Set(),events={},layout={...model.viewport,height:session.viewportHeight||model.viewport.height},ctx={...context(session),localization:model.localization,locale:session.locale||'en'},assets=Object.fromEntries(model.assets.map(a=>[a.name,a]));
 function num(v,available,fallback){if(v==null||v==='auto')return fallback;if(v==='fill')return available;return Number(v)}
 function expanded(children,c,prefix){let out=[];for(const raw of children||[]){if(raw['runtime-only']&&session.editingPage)continue;if(raw.when&&!expr(raw.when,c))continue;
 if(raw.repeat){const rows=expr(raw.repeat,c);if(!Array.isArray(rows))throw Error('repeat must be array: '+raw.id);const keys=new Set();for(const item of rows){const key=get(item,raw.key);if(key==null||keys.has(String(key)))throw Error('Missing/duplicate repeat key: '+raw.id);keys.add(String(key));out.push({raw,c:{...c,item},id:prefix+raw.id+'['+key+']'})}}
 else out.push({raw,c,id:prefix+raw.id});}return out;}
 function render(raw,c,id,box,parent,z){const st=style(raw,c),patch=overrides?.[id]||{},typ=raw.type;
 let n={id,name:raw.name||id,type:typ,action:raw.action||'', text:raw['text-key']?translate(c,raw['text-key'],expr(raw['text-args']||{},c)):('content'in raw)?String(expr(raw.content,c)??''):text(raw.text,c),x:box.x,y:box.y,width:box.w,height:box.h,rotation:st.rotation||0,opacity:st.opacity??1,fill:st.background||'#00000000',color:st.color||'#17212B',fontSize:st['font-size']||16,fontWeight:st['font-weight']||400,fontFamily:st['font-family']||'sans',alignment:st['text-align']||'left',lineHeight:st['line-height'],letterSpacing:st['letter-spacing'],cornerRadius:st['border-radius']||0,strokeColor:st['border-color']||'#00000000',strokeWidth:st['border-width']||0,fit:st['object-fit']||'fit',groupID:raw.group||'',sharedKey:raw.shared||null,hidden:false,locked:false,parent:parent||'',clip:st.overflow==='hidden',scale:st.scale||1,gradient:raw.gradient||null,shadow:raw.shadow||null,options:raw['option-keys']?raw['option-keys'].map(key=>translate(c,key)):raw.options||[],step:raw.step||1,disabled:raw.disabled?!!expr(raw.disabled,c):false,placeholder:raw['placeholder-key']?translate(c,raw['placeholder-key']):raw.placeholder||'',value:raw.bind&&typeof get(session.state,raw.bind)==='number'?get(session.state,raw.bind):0,isOn:raw.bind?!!get(session.state,raw.bind):false,minimum:raw.min??0,maximum:raw.max??1,inputType:raw.inputType||'text',source:raw.source};
 if(raw.bind&&['nativeTextField','nativeTextView'].includes(typ))n.text=String(get(session.state,raw.bind)??'');
 n.textKey=raw['text-key']||null;n.placeholderKey=raw['placeholder-key']||null;n.symbol=raw.symbol||null;n.selected=raw.selected?!!expr(raw.selected,c):false;
 const aid=raw.asset?text(raw.asset,c):'';if(aid){if(!assets[aid])throw Error('Missing resource '+aid);n.asset=assets[aid].id}
 if(raw.font){if(!assets[raw.font])throw Error('Missing font '+raw.font);n.fontName=assets[raw.font].postscript}
 if(raw.spans){if(raw.spans.some(s=>s.end>n.text.length))throw Error('Rich text span out of range: '+id);n.textSpans=raw.spans;}
 Object.assign(n,patch);if(n.hidden)return;if(nodeIDs.has(n.id))throw Error('Duplicate rendered layer ID: '+n.id);nodeIDs.add(n.id);nodes.push(n);
 events[id]={action:raw.action||'',bind:raw.bind||'',...(raw['model-asset']?{requiresValue:true}:{}),item:c.item||{},sourceParams:c.params||{},disabled:n.disabled};
 if(typ==='path'){n.points=expr(raw.points,c);n.closed=!!expr(raw.closed,c);validatePoints(n.points);return;}
 if(typ==='model'&&raw['model-asset']){const a=assets[text(raw['model-asset'],c)];if(!a||a.kind!=='model')throw Error('Missing GLB resource');n.modelAsset=a.id;n.paintOptions=expr(raw['paint-options']||{},c);if(raw['analysis-action'])events[id+'#analysis']={action:raw['analysis-action'],requiresAnalysis:true,item:c.item||{},sourceParams:c.params||{}};n.type='image';return;}
 if(typ==='model'){n.mesh=projectRevolve(expr(raw.profile,c),Number(expr(raw.angle||0,c)),Number(expr(raw.elevation||15,c)),n.color);return;}
 if(typ==='text'||typ==='image'||typ.startsWith('native'))return;
 const kids=expanded((raw.children||[]).filter(child=>child.placement!=='viewport-background'),c,id+'/'),pad=st.padding||0,gap=st.gap||0,inner={x:pad,y:pad,w:Math.max(0,n.width-2*pad),h:Math.max(0,n.height-2*pad)};
 const direction=st['flex-direction']||'column',row=direction==='row',mode=st.display||'flex',columns=st.columns||1;
 const flows=kids.filter(k=>style(k.raw,k.c).position!=='absolute');let fixed=0,flex=0;
 for(const k of flows){const s=style(k.raw,k.c);let size=s[row?'width':'height'];if(size==='fill'||s['flex-grow'])flex+=s['flex-grow']||1;else fixed+=num(size,row?inner.w:inner.h,44)}
 const remainder=Math.max(0,(row?inner.w:inner.h)-fixed-gap*Math.max(0,flows.length-1));let cursor=0,idx=0,maxX=inner.w,maxY=inner.h;
 for(const k of kids){const s=style(k.raw,k.c);let x=inner.x,y=inner.y,w=num(s.width,inner.w,row?44:inner.w),h=num(s.height,inner.h,44);
 if(s.position==='absolute'||mode==='stack'){x=num(s.left,inner.w,0);y=num(s.top,inner.h,0);w=num(s.width,inner.w,inner.w);h=num(s.height,inner.h,44);if(s.right!=null)x=n.width-s.right-w;if(s.bottom!=null)y=n.height-s.bottom-h}
 else if(mode==='grid'){w=(inner.w-gap*(columns-1))/columns;h=num(s.height,inner.h,44);x+=idx%columns*(w+gap);y+=Math.floor(idx/columns)*((st['row-height']||h)+gap);idx++}
 else{const grow=s['flex-grow']||((row?s.width:s.height)==='fill'?1:0);if(grow){if(row)w=remainder*grow/flex;else h=remainder*grow/flex}if(row)x+=cursor;else y+=cursor;cursor+=(row?w:h)+gap;const align=s['align-self']||st['align-items'];if(align==='center'){if(row)y+=(inner.h-h)/2;else x+=(inner.w-w)/2}else if(align==='end'){if(row)y+=inner.h-h;else x+=inner.w-w}}
 maxX=Math.max(maxX,x+w+pad);maxY=Math.max(maxY,y+h+pad);render(k.raw,k.c,k.id,{x,y,w,h},n.id,z+1);
 }
 if(typ==='scroll'){n.contentWidth=maxX;n.contentHeight=maxY;const off=session.scroll[n.id]||{};n.scrollX=Math.max(0,Math.min(maxX-n.width,off.x||0));n.scrollY=Math.max(0,Math.min(maxY-n.height,off.y||0));}
 }
 const rootPage=session.stack[session.stack.length-1].page,p=model.pages[rootPage];if(!p)throw Error('Current page deleted');
 const nav=model.navigation,tabItems=nav?.tabs||[],hasTabs=tabItems.some(t=>t.page===session.stack[0].page),showTabs=hasTabs&&session.stack.length===1;
 const nativeChrome=nav?{tabs:tabItems.map(t=>({...t,title:translate(ctx,t.titleKey)})),showTabs,hasTabs,tint:nav.tint||'#007AFF',background:nav.background||'#FFFFFF',topBarTransparent:nav.topBarTransparent===true,stack:session.stack.map(entry=>{const item=model.pages[entry.page].navigation||{};return {page:entry.page,title:item.titleKey?translate(ctx,item.titleKey):'',backTitle:item.backTitleKey?translate(ctx,item.backTitleKey):null,hidden:!!item.hidden,buttons:(item.buttons||[]).map(b=>{const id='$nav.'+entry.page+'.'+b.id;events[id]={action:b.action};return {...b,node:id,title:translate(ctx,b.titleKey)}})}})}:null;
 const insets=nativeChrome?{top:session.chromeInsets?.top??(p.navigation?.hidden?59:103),bottom:session.chromeInsets?.bottom??(showTabs?83:34)}:{top:0,bottom:0};
 for(const background of (p.root.children||[]).filter(child=>child.placement==='viewport-background'))render(background,ctx,rootPage+'/'+background.id,{x:0,y:0,w:layout.width,h:layout.height},'',0);
 render(p.root,ctx,rootPage,{x:0,y:insets.top,w:layout.width,h:Math.max(1,layout.height-insets.top-insets.bottom)},'',0);
 const modals=modalPages(model,session);
 modals.forEach((id,i)=>{const p=model.pages[id];const backdrop={id:'modalShade'+i,type:'shape',name:'Modal backdrop',style:{background:'#00000066'},action:p.dismissOnBackdrop?'$dismiss':''};render(backdrop,ctx,'$shade'+i,{x:0,y:0,w:layout.width,h:layout.height},'',0);render(p.root,ctx,id,{x:0,y:0,w:layout.width,h:layout.height},'',0)});
 return {id:rootPage,name:p.name,route:rootPage,routeParams:clone(ctx.params),width:layout.width,height:layout.height,background:'#FFFFFF',nodes,events,nativeChrome,contentInsets:insets,modalPages:modals,locale:ctx.locale,effects:session.effects||[],animation:session.animation,animationID:model.hash+':'+session.tick};}
function normalizeLayerOrder(nodes){for(let i=0;i<nodes.length;i++)if(!Number.isFinite(nodes[i].layerOrder))nodes[i].layerOrder=i;return nodes}
function editorFrame(page){const copy=clone(page),map={};normalizeLayerOrder(copy.nodes);for(const n of copy.nodes){map[n.id]=n;const p=map[n.parent];if(p){n.x+=p.x-(p.type==='scroll'?p.scrollX||0:0);n.y+=p.y-(p.type==='scroll'?p.scrollY||0:0)} }copy.nodes=copy.nodes.map((n,i)=>({n,i})).sort((a,b)=>(a.n.layerOrder??a.i)-(b.n.layerOrder??b.i)).map(v=>v.n);return copy}
function applyEditor(page,edit){const base=editorFrame(page),map=Object.fromEntries(base.nodes.map(n=>[n.id,n])),out={};for(const n of edit.nodes){const old=map[n.id];if(!old){out[n.id]=n;continue}const d={};for(const k of Object.keys(n)){if(['id','source','sharedKey','textKey','placeholderKey','symbol','selected'].includes(k))continue;if(JSON.stringify(n[k])!==JSON.stringify(old[k]))d[k]=n[k]}if(Object.keys(d).length)out[n.id]=d;}for(const n of base.nodes)if(!edit.nodes.some(e=>e.id===n.id))out[n.id]={hidden:true};return out}
// Apply iOS visual edits while retaining source actions, localized copy and live control state.
function compose(model,session,overrides={},additions={}){
 const page=rawFrame(model,session),sourcePages={[page.id]:page};
 for(const n of page.nodes){const patch={...(overrides[n.sharedKey||n.id]?.patch||{})};delete patch.scrollX;delete patch.scrollY;Object.assign(n,patch)}
 const extra=clone(additions[page.id]||[]);
 const ids=new Set(page.nodes.map(n=>n.id));for(const n of extra){if(!n.id||ids.has(n.id))throw Error('Duplicate or missing added layer ID: '+n.id);ids.add(n.id)}
 for(const n of extra){
  const origin=n.origin;
  if(origin&&model.pages[origin.page]){
   const cacheKey=origin.page+':'+JSON.stringify(origin.params||{});
   if(!sourcePages[cacheKey]){const sourceSession=clone(session);sourceSession.stack=[{page:origin.page,params:origin.params||{}}];sourceSession.modals=[];sourcePages[cacheKey]=frame(model,sourceSession)}
   const source=sourcePages[cacheKey],original=source.nodes.find(v=>v.id===origin.node);
   if(original){
    for(const key of ['text','placeholder','options','textKey','placeholderKey','symbol','asset','fontName','value','isOn','selected','disabled','action','minimum','maximum','step','inputType']){
     if(!(n.manualFields||[]).includes(key)&&!(n.manualContent&&['text','placeholder','options'].includes(key)))n[key]=original[key];
    }
    if(source.events[origin.node])page.events[n.id]=clone(source.events[origin.node]);
   }else n.hidden=true;
  }else if(n.interaction)page.events[n.id]=clone(n.interaction);
 }
 normalizeLayerOrder(page.nodes);
 let nextOrder=page.nodes.reduce((max,n)=>Math.max(max,n.layerOrder),-1)+1;
 for(const n of extra){if(!Number.isFinite(n.layerOrder))n.layerOrder=nextOrder;nextOrder=Math.max(nextOrder,n.layerOrder+1)}
 page.nodes.push(...extra);
 // Parent-first emission keeps native containers and editor coordinate conversion valid after a layer move.
 const byID=new Map(page.nodes.map(n=>[n.id,n])),ordered=[],done=new Set(),visiting=new Set();
 function emit(n){if(done.has(n.id))return;if(visiting.has(n.id))throw Error('Layer parent cycle');visiting.add(n.id);const parent=byID.get(n.parent);if(parent)emit(parent);visiting.delete(n.id);done.add(n.id);ordered.push(n)}
 for(const n of page.nodes)emit(n);page.nodes=ordered;return presentLayers(model,session,page);
}

function presentLayers(model,session,page){
 const spec=model.pages[page.id]?.presentation;if(!spec||session.editingPage)return page;
 const c={...context(session),localization:model.localization,locale:session.locale||'en'};
 if(spec.when&&!expr(spec.when,c))return page;
 const assets=Object.fromEntries(model.assets.map(a=>[a.name,a.id]));
 for(const fallback of spec.fallbacks||[]){if(page.nodes.some(n=>n.id===fallback.id))continue;page.nodes.push({type:'image',parent:'',rotation:0,opacity:1,scale:1,hidden:false,locked:false,fit:'fit',fill:'#00000000',...fallback,asset:assets[fallback.asset]});}
 for(const rule of spec.rules||[]){
  if(rule.when&&!expr(rule.when,c))continue;
  const m=rule.match||{},targets=page.nodes.filter(n=>(!m.id||n.id===m.id)&&(!m.action||n.action===m.action)&&(!m.asset||n.asset===assets[m.asset]));
  for(const n of targets){const v=expr(rule.set||{},c);n.x+=v.offsetX||0;n.y+=v.offsetY||0;
   for(const k of ['opacity','hidden','disabled','rotation','scale','layerOrder'])if(k in v)n[k]=v[k];
   if(n.hidden||n.disabled||n.opacity===0){if(page.events[n.id])page.events[n.id].disabled=true;}
   if(rule.badge){const b=expr(rule.badge,c),w=n.width*(b.width??.65),h=n.height*(b.height??.2),dx=n.width*((b.x??.5)-.5),dy=n.height*((b.y??.25)-.5),a=(n.rotation||0)*Math.PI/180;
    page.nodes.push({...n,id:n.id+'#badge',type:'text',asset:undefined,modelAsset:undefined,paintOptions:undefined,action:'',text:String(b.text??''),x:n.x+n.width/2+dx*Math.cos(a)-dy*Math.sin(a)-w/2,y:n.y+n.height/2+dx*Math.sin(a)+dy*Math.cos(a)-h/2,width:w,height:h,scale:1,fill:'#00000000',fontSize:b.fontSize??Math.min(48,n.width*.24),fontWeight:800,color:b.color||'#082DB5',alignment:'center',fontName:undefined,lineHeight:undefined,layerOrder:(n.layerOrder||0)+.1,shadow:b.shadow||null,gradient:null});
   }
  }
 }
 return page;
}
function frame(model,session,overrides){return presentLayers(model,session,rawFrame(model,session,overrides))}

function clipsContent(n){return n.clip===true||n.type==='image'||(n.type==='scroll'&&((n.contentWidth??n.width)>n.width+0.5||(n.contentHeight??n.height)>n.height+0.5))}
function acceptsPointer(n,event,editing=false){return !n.hidden&&(editing||!!n.modelAsset||!!event?.action||String(n.id).startsWith('$shade')||['scroll','nativeButton','nativeCheckbox','nativeSwitch','nativeSlider','nativeSegment','nativeStepper','nativeTextField','nativeTextView'].includes(n.type))}
const API={normalizeLayerOrder,acceptsPointer,clipsContent,initial,reduce,frame,compose,editorFrame,applyEditor,expr,clone};global.StudioEngine=API;
if(typeof module!=='undefined')module.exports=API;
})(typeof globalThis!=='undefined'?globalThis:this);
