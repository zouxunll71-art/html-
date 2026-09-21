'use strict';
const nativeSymbols=new Map(),nativeEffects=new Set();
window.studioSymbol=(key,data)=>{nativeSymbols.set(key,data);document.querySelectorAll('img[data-symbol-key]').forEach(image=>{if(image.dataset.symbolKey===key)image.src=data})};
function requestSymbol(image,name,color){
 const key=name+'|'+color;image.dataset.symbolKey=key;image.alt='';
 if(nativeSymbols.has(key)){image.src=nativeSymbols.get(key);return}
 if(image.dataset.symbolRequested===key)return;image.dataset.symbolRequested=key;
 window.webkit?.messageHandlers.studio?.postMessage({type:'symbol',name,color,key});
}
function renderNativeChrome(p,page){
 let chrome=document.getElementById('native-chrome');if(!chrome){chrome=document.createElement('div');chrome.id='native-chrome';root.appendChild(chrome)}
 const spec=page.nativeChrome;if(!spec){chrome.replaceChildren();return}
 Object.assign(chrome.style,{position:'absolute',inset:'0',pointerEvents:'none',zIndex:10000});chrome.replaceChildren();
 const stack=spec.stack,current=stack[stack.length-1];
 function button(title,action,symbol){const b=document.createElement('button');b.title=title;b.setAttribute('aria-label',title);b.style.cssText='border:0;background:transparent;color:inherit;font:inherit;padding:6px;pointer-events:auto;';if(symbol){const img=document.createElement('img');img.width=22;img.height=22;requestSymbol(img,symbol,spec.tint);b.append(img)}else b.textContent=title;b.onclick=event=>{event.stopPropagation();if(!editMode)emit(action)};return b}
 if(!current.hidden){const bar=document.createElement('div');Object.assign(bar.style,{position:'absolute',top:Math.max(0,page.contentInsets.top-44)+'px',left:'0',width:'100%',height:'44px',background:spec.background,color:spec.tint,display:'flex',alignItems:'center',justifyContent:'space-between',padding:'0 10px',borderBottom:'1px solid #00000018'});
 const left=document.createElement('div'),title=document.createElement('strong'),right=document.createElement('div');title.textContent=current.title;title.style.color='#17212B';if(stack.length>1)left.append(button(current.backTitle||current.title,{type:'back'},'chevron.left'));
 for(const item of current.buttons)(item.side==='left'?left:right).append(button(item.title,{node:item.node},item.symbol));bar.append(left,title,right);chrome.append(bar)}
 if(spec.showTabs){const bar=document.createElement('div');Object.assign(bar.style,{position:'absolute',bottom:'0',left:'0',width:'100%',height:page.contentInsets.bottom+'px',paddingBottom:Math.max(0,page.contentInsets.bottom-49)+'px',display:'flex',background:spec.background,borderTop:'1px solid #00000018'});
 for(const tab of spec.tabs){const b=button(tab.title,{type:'tab',page:tab.page});b.style.cssText+='flex:1;display:flex;flex-direction:column;align-items:center;font-size:10px;gap:3px;';const selected=stack[0].page===tab.page,color=selected?spec.tint:'#777777';b.style.color=color;b.setAttribute('aria-selected',String(selected));b.replaceChildren();const img=document.createElement('img');img.width=22;img.height=22;requestSymbol(img,tab.symbol,color);const text=document.createElement('span');text.textContent=tab.title;b.append(img,text);bar.append(b)}chrome.append(bar)}
 // Custom dialogs sit above system chrome in the preview just as on iOS.
 const modalIDs=page.modalPages||[];for(const [id,element] of views)if(id.startsWith('$shade')||modalIDs.some(m=>id===m||id.startsWith(m+'/')))element.style.zIndex='20000';
}
function processNativeEffects(p){
 const ids=[];
 for(const effect of p.page.effects||[]){const key=p.projectID+':'+effect.id;ids.push(effect.id);if(nativeEffects.has(key))continue;nativeEffects.add(key);
  if(effect.type==='openURL')window.webkit?.messageHandlers.studio?.postMessage({type:'openURL',url:effect.url});
  if(effect.type==='share'){const blob=new Blob([effect.content],{type:effect.mime||'text/plain'}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=effect.filename;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
 }
 if(ids.length)api('/ack-effects',{side:'web',projectID:p.projectID,ids}).catch(()=>{});
}
