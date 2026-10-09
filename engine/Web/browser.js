'use strict';
// Uses the exact same DOM renderer and source records as the workbench.
// This host shim replaces only the native window services.
const notice=document.createElement('div');
notice.setAttribute('role','alert');notice.hidden=true;
notice.style.cssText='position:fixed;inset:12px 16px auto;padding:10px 12px;background:#fff1ec;color:#9e2d13;z-index:2147483647;font:13px -apple-system,sans-serif;white-space:pre-wrap';
document.body.append(notice);
const showError=message=>{notice.textContent=message||'';notice.hidden=!message};
const style=document.createElement('style');style.textContent='body{background:#ececec}#error{max-width:calc(100vw - 32px);left:16px;white-space:pre-wrap}#phone-stage{margin-top:12px}#screen{transform:none!important}#bar{width:calc(100% - 60px)}#home{left:50%;transform:translateX(-50%)}';document.head.append(style);
const originalFetch=window.fetch.bind(window);
window.fetch=async (url,options={})=>{
 const target=new URL(url,location.href);
 if(target.origin===location.origin){const headers=new Headers(options.headers);headers.set('X-Studio-Token',TOKEN);options={...options,headers}}
 const response=await originalFetch(url,options);
 if(target.origin===location.origin&&target.pathname==='/runtime'&&response.ok){
  const value=await response.clone().json();
  if(value.browserInfo){
   showError(value.browserInfo.error?'源码有错误，保留上次页面：'+value.browserInfo.error:'');
  }
 }
 return response;
};
window.webkit={messageHandlers:{studio:{postMessage(message){
 if(message.type==='symbol'){
  const url='/browser-symbol?'+new URLSearchParams({name:message.name,color:message.color,token:TOKEN});
  // Do not let a missing host icon silently look like a valid empty element.
  originalFetch(url).then(r=>{if(!r.ok)throw Error('图标加载失败：'+message.name);return r.blob()}).then(blob=>window.studioSymbol(message.key,URL.createObjectURL(blob))).catch(e=>showError(e.message));
 }
 if(message.type==='openURL'){
  try{const url=new URL(message.url);if(['https:','http:','mailto:'].includes(url.protocol))window.open(url.href,'_blank','noopener,noreferrer')}catch{}
 }
}}}};
async function start(){
 if(!TOKEN)throw Error('请用项目的浏览器预览命令打开，此地址尚未绑定项目。');
 for(const path of ['/engine.js','/native-ui.js','/preview.js'])await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src=path+'?token='+encodeURIComponent(TOKEN);script.onload=resolve;script.onerror=()=>reject(Error('预览加载失败，请重新运行项目预览命令'));document.head.append(script)});
 const layout=()=>{
  // Keep source coordinates at 1 CSS pixel each. The native host normalizes
  // to 402 then scales its window; this browser must not repeat both scales.
  const width=parseFloat(root.style.width)||402,height=parseFloat(root.style.height)||874;
  const css=document.documentElement.style;
  css.setProperty('--iphone-17-pro-width',width+'px');css.setProperty('--iphone-17-pro-height',height+'px');
  css.setProperty('--phone-frame-width',(width+32)+'px');css.setProperty('--phone-frame-height',(height+32)+'px');
  const stageWidth=width+54,stageHeight=height+36;
  const scale=Math.max(.05,Math.min(1,(innerWidth-24)/stageWidth,(innerHeight-24)/stageHeight));
  const stage=document.getElementById('phone-stage');stage.style.width=stageWidth+'px';stage.style.height=stageHeight+'px';stage.style.transform=`scale(${scale})`;
  stage.style.left=(Math.round(Math.max(0,(innerWidth-stageWidth*scale)/2)*(devicePixelRatio||1))/(devicePixelRatio||1))+'px';
  stage.dataset.displayScale=String(scale);
 };
 addEventListener('resize',layout);layout();
 // The shared renderer resizes after every changed page.
 new MutationObserver(layout).observe(document.getElementById('screen'),{attributes:true,attributeFilter:['style']});
}
start().catch(e=>showError(e.message));
