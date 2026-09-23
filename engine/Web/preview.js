'use strict';
let payload=null,revision=-1,busy=false,pollPending=false,sending=Promise.resolve(),views=new Map(),editMode=true,lastAnimationID=null,sourceSelection=null;
window.studioSelect=id=>{sourceSelection=id;for(const [key,v] of views)v.style.outline=key===id&&editMode ? "2px solid #235BDE":"none"};
const root=document.getElementById('screen'),error=document.getElementById('error');
function api(path,body){return fetch(path,{method:body?'POST':'GET',headers:{'X-Studio-Token':TOKEN,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined}).then(async r=>{let v=await r.json();if(!r.ok)throw Error(v.error);return v})}
function emit(event){const request={side:'web',event,eventID:crypto.randomUUID(),projectID:payload?.projectID,pageID:payload?.page.id};sending=sending.then(()=>api('/event',request)).then(()=>poll(true)).catch(e=>{error.textContent=e.message;error.style.display='block'})}
function render(p){const animate=!matchMedia('(prefers-reduced-motion: reduce)').matches&&p.page.animation&&lastAnimationID!==p.page.animationID;lastAnimationID=p.page.animationID;const motion=animate?p.page.animation:null;payload=p;editMode=p.editing;const page=p.page,ids=new Set(page.nodes.map(n=>n.id));
for(const [id,v] of views)if(!ids.has(id)){if(motion){v.style.pointerEvents='none';v.animate([{opacity:v.style.opacity},{opacity:0}],{duration:1000*motion.duration,delay:1000*(motion.delay||0)}).finished.finally(()=>v.remove())}else v.remove();views.delete(id)}
for(const [nodeIndex,n] of page.nodes.entries()){let v=views.get(n.id),tag=n.modelAsset?'div':n.type==='image'?'img':n.type==='nativeSegment'||n.type==='nativeStepper'?'div':n.type==='nativeTextField'?'input':n.type==='nativeTextView'?'textarea':n.type==='nativeButton'||n.type==='nativeCheckbox'?'button':n.type==='nativeSwitch'||n.type==='nativeSlider'?'input':'div';
if(!v||v.tagName.toLowerCase()!==tag){if(v)v.remove();v=document.createElement(tag);views.set(n.id,v);v.dataset.kind=n.type;v.dataset.node=n.id;if(motion)v.animate([{opacity:0},{opacity:n.opacity}],{duration:1000*motion.duration,delay:1000*(motion.delay||0),fill:'backwards'});
v.onclick=e=>{e.stopPropagation();if(editMode){window.studioSelect(n.id);window.webkit?.messageHandlers.studio?.postMessage({type:'select',id:n.id});return}if(n.modelAsset)return;const d=payload.page.events[n.id];if(d?.disabled)return;if(n.type==='nativeCheckbox')emit({node:n.id,value:!payload.page.nodes.find(x=>x.id===n.id).isOn});else if(n.type==='nativeSegment'||n.type==='nativeStepper'||n.type==='nativeSwitch'||n.type==='nativeSlider'||n.type==='nativeTextField'||n.type==='nativeTextView')return;else if(d?.action)emit({node:n.id})};
v.oninput=()=>{if(!editMode)emit({node:n.id,value:n.type==='nativeSwitch'?v.checked:['nativeSlider','nativeStepper','nativeSegment'].includes(n.type)?Number(v.value):v.value})};
if(n.type==='scroll'){let timer;v.onscroll=()=>{if(v._setting)return;v._scrollingUntil=performance.now()+200;clearTimeout(timer);timer=setTimeout(()=>emit({type:'scroll',node:n.id,x:v.scrollLeft,y:v.scrollTop}),100)}}}
let pointerStart=null;v.onpointerdown=e=>{if(!editMode)return;e.stopPropagation();pointerStart={x:e.clientX,y:e.clientY,id:e.pointerId};v.setPointerCapture(e.pointerId)};v.onpointercancel=()=>pointerStart=null;v.onpointerup=e=>{if(!pointerStart)return;const start=pointerStart;pointerStart=null;if(editMode&&Math.hypot(e.clientX-start.x,e.clientY-start.y)>10&&e.clientX<0){window.webkit?.messageHandlers.studio?.postMessage({type:'resourceDrop',id:n.id,projectID:payload.projectID,signature:payload.sourceSignature,x:e.clientX,y:e.clientY})}};
v.draggable=editMode;v.ondragstart=e=>{if(!editMode){e.preventDefault();return}e.stopPropagation();window.studioSelect(n.id);window.webkit?.messageHandlers.studio?.postMessage({type:'select',id:n.id});e.dataTransfer.effectAllowed='copy';e.dataTransfer.setData('text/plain','html-node:'+JSON.stringify({projectID:payload.projectID,signature:payload.sourceSignature,node:n.id}));const ghost=v.cloneNode(!['container','scroll'].includes(n.type));ghost.style.outline='none';ghost.style.position='fixed';ghost.style.left='0';ghost.style.top='0';ghost.style.pointerEvents='none';ghost.style.transform=`scale(${Math.min(1,160/n.width,160/n.height)})`;ghost.style.transformOrigin='top left';document.body.append(ghost);e.dataTransfer.setDragImage(ghost,8,8);setTimeout(()=>ghost.remove(),0)};
v.style.zIndex=String(nodeIndex);const parent=views.get(n.parent)||root;if(v.parentNode!==parent)parent.appendChild(v);
const font=n.fontName?`"${n.fontName}"`:n.fontFamily==='serif'?'serif':n.fontFamily==='monospace'?'monospace':n.fontFamily==='cursive'?'cursive':'-apple-system';
Object.assign(v.style,{position:'absolute',left:n.x+'px',top:n.y+'px',width:n.width+'px',height:n.height+'px',color:n.color,background:n.fill,opacity:n.opacity,border:`${n.strokeWidth}px solid ${n.strokeColor}`,borderRadius:n.cornerRadius+'px',fontFamily:font,fontSize:n.fontSize+'px',fontWeight:n.fontWeight,textAlign:n.alignment,whiteSpace:'pre-wrap',lineHeight:n.lineHeight?n.lineHeight+'px':'normal',letterSpacing:(n.letterSpacing||0)+'px',transform:`rotate(${n.rotation}deg) scale(${n.scale||1})`,overflow:StudioEngine.clipsContent(n)?(n.type==='scroll'?'auto':'hidden'):'visible',pointerEvents:StudioEngine.acceptsPointer(n,page.events[n.id],editMode)?'auto':'none',display:n.hidden?'none':'block',padding:'0',margin:'0',transition:motion?`all ${motion.duration||.25}s ${motion.curve==='linear'?'linear':motion.curve==='spring'?'cubic-bezier(.2,.8,.2,1.08)':'ease-in-out'} ${motion.delay||0}s`:'none'});
if(n.gradient){const g=n.gradient,start=g.start||[0,0],end=g.end||[0,1],angle=90+Math.atan2((end[1]-start[1])*n.height,(end[0]-start[0])*n.width)*180/Math.PI;v.style.backgroundImage=`linear-gradient(${angle}deg,${g.colors.map((c,i)=>c+' '+((g.locations?.[i]??i/(g.colors.length-1))*100)+'%').join(',')})`}else v.style.backgroundImage='none';
if(n.shadow)v.style.boxShadow=`${n.shadow.x||0}px ${n.shadow.y||0}px ${n.shadow.blur||0}px ${n.shadow.color||'#00000033'}`;else v.style.boxShadow='none';
if(n.modelAsset){
 const identity=p.projectID+':'+n.modelAsset+':'+(n.paintOptions?.work||'draft');
 if(v._modelKey!==identity){v._paint?.dispose();v._paint=null;v._modelKey=identity;const loading=document.createElement('span');loading.textContent=p.page.locale==='zh-Hans'?'加载模型…':'Loading model…';v.replaceChildren(loading);
 Promise.resolve(window.StudioModelPainting).then(({ModelPaint})=>{if(v._modelKey!==identity||!v.isConnected)return;const instance=new ModelPaint(v,{locale:p.session?.locale||'en',project:p.projectID,asset:n.modelAsset,onSave:id=>emit({node:n.id,value:id}),onAnalysis:value=>emit({node:n.id+'#analysis',value})});v._paint=instance;instance.update(n,editMode);return instance.load('/asset?project='+encodeURIComponent(p.projectID)+'&id='+encodeURIComponent(n.modelAsset)+'&token='+encodeURIComponent(TOKEN),p.projectID+':'+(n.paintOptions?.work||('draft:'+n.modelAsset)))}).catch(e=>{if(v.isConnected){const msg=v.querySelector('div');if(msg)msg.textContent=e.message;else v.textContent=e.message}});
 }else v._paint?.update(n,editMode);
}
else if(n.type==='path'||n.type==='model'){
 let canvas=v.querySelector('canvas');if(!canvas){canvas=document.createElement('canvas');canvas.style.cssText='width:100%;height:100%;pointer-events:none';v.replaceChildren(canvas)}
 const ratio=devicePixelRatio||1;canvas.width=Math.ceil(n.width*ratio);canvas.height=Math.ceil(n.height*ratio);const ctx=canvas.getContext('2d');ctx.scale(ratio,ratio);ctx.clearRect(0,0,n.width,n.height);
 function draw(points,color,closed,fill){ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(p[0]*n.width,p[1]*n.height):ctx.moveTo(p[0]*n.width,p[1]*n.height));if(closed)ctx.closePath();if(fill){ctx.fillStyle=fill;ctx.fill()}if(color){ctx.strokeStyle=color;ctx.lineWidth=n.strokeWidth||2;ctx.lineJoin='round';ctx.stroke()}}
 if(n.mesh)n.mesh.forEach(face=>draw(face.points,null,true,face.color));else draw(n.points,n.color,n.closed,n.closed?n.fill:null);
}
else if(n.type==='image'&&n.symbol){requestSymbol(v,n.symbol,n.color);v.style.objectFit='contain'}
else if(n.type==='image'){delete v.dataset.symbolKey;delete v.dataset.symbolRequested;const url=`/asset?project=${p.projectID}&id=${n.asset}&token=${TOKEN}`;if(v.getAttribute('src')!==url)v.src=url;v.style.objectFit=n.fit==='fill'?'cover':n.fit==='stretch'?'fill':'contain'}
else if(['nativeTextField','nativeTextView'].includes(n.type)){if(v.value!==n.text&&document.activeElement!==v)v.value=n.text;v.onblur=()=>{if(payload)render(payload)};v.placeholder=n.placeholder;v.readOnly=editMode;if(n.type==='nativeTextField')v.type=n.inputType==='password'?'password':n.inputType==='number'?'number':'text'}
else if(n.type==='nativeSwitch'){v.type='checkbox';v.checked=n.isOn;v.disabled=editMode||n.disabled}
else if(n.type==='nativeSlider'){v.type='range';v.min=n.minimum;v.max=n.maximum;v.step='any';v.value=n.value;v.disabled=editMode||n.disabled}
else if(n.type==='nativeSegment'||n.type==='nativeStepper'){
 const options=n.type==='nativeSegment'?(n.options||[]):['−','+'];v.style.display='flex';v.style.alignItems='stretch';v.style.padding='2px';v.style.gap='2px';v.style.background='#E7E7EC';v.style.borderRadius='9px';
 if(v.children.length!==options.length||v._options!==JSON.stringify(options)){v._options=JSON.stringify(options);v.replaceChildren(...options.map((title,i)=>{const button=document.createElement('button');button.textContent=title;button.style.cssText='flex:1;border:0;border-radius:7px;font:inherit;color:inherit;padding:0;';button.onclick=e=>{e.stopPropagation();if(editMode){window.studioSelect(n.id);window.webkit?.messageHandlers.studio?.postMessage({type:'select',id:n.id});return}const now=payload.page.nodes.find(x=>x.id===n.id);if(now.disabled)return;emit({node:n.id,value:n.type==='nativeSegment'?i:Math.max(now.minimum,Math.min(now.maximum,now.value+(i?1:-1)*(now.step||1)))})};return button}))}
 [...v.children].forEach((button,i)=>{button.disabled=n.disabled;button.style.background=n.type==='nativeSegment'&&i===n.value?'white':'transparent';button.style.boxShadow=n.type==='nativeSegment'&&i===n.value?'0 1px 3px #0002':'none'});
}
else if(n.type==='nativeSpinner'){v.textContent='';v.style.border=`2px solid ${n.color}33`;v.style.borderTopColor=n.color;v.style.borderRadius='50%';if(!v._spinner)v._spinner=v.animate([{transform:'rotate(0deg)'},{transform:'rotate(360deg)'}],{duration:850,iterations:Infinity})}
else if(n.type==='nativeProgress'){v.textContent='';v.style.background=`linear-gradient(to right, ${n.color} ${100*n.value}%, #e8e8e8 0)`}
else if(n.type==='nativeCheckbox'){v.disabled=n.disabled;v.setAttribute('role','checkbox');v.setAttribute('aria-checked',String(n.isOn));v.style.display='flex';v.style.alignItems='center';v.style.gap='5px';if(v.children.length!==2){v.replaceChildren(document.createElement('img'),document.createElement('span'))}const icon=v.children[0];icon.width=n.fontSize;icon.height=n.fontSize;requestSymbol(icon,n.isOn?'checkmark.square.fill':'square',n.color);v.children[1].textContent=n.text}
else if(['text','nativeButton'].includes(n.type)){if(n.textSpans?.length){const key=JSON.stringify([n.text,n.textSpans]);if(v._rich!==key){v._rich=key;const bounds=[...new Set([0,n.text.length,...n.textSpans.flatMap(x=>[x.start,x.end])])].sort((a,b)=>a-b);v.replaceChildren(...bounds.slice(0,-1).map((a,i)=>{const b=bounds[i+1],span=document.createElement('span');span.textContent=n.text.slice(a,b);for(const st of n.textSpans.filter(x=>x.start<=a&&x.end>=b)){if(st.color)span.style.color=st.color;if(st.fontSize)span.style.fontSize=st.fontSize+'px';if(st.fontWeight)span.style.fontWeight=st.fontWeight;if(st.italic)span.style.fontStyle='italic';if(st.underline)span.style.textDecoration='underline'}return span}))}}else{v._rich=null;if(v.textContent!==n.text||v.children.length)v.textContent=n.text}v.disabled=n.disabled}
v.setAttribute('aria-selected',String(!!n.selected));if(n.type==='nativeButton')v.setAttribute('aria-pressed',String(!!n.selected));
if(n.type==='scroll'&&performance.now()>(v._scrollingUntil||0)){v._setting=true;v.scrollLeft=n.scrollX;v.scrollTop=n.scrollY;requestAnimationFrame(()=>v._setting=false)}
}
let fontStyle=document.getElementById('fonts');if(!fontStyle){fontStyle=document.createElement('style');fontStyle.id='fonts';document.head.appendChild(fontStyle)}
const css=p.assets.filter(a=>a.kind==='font').map(a=>`@font-face{font-family:"${a.postscript}";src:url('/asset?project=${p.projectID}&id=${a.id}&token=${TOKEN}')}`).join('');if(fontStyle.textContent!==css)fontStyle.textContent=css;
renderNativeChrome(p,page);processNativeEffects(p);window.studioSelect(sourceSelection);root.style.width=page.width+'px';root.style.height=page.height+'px';root.style.transform=`scale(${402/page.width})`;resizePhone();api('/ack',{side:'web',revision:p.revision});window.webkit?.messageHandlers.studio?.postMessage({type:'rendered',revision:p.revision,route:page.id});}
async function poll(force=false){
 if(busy){if(force)pollPending=true;return}busy=true;
 try{
  const query=new URLSearchParams({side:'web',after:String(force?-1:revision),project:payload?.projectID||'',model:payload?.modelHash||''});
  let p=await api('/runtime?'+query);
  if(p.reuseModel){
   if(p.projectID!==payload?.projectID||p.modelHash!==payload?.modelHash){revision=-1;payload=null;pollPending=true;return}
   p={...p,model:payload.model,assets:payload.assets};
  }
  if(p.page&&p.model&&p.revision>=revision){revision=p.revision;render(p)}
  error.style.display='none';
 }catch(e){error.textContent=e.message;error.style.display='block'}
 finally{busy=false;if(pollPending){pollPending=false;void poll(true)}}
}
setInterval(poll,150);function resizePhone(){document.getElementById('phone-stage').style.transform=`scale(${Math.min(innerWidth/456,innerHeight/910)})`}addEventListener('resize',resizePhone);resizePhone();poll();

// Command+W toggles studio mode, but never steals a character from an editable field or IME.
document.addEventListener('keydown',event=>{
 if(event.code!=='KeyW'||!event.metaKey||event.repeat||event.isComposing||event.ctrlKey||event.altKey||event.shiftKey)return;
 const element=document.activeElement;
 if(element?.isContentEditable||((element?.tagName==='INPUT'||element?.tagName==='TEXTAREA')&&!element.readOnly&&!element.disabled))return;
 if(!window.webkit?.messageHandlers.studio)return;
 event.preventDefault();event.stopPropagation();window.webkit.messageHandlers.studio.postMessage({type:'toggleMode'});
});

// Editing tool shortcuts leave text fields and IME input untouched.
document.addEventListener('keydown',event=>{
 const tool={KeyA:'move',KeyS:'resize',KeyD:'rotate'}[event.code];
 if(!tool||!event.metaKey||event.ctrlKey||event.altKey||event.shiftKey!==(event.code==='KeyS')||event.repeat||event.isComposing)return;
 const element=document.activeElement;
 if(element?.isContentEditable||((element?.tagName==='INPUT'||element?.tagName==='TEXTAREA')&&!element.readOnly&&!element.disabled))return;
 if(!editMode||!window.webkit?.messageHandlers.studio)return;
 event.preventDefault();event.stopPropagation();window.webkit.messageHandlers.studio.postMessage({type:'editorTool',tool});
},true);
