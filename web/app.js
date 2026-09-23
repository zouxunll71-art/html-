import { groupConversation, userMessageText } from './conversation-groups.js';
import { installAnnotation } from './annotation.js';
const $ = id => document.getElementById(id);
const token = document.querySelector('meta[name="client-token"]').content;
const nativeHost = new URLSearchParams(location.search).get('native') === '1';
if (nativeHost) document.documentElement.classList.add('native-host');
let leftPanelMode = 'projects', rightPanelMode = 'chat', lastLeftPanel='projects';
let previewZoom=Number(localStorage.getItem('studio-zoom')||0.8), previewFit=true;
const nativeMessage = message => window.webkit?.messageHandlers?.native?.postMessage(message);
let lastNativeLayout='';
window.reportNativeLayout = (force=false) => {
  if (!nativeHost) return;
  const bounds = el => { const r = el.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; };
  const layout={ action:'layout', center:bounds(document.querySelector('.canvas-layout')), left:bounds(document.querySelector('.sidebar')), right:bounds(document.querySelector('.chat-panel')), leftMode:leftPanelMode,leftNative:['library','tools'].includes(leftPanelMode),rightNative:rightPanelMode==='properties',preview:!!project()&&project().nativePreview!==false,modal:!!window.imageViewerActive||!!window.annotationActive||$('dialog').open||!$('sidebar-menu').classList.contains('hidden') };
  const folderDrop=$('project-folder-drop');layout.composerDrop=layout.modal?null:bounds(document.querySelector('.composer-wrap'));layout.projectDrop=$('dialog').open&&folderDrop?{...bounds(folderDrop),requestId:folderDrop.dataset.requestId}:null;
  const key=JSON.stringify(layout);if(force===true||key!==lastNativeLayout){lastNativeLayout=key;nativeMessage(layout)}
};
window.setClientPanel = (side, mode) => {
  if (project()?.nativePreview!==true && (['library','tools'].includes(mode)||mode==='properties')) {
    toast('此 Codex 项目尚未导入手机工作台，可使用对话编辑项目文件');
    mode=side==='left'?'projects':'chat';
  }
  if (side==='left') {leftPanelMode=mode;if(mode!=='hidden')lastLeftPanel=mode;} else rightPanelMode=mode;
  document.documentElement.classList.toggle('left-hidden',leftPanelMode==='hidden'); document.documentElement.classList.toggle('right-hidden',rightPanelMode==='hidden');
  document.documentElement.classList.toggle('left-native',['library','tools'].includes(leftPanelMode)); document.documentElement.classList.toggle('right-native',rightPanelMode==='properties');
  $('left-tools').classList.toggle('selected',leftPanelMode==='tools'); $('left-projects').classList.toggle('selected',leftPanelMode==='projects'); $('left-library').classList.toggle('selected',leftPanelMode==='library');
  $('right-chat').classList.toggle('selected',rightPanelMode==='chat'); $('right-properties').classList.toggle('selected',rightPanelMode==='properties');
  $('toggle-left').setAttribute('aria-label',leftPanelMode==='hidden'?'显示左侧栏':'收起左侧栏'); $('toggle-right').setAttribute('aria-label',rightPanelMode==='hidden'?'显示右侧栏':'收起右侧栏');
  if (!nativeHost && side==='right') { $('inspector').classList.toggle('hidden',mode!=='properties'); if(mode==='properties')renderInspector(); }
  if (!nativeHost && side==='left' && ['library','tools'].includes(mode)) { toast('完整页面、资源与组件库在桌面客户端中使用'); leftPanelMode='projects';document.documentElement.classList.remove('left-native'); }
  localStorage.setItem('studio-panels',JSON.stringify({left:leftPanelMode,right:rightPanelMode}));
  requestAnimationFrame(window.reportNativeLayout);
};
new ResizeObserver(() => window.reportNativeLayout()).observe(document.querySelector('.app'));
new ResizeObserver(() => window.reportNativeLayout()).observe($('dialog'));
new ResizeObserver(() => window.reportNativeLayout()).observe(document.querySelector('.composer-wrap'));
new MutationObserver(() => window.reportNativeLayout()).observe($('dialog'),{attributes:true,attributeFilter:['open']});
addEventListener('resize',window.reportNativeLayout);
$('toggle-left').onclick=()=>window.setClientPanel('left',leftPanelMode==='hidden'?lastLeftPanel:'hidden');
$('toggle-right').onclick=()=>window.setClientPanel('right',rightPanelMode==='hidden'?'chat':'hidden');
$('left-tools').onclick=()=>window.setClientPanel('left','tools'); $('left-projects').onclick=()=>window.setClientPanel('left','projects'); $('left-library').onclick=()=>window.setClientPanel('left','library');
$('right-chat').onclick=()=>window.setClientPanel('right','chat'); $('right-properties').onclick=()=>window.setClientPanel('right','properties');
const zoomControls=document.createElement('div');zoomControls.className='preview-zoom';zoomControls.innerHTML='<button id="zoom-out" class="icon-btn" aria-label="缩小预览" title="缩小预览"><i data-lucide="minus"></i></button><span id="zoom-value">自动</span><button id="zoom-in" class="icon-btn" aria-label="放大预览" title="放大预览"><i data-lucide="plus"></i></button><button id="zoom-fit" class="subtle">适合窗口</button>';
document.querySelector('.topbar-center').prepend(zoomControls);
function applyZoom(fit=false){previewFit=fit;$('zoom-value').textContent=fit?'自动':Math.round(previewZoom*100)+'%';nativeMessage({action:'zoom',value:previewZoom,fit});document.documentElement.style.setProperty('--preview-height',Math.round(910*previewZoom)+'px');document.documentElement.classList.toggle('zoomed-preview',!fit);localStorage.setItem('studio-zoom',String(previewZoom))}
$('zoom-in').onclick=()=>{previewZoom=Math.min(1.5,previewZoom+.1);applyZoom()};$('zoom-out').onclick=()=>{previewZoom=Math.max(.35,previewZoom-.1);applyZoom()};$('zoom-fit').onclick=()=>applyZoom(true);
const state = { projects: [], conversations: [], project: null, thread: null, items: new Map(), running: {}, requests: new Map(), attachments: [], models: [], editing: true, editor: null, selected: null, ready: false, switching: false, pendingSend: false, remoteRunning: {}, selectedSkills: [], sequence: 0 };
let usage=null, usageBusy=false, lastUsageRead=0;
const usageButton=document.createElement('button');usageButton.type='button';usageButton.id='usage';usageButton.className='usage-button';usageButton.textContent='额度读取中';usageButton.setAttribute('aria-label','查看使用额度');$('model-picker').before(usageButton);
const windowLabel=minutes=>minutes===10080?'每周额度':minutes===300?'5 小时额度':minutes==null?'额度周期':minutes>=1440?`${Math.round(minutes/1440)} 天额度`:`${Math.round(minutes/60*10)/10} 小时额度`;
function usageBucket(){return usage?.buckets.find(b=>b.model && b.model===$('model').value)||usage?.buckets.find(b=>b.id==='codex')||usage?.buckets[0]}
function renderUsage(){const bucket=usageBucket(), windows=bucket?.windows||[];usageButton.textContent=windows.length?`剩余 ${Math.round(Math.min(...windows.map(w=>w.remaining)))}%`:'额度暂不可用';usageButton.title=windows.length?windows.map(w=>`${windowLabel(w.minutes)}：剩余 ${Math.round(w.remaining)}%`).join('\n'):'点击重试读取账户额度';usageButton.classList.toggle('low',windows.length>0&&Math.min(...windows.map(w=>w.remaining))<=10)}
async function refreshUsage(){if(usageBusy || Date.now()-lastUsageRead<10000)return;usageBusy=true;lastUsageRead=Date.now();try{usage=await api('/api/usage');renderUsage()}catch{usageButton.textContent='额度暂不可用';usageButton.title='额度读取失败，点击重试'}finally{usageBusy=false}}
usageButton.onclick=attempt(async()=>{await refreshUsage();const buckets=usage?.buckets||[];showDialog('使用额度',`<p class="dialog-description">账号共享额度 · ${usageBucket()?.plan?.toUpperCase()||'Codex'}<br>这里显示剩余额度，随使用情况自动更新。</p>${buckets.map(b=>`<div class="usage-group"><strong>${escape(b.name)}</strong>${b.windows.map(w=>`<div class="settings-row"><div>${windowLabel(w.minutes)}<small>${w.resetsAt?new Date(w.resetsAt*1000).toLocaleString('zh-CN',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'})+' 重置':'重置时间暂不可用'}</small></div><strong>${Math.round(w.remaining)}%</strong></div><div class="usage-track"><span style="width:${w.remaining}%"></span></div>`).join('')||'<p class="inspector-note">此额度周期数据暂不可用</p>'}</div>`).join('')||'<p>暂时无法取得额度，请稍后重试。</p>'}${usage?.ordinaryUsageAllowed===false?'<p class="form-error">当前账户的常规额度暂不可用。</p>':''}<p class="inspector-note">${usage?'更新于 '+new Date(usage.updatedAt).toLocaleTimeString('zh-CN'):''}</p>`,'关闭',async()=>{})});
const escape = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const icon = name => `<i data-lucide="${name}"></i>`;
const icons = () => { if(!document.querySelector('i[data-lucide]'))return;lucide.createIcons({ attrs: { 'aria-hidden': 'true' } });document.querySelectorAll('svg[data-lucide]').forEach(el=>el.removeAttribute('data-lucide')); };
async function api(url, body) {
  const response = await fetch(url, { method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json', 'X-Client-Token': token }, body: body === undefined ? undefined : JSON.stringify(body) });
  const result = await response.json(); if (!response.ok) throw new Error(result.error || `请求失败 (${response.status})`); return result;
}
const previewId=()=>project()?.nativeProjectId||state.project;
const studio = (url, body) => {const mapped=body?{...body}:body;if(mapped?.id===state.project)mapped.id=previewId();if(mapped?.projectID===state.project)mapped.projectID=previewId();return api('/studio'+url,mapped)};
let toastTimer;
function toast(message, error = false) { $('toast').textContent = message; $('toast').className = 'toast' + (error ? ' error' : ''); clearTimeout(toastTimer); toastTimer = setTimeout(() => $('toast').classList.add('hidden'), error ? 8500 : 4500); }
function attempt(fn) { return async (...args) => { try { return await fn(...args); } catch (error) { toast(error.message, true); } }; }
function project() { return state.projects.find(p => p.id === state.project); }
function currentConversation() { return state.conversations.find(c => c.id === state.thread); }
let sidebarPrefs;try{sidebarPrefs=JSON.parse(localStorage.getItem('studio-sidebar')||'{}')}catch{sidebarPrefs={}}
let expandedProjects=false,expandedRecent=false,projectSectionOpen=sidebarPrefs.projectSectionOpen!==false,recentSectionOpen=sidebarPrefs.recentSectionOpen!==false;
const expandedProjectIds=new Set(sidebarPrefs.expandedProjectIds||[]);
const saveSidebarPrefs=()=>localStorage.setItem('studio-sidebar',JSON.stringify({projectSectionOpen,recentSectionOpen,expandedProjectIds:[...expandedProjectIds]}));
function rowButton(label,iconName,action,id){return `<button type="button" class="row-action" data-action="${action}" data-id="${escape(id)}" title="${escape(label)}" aria-label="${escape(label)}">${icon(iconName)}</button>`;}
function threadRow(c){return `<div class="sidebar-row thread-item ${c.id===state.thread?'selected':''}"><button class="row-main" data-thread="${c.id}" title="${escape(c.title)}"><span class="row-title">${escape(c.title)}</span>${state.running[c.id]?'<span class="busy-dot"></span>':''}</button><div class="row-actions">${rowButton(c.pinned?'取消置顶':'置顶',c.pinned?'pin-off':'pin','pin',c.id)}${rowButton('归档','archive','archive',c.id)}${rowButton('对话菜单','ellipsis','thread-menu',c.id)}</div></div>`;}
function sidebarMarkup(id,html){const el=$(id);if(el._sidebarMarkup===html)return;el._sidebarMarkup=html;el.innerHTML=html;}
function renderSidebar() {
  const conversations=state.conversations.filter(c=>!c.archived),pinned=conversations.filter(c=>c.pinned);
  $('pinned-section').classList.toggle('hidden',!pinned.length);sidebarMarkup('pinned-threads',pinned.map(threadRow).join(''));
  const visibleProjects=expandedProjects?state.projects:state.projects.slice(0,5);
  sidebarMarkup('projects',projectSectionOpen?visibleProjects.map(p=>`<div class="sidebar-row project-item ${p.id===state.project&&!state.thread?'selected':''}"><button class="row-main" data-project="${p.id}" title="${escape(p.sourcePath)}" aria-expanded="${expandedProjectIds.has(p.id)}">${icon(expandedProjectIds.has(p.id)?'folder-open':'folder')}<span class="row-title">${escape(p.name)}</span></button><div class="row-actions">${rowButton('项目菜单：'+p.name,'ellipsis','project-menu',p.id)}${rowButton('新对话：'+p.name,'square-pen','project-new',p.id)}</div></div>${expandedProjectIds.has(p.id)?`<div class="project-threads">${conversations.filter(c=>c.projectId===p.id).map(threadRow).join('')||'<div class="no-thread">暂无对话</div>'}</div>`:''}`).join(''):'');
  $('show-projects').classList.toggle('hidden',!projectSectionOpen||state.projects.length<=5);$('show-projects').textContent=expandedProjects?'收起显示':'展开显示';
  $('project-section-toggle').setAttribute('aria-expanded',String(projectSectionOpen));
  const recent=conversations.filter(c=>!c.pinned).sort((a,b)=>(b.updatedAt||b.createdAt)-(a.updatedAt||a.createdAt));
  sidebarMarkup('recent-threads',recentSectionOpen?(expandedRecent?recent:recent.slice(0,10)).map(threadRow).join(''):'');
  $('show-recent').classList.toggle('hidden',!recentSectionOpen||recent.length<=10);$('show-recent').textContent=expandedRecent?'收起显示':'显示更多';
  $('recent-section-toggle').setAttribute('aria-expanded',String(recentSectionOpen));
  document.querySelector('.sidebar').querySelectorAll('[data-project]').forEach(b=>b.onclick=attempt(async()=>{const id=b.dataset.project;if(expandedProjectIds.has(id))expandedProjectIds.delete(id);else expandedProjectIds.add(id);saveSidebarPrefs();if(id!==state.project)await selectProject(id);else renderSidebar()}));
  document.querySelector('.sidebar').querySelectorAll('[data-thread]').forEach(b=>b.onclick=attempt(()=>selectThread(b.dataset.thread)));
  document.querySelector('.sidebar').querySelectorAll('[data-action]').forEach(b=>b.onclick=attempt(async e=>{e.stopPropagation();const id=b.dataset.id,c=state.conversations.find(c=>c.id===id);switch(b.dataset.action){
    case 'pin':await api('/api/thread/pin',{id,pinned:!c.pinned});await refreshRegistry(true);break;
    case 'archive':await archiveThread(id);break;
    case 'project-new':await newProjectThread(id);break;
    case 'project-menu':showProjectMenu(id,b);break;
    case 'thread-menu':showThreadMenu(id,b);break;
  }}));
  const p=project(),c=currentConversation();$('project-title').textContent=p?.name||'工作台';$('canvas-title').textContent=p?.name||'你的 App，在这里成形';
  $('thread-title').textContent=c?.title||'新的开始';$('composer-context').textContent=c?.title||'新对话';
  const nativePreview=!!p&&p.nativePreview!==false;document.documentElement.classList.toggle('code-project',!nativePreview);
  if(!nativePreview){if(['library','tools'].includes(leftPanelMode))window.setClientPanel('left','projects');if(rightPanelMode==='properties')window.setClientPanel('right','chat');}
  $('code-project-title').textContent=p?.name||c?.title||'Codex 对话';$('code-project-path').textContent=p?.sourcePath||c?.sourcePath||'';
  $('sidebar-sync-state').textContent='与 Codex 同步';
  icons();if(nativeHost&&nativePreview)nativeMessage({action:'project',id:previewId()});window.reportNativeLayout();
}
function closeSidebarMenu(){$('sidebar-menu').classList.add('hidden');window.reportNativeLayout()}
function showSidebarMenu(anchor,entries){const menu=$('sidebar-menu');menu.innerHTML=entries.map((entry,i)=>`<button type="button" role="menuitem" data-menu-index="${i}">${icon(entry.icon)}<span>${escape(entry.label)}</span></button>`).join('');menu.classList.remove('hidden');const r=anchor.getBoundingClientRect();menu.style.left=Math.min(r.left,innerWidth-250)+'px';menu.style.top=Math.min(r.bottom+4,innerHeight-menu.offsetHeight-12)+'px';menu.querySelectorAll('button').forEach(b=>b.onclick=attempt(async()=>{closeSidebarMenu();await entries[Number(b.dataset.menuIndex)].run()}));icons();window.reportNativeLayout();menu.querySelector('button')?.focus()}
document.addEventListener('pointerdown',e=>{if(!$('sidebar-menu').contains(e.target))closeSidebarMenu()});document.addEventListener('keydown',e=>{if(e.key==='Escape')closeSidebarMenu()});
function renameConversation(id){const c=state.conversations.find(c=>c.id===id);showDialog('重命名对话',`<label class="field">对话名称<input id="sidebar-name" value="${escape(c.title)}" maxlength="100"></label>`,'保存',async()=>{await api('/api/thread/rename',{id,title:$('sidebar-name').value});await refreshRegistry(true)})}
async function archiveThread(id){await api('/api/thread/archive',{id});if(state.thread===id){state.thread=null;state.items.clear();renderMessages(true)}await refreshRegistry(true);toast('已归档，可在最近菜单中恢复')}
async function newProjectThread(id){if(id!==state.project)await selectProject(id);expandedProjectIds.add(id);saveSidebarPrefs();await newThread();window.setClientPanel('right','chat')}
function showThreadMenu(id,anchor){const c=state.conversations.find(c=>c.id===id);showSidebarMenu(anchor,[{label:'重命名',icon:'pencil',run:()=>renameConversation(id)},{label:c.pinned?'取消置顶':'置顶',icon:'pin',run:async()=>{await api('/api/thread/pin',{id,pinned:!c.pinned});await refreshRegistry(true)}},{label:'归档',icon:'archive',run:()=>archiveThread(id)}])}
function showProjectMenu(id,anchor){const p=state.projects.find(p=>p.id===id);showSidebarMenu(anchor,[{label:p.nativePreview?'更改工作台关联':'接入工作台',icon:'plug',run:()=>showConnectWorkbench(id)},{label:'新对话',icon:'square-pen',run:()=>newProjectThread(id)},{label:'在访达中打开',icon:'folder-open',run:()=>api('/api/reveal',{id})},{label:'重命名项目',icon:'pencil',run:()=>showDialog('重命名项目',`<label class="field">项目名称<input id="sidebar-name" value="${escape(p.name)}" maxlength="80"></label>`,'保存',async()=>{await api('/api/project/rename',{id,name:$('sidebar-name').value});await refreshRegistry(true)})},{label:'移除项目',icon:'trash-2',run:()=>showRemoveProject(id)}])}
async function showArchived(){const data=await api('/api/archived');let items=data.data,cursor=data.nextCursor;const content=()=>`<div class="archived-list">${items.map(t=>`<div class="archive-row"><span>${escape(t.name||t.title||t.preview||'新对话')}</span><button type="button" class="secondary" data-restore="${t.id}">恢复</button></div>`).join('')||'<p class="dialog-description">暂无已归档对话</p>'}</div>${cursor?'<button type="button" class="subtle" id="more-archived">加载更多</button>':''}`;const bind=()=>{$('dialog-content').querySelectorAll('[data-restore]').forEach(b=>b.onclick=attempt(async()=>{await api('/api/thread/restore',{id:b.dataset.restore});items=items.filter(t=>t.id!==b.dataset.restore);await refreshRegistry(true);$('dialog-content').innerHTML=content();bind()}));if($('more-archived'))$('more-archived').onclick=attempt(async()=>{const next=await api('/api/archived?cursor='+encodeURIComponent(cursor));items.push(...next.data);cursor=next.nextCursor;$('dialog-content').innerHTML=content();bind()})};showDialog('已归档对话',content(),'完成',async()=>{});bind()}
window.receiveProjectFolder=(requestId,path,error)=>{
 const zone=$('project-folder-drop');if(!$('dialog').open||zone?.dataset.requestId!==requestId)return;
 if(error){$('dialog-error').textContent=error;return}if(!path)return;
 $('codex-project-path').value=path;$('project-folder-label').textContent=path.split('/').filter(Boolean).pop();
 $('project-folder-selected').textContent=path;$('dialog-error').textContent='';window.reportNativeLayout();
};
function addCodexProject(){
 const requestId=crypto.randomUUID();
 showDialog('添加项目',`<label class="field">源文件夹</label><button type="button" id="project-folder-drop" class="project-folder-drop" data-request-id="${requestId}">${icon('folder-plus')}<strong id="project-folder-label">将文件夹拖到这里</strong><span>或点击选择文件夹</span></button><p id="project-folder-selected" class="project-folder-selected"></p><details><summary>手动填写路径</summary><label class="field"><input id="codex-project-path" placeholder="/Users/…/项目文件夹"></label></details>`,'添加项目',async()=>{await api('/api/project/add',{path:$('codex-project-path').value});await refreshRegistry(true)});
 const zone=$('project-folder-drop');zone.onclick=()=>{if(window.webkit?.messageHandlers?.native)nativeMessage({action:'chooseProjectFolder',requestId});else $('dialog-error').textContent='请在桌面应用中选择文件夹，或展开下方手动填写路径。'};
 zone.ondragover=e=>{e.preventDefault();zone.classList.add('drag-over')};zone.ondragleave=()=>zone.classList.remove('drag-over');
 zone.ondrop=e=>{e.preventDefault();zone.classList.remove('drag-over');const raw=e.dataTransfer.getData('text/uri-list').split('\n').find(x=>x.startsWith('file:'));if(raw){try{window.receiveProjectFolder(requestId,decodeURIComponent(new URL(raw).pathname))}catch{}}else $('dialog-error').textContent='请在桌面应用中拖入文件夹，或点击选择文件夹。'};
 window.reportNativeLayout();
}
$('project-section-toggle').onclick=()=>{projectSectionOpen=!projectSectionOpen;saveSidebarPrefs();renderSidebar()};$('recent-section-toggle').onclick=()=>{recentSectionOpen=!recentSectionOpen;saveSidebarPrefs();renderSidebar()};
$('show-projects').onclick=()=>{expandedProjects=!expandedProjects;renderSidebar()};$('show-recent').onclick=()=>{expandedRecent=!expandedRecent;renderSidebar()};
$('project-add').onclick=addCodexProject;$('recent-add').onclick=attempt(newThread);
$('project-section-menu').onclick=e=>showSidebarMenu(e.currentTarget,[{label:'添加项目',icon:'folder-plus',run:addCodexProject},{label:'创建新系统',icon:'plus',run:showNewProject},{label:'导入 HTML 项目',icon:'folder-input',run:()=>$('import-project').click()},{label:'立即同步 Codex',icon:'refresh-cw',run:()=>refreshRegistry(true)}]);
$('recent-section-menu').onclick=e=>showSidebarMenu(e.currentTarget,[{label:'已归档对话',icon:'archive',run:showArchived},{label:'立即同步 Codex',icon:'refresh-cw',run:()=>refreshRegistry(true)}]);
$('sidebar-search').onclick=()=>{showDialog('搜索项目与对话','<label class="field"><input id="sidebar-query" placeholder="搜索名称…" autocomplete="off"></label><div id="sidebar-search-results"></div>','完成',async()=>{});const draw=()=>{const q=$('sidebar-query').value.trim().toLowerCase();const projects=state.projects.filter(p=>p.name.toLowerCase().includes(q)).slice(0,20);const threads=state.conversations.filter(c=>!c.archived&&c.title.toLowerCase().includes(q)).slice(0,50);$('sidebar-search-results').innerHTML=projects.map(p=>`<button type="button" class="search-result" data-project-result="${escape(p.id)}">${icon('folder')}<span>${escape(p.name)}</span></button>`).join('')+threads.map(c=>`<button type="button" class="search-result" data-result="${c.id}">${icon('message-square')}<span>${escape(c.title)}</span></button>`).join('');$('sidebar-search-results').querySelectorAll('[data-result]').forEach(b=>b.onclick=attempt(async()=>{$('dialog').close();await selectThread(b.dataset.result)}));$('sidebar-search-results').querySelectorAll('[data-project-result]').forEach(b=>b.onclick=attempt(async()=>{$('dialog').close();await selectProject(b.dataset.projectResult)}));icons()};$('sidebar-query').oninput=draw;draw()};
$('sidebar-help').onclick=()=>showDialog('工作台帮助','<p class="dialog-description">项目和对话通过 Codex 接口同步。项目右侧可新建对话、重命名和打开文件夹；对话右侧可置顶、归档，归档后可从最近菜单恢复。<br><br>页面与资源、工具保留原工作台操作。HTML 原生项目显示两端预览，其他项目可直接继续 Codex 对话。<br><br>⌘ N 新对话 · Enter 发送 · Shift Enter 换行</p>','完成',async()=>{});
$('account-menu').onclick=e=>showSidebarMenu(e.currentTarget,[{label:'使用额度',icon:'gauge',run:()=>usageButton.click()},{label:'连接与设置',icon:'settings-2',run:()=>showSettings()},{label:'已归档对话',icon:'archive',run:showArchived}]);
$('open-code-project').onclick=attempt(()=>state.project?api('/api/reveal',{id:state.project}):Promise.resolve());

function updateRunning() {
  const running = !!state.running[state.thread],remote=!!state.remoteRunning[state.thread]&&!running;
  $('send').classList.toggle('running', running); $('send').innerHTML = icon(running ? 'square' : 'arrow-up'); $('send').title = running ? '停止任务' : '发送'; $('send').setAttribute('aria-label', running ? '停止任务' : '发送');
  $('send').disabled = remote || state.pendingSend || !state.ready || (!state.project&&!state.thread);
  $('chat-status').textContent = running ? '正在处理' : remote?'Codex 正在处理':'就绪'; $('run-status').textContent = running ? 'Codex 正在修改，预览将自动更新' : '修改会自动同步到预览'; icons();
}
const emptyChat = $('messages').innerHTML;let displayedThreadUpdate=0;
function markdown(text) { return DOMPurify.sanitize(marked.parse(text || '', { breaks: true }), { FORBID_TAGS: ['iframe', 'form', 'input', 'button'], FORBID_ATTR: ['style'] }); }
function conversationImage(url,alt='对话图片'){
  return typeof url==='string'&&(/^(?:data:image\/(?:png|jpeg|webp|gif);base64,|\/api\/conversation-media\/)/.test(url))?`<img class="conversation-image" src="${escape(url)}" alt="${escape(alt)}" loading="lazy">`:'';
}
function itemHTML(item) {
  if (item.type === 'userMessage') {
    const text=userMessageText(item.content),pictures=(item.content||[]).filter(c=>['localImage','image'].includes(c.type));
    const thumbs=pictures.map((c,index)=>{const url=c.mediaUrl||c.url;const img=conversationImage(url,'参考图片 '+(index+1));return img?`<a class="user-image-thumb" href="${escape(url)}" aria-label="查看原图 ${index+1}">${img}</a>`:'<span class="muted">参考图片暂不可用</span>'}).join('');
    return `<div class="user-message-group">${thumbs?`<div class="user-message-images">${thumbs}</div>`:''}${text?`<div class="message user">${escape(text)}</div>`:''}</div>`;
  }
  if (item.type === 'agentMessage') return item.text ? `<div class="message agent"><div class="message-label">${icon('sparkles')}Codex</div>${markdown(item.text)}</div>` : '';
  if(item.type==='imageGeneration'){const data=item.result&&/^[A-Za-z0-9+/=\r\n]+$/.test(item.result)?'data:image/png;base64,'+item.result:item.result;return `<div class="message agent">${conversationImage(item.mediaUrl||data,'生成的图片')}<small>${escape(item.failure?.message||(item.status==='completed'?'图片已生成':'图片生成：'+item.status))}</small></div>`;}
  if(item.type==='imageView')return conversationImage(item.mediaUrl,'查看的图片');
  if (item.type === 'plan') return `<details class="activity" open><summary>执行计划</summary><div>${markdown(item.text)}</div></details>`;
  if (item.type === 'commandExecution') return `<details class="activity"><summary>${item.status === 'inProgress' ? '正在执行' : item.exitCode && item.exitCode !== 0 ? '命令返回 ' + item.exitCode : '已执行'} · ${escape((item.command||'').split('\n')[0]).slice(0, 90)}</summary><pre>${escape(item.aggregatedOutput || '等待执行结果…')}</pre></details>`;
  if (item.type === 'fileChange') return `<details class="activity"><summary>${item.status === 'inProgress' ? '正在修改文件' : '文件修改'} · ${item.changes?.length || 0} 项</summary><pre>${escape(item.changes?.map(c => `${c.path}\n${c.diff || ''}`).join('\n\n') || '')}</pre></details>`;
  if (item.type === 'mcpToolCall') return `<details class="activity"><summary>${item.status === 'inProgress' ? '正在调用' : '已调用'} · ${escape(item.tool)}</summary><pre>${escape(JSON.stringify(item.result || item.error || item.arguments, null, 2)).slice(0, 18000)}</pre></details>`;
  if (item.type === 'dynamicToolCall') return `<details class="activity"><summary>${item.status === 'inProgress' ? '正在执行' : '已执行'} · ${escape(item.tool)}</summary><pre>${escape(JSON.stringify(item.contentItems || item.arguments, null, 2)).slice(0, 18000)}</pre></details>`;
  if (item.type === 'functionCallOutput') return `<details class="activity"><summary>执行结果 · ${escape(item.name)}</summary><pre>${escape(typeof item.output === 'string' ? item.output : JSON.stringify(item.output, null, 2)).slice(0, 18000)}</pre></details>`;
  if (item.type === 'clientError') return `<div class="turn-error">${escape(item.text)}</div>`;
  return '';
}
const pendingMessages=new Map();
let renderTimer,lastMessagesMarkup='',lastMessagesThread=null;
const messageExpansion=new Map();
// Toggle synchronously so polling cannot overwrite a pending native details click.
$('messages').addEventListener('click',event=>{
 const summary=event.target.closest('summary');if(!summary)return;
 const details=summary.parentElement;if(details.tagName!=='DETAILS'||!details.dataset.detailKey)return;
 event.preventDefault();event.stopPropagation();details.open=!details.open;messageExpansion.set(details.dataset.detailKey,details.open);if(details.classList.contains('turn-process'))renderMessages(true);
});
function renderMessages(immediate = false) {
  clearTimeout(renderTimer); const draw = () => {
    const el = $('messages'), bottom = el.scrollHeight - el.scrollTop - el.clientHeight < 100;
    const scrollTop=el.scrollTop;
    const html=groupConversation([...state.items.values()],!!(state.running[state.thread]||state.remoteRunning[state.thread])).map(group=>{
      const users=group.visible.filter(i=>i.type==='userMessage').map(itemHTML).join('');
      const key=state.thread+':'+group.key,expanded=messageExpansion.get(key)===true;
      const process=expanded?group.process.map(item=>{const node=itemHTML(item);return node?`<div data-process-item="${escape(item.id||'')}">${node}</div>`:''}).join(''):'';
      return users+(group.process.length?`<details class="turn-process" data-detail-key="${escape(key)}"><summary>${group.active?'正在处理':'查看执行过程'} · ${group.process.length} 项</summary><div class="turn-process-content">${process}</div></details>`:'')+group.visible.filter(i=>i.type!=='userMessage').map(itemHTML).join('');
    }).join('');
    const pending=pendingMessages.get(state.thread);
    if(pending&&[...state.items.values()].some(i=>i.type==='userMessage'&&!pending.known.has(i.id)&&(i.id===pending.id||i.clientUserMessageId===pending.id||userMessageText(i.content)===pending.matchText)))pendingMessages.delete(state.thread);
    const outgoing=pendingMessages.get(state.thread);
    const pendingHTML=outgoing?itemHTML({type:'userMessage',content:[{type:'text',text:outgoing.text||'图片参考'}]})+`<small class="muted">${escape(outgoing.status)}</small>`:'';
    const markup=(html+pendingHTML || emptyChat) + (state.running[state.thread] ? `<div class="typing">${icon('loader-circle')}Codex 正在处理…</div>` : '');
    if(markup===lastMessagesMarkup&&state.thread===lastMessagesThread)return;
    const images=new Map([...el.querySelectorAll('img.conversation-image')].filter(img=>img.complete&&img.naturalWidth>0).map(img=>[img.getAttribute('src'),img]));
    lastMessagesMarkup=markup;lastMessagesThread=state.thread;el.innerHTML=markup;
    el.querySelectorAll('img.conversation-image').forEach(img=>{const previous=images.get(img.getAttribute('src'));if(previous){img.replaceWith(previous);images.delete(img.getAttribute('src'));}});
    el.querySelectorAll('img.conversation-image').forEach(img=>{
      img.addEventListener('error',async()=>{
        try{
          const response=await fetch(img.getAttribute('src'),{headers:{'x-client-token':document.querySelector('meta[name="client-token"]').content},cache:'reload'});
          if(!response.ok)throw new Error('missing');
          const url=URL.createObjectURL(await response.blob());
          img.onload=()=>URL.revokeObjectURL(url);
          img.onerror=()=>{URL.revokeObjectURL(url);img.replaceWith(Object.assign(document.createElement('span'),{className:'muted',textContent:'参考图片暂不可用，请重新添加'}));};
          img.src=url;
        }catch{img.replaceWith(Object.assign(document.createElement('span'),{className:'muted',textContent:'参考图片暂不可用，请重新添加'}));}
      },{once:true});
    });
    el.querySelectorAll('[data-process-item] details').forEach((d,index)=>{d.dataset.detailKey=state.thread+':item:'+d.closest('[data-process-item]').dataset.processItem+':'+index});
    el.querySelectorAll('details[data-detail-key]').forEach(d=>{d.open=messageExpansion.get(d.dataset.detailKey)===true});
    el.querySelectorAll('a').forEach(a => { a.target = '_blank'; a.rel = 'noopener noreferrer'; });
    if (bottom || immediate) el.scrollTop = el.scrollHeight;else el.scrollTop=scrollTop; icons();
  }; if (immediate) draw(); else renderTimer = setTimeout(draw, 65);
}
function loadHistory(thread) {
  state.items.clear();delete state.remoteRunning[thread.id];
  for (const turn of thread?.turns || []) {
    for (const item of turn.items || []) state.items.set(item.id, {...item,_turnId:turn.id});
    if (turn.error) state.items.set('error:' + turn.id, { type: 'clientError', text: turn.error.message });
    if (turn===thread.turns.at(-1)&&turn.status === 'inProgress'&&!state.running[thread.id]) state.remoteRunning[thread.id] = turn.id;
  }
  renderMessages(true); updateRunning();
}
let registryRefresh=null,registryRefreshLight=false,registryRenderKey='';
async function refreshRegistry(force=false,light=false) {
 if(registryRefresh){if(!force&&(light||!registryRefreshLight))return registryRefresh;await registryRefresh.catch(()=>{});}
 registryRefreshLight=light;
 registryRefresh=(async()=>{
  const query=new URLSearchParams();if(force)query.set('refresh','1');if(light)query.set('sidebar','1');
  const value=await api('/api/state?'+query);state.projects=value.projects;state.conversations=value.registry.conversations;state.running=value.running;
  if(state.thread&&!currentConversation()){state.thread=null;state.items.clear();renderMessages(true)}
  const key=JSON.stringify([state.projects,state.conversations,state.running,state.project,state.thread]);
  if(key!==registryRenderKey){registryRenderKey=key;renderSidebar();updateRunning();}
  $('sidebar-sync-state').textContent='与 Codex 同步';return value;
 })().finally(()=>{registryRefresh=null});return registryRefresh;
}
let sidebarEventTimer;
function scheduleSidebarSync(){clearTimeout(sidebarEventTimer);sidebarEventTimer=setTimeout(()=>{if(!document.hidden&&!state.switching&&!$('dialog').open&&$('sidebar-menu').classList.contains('hidden'))refreshRegistry(false,true).catch(()=>{})},150)}
async function selectProject(id) {
  if (state.switching || id === state.project) return; state.switching = true;
  try {
    window.cancelWorkbenchAnnotation?.();state.selectedSkills=[];renderSelectedSkills();await disconnectInput(); await api('/api/project/activate', { id }); state.project = id; state.thread = null; state.selected = null; state.items.clear(); state.editor = null;
    renderSidebar(); renderMessages(true); renderRequests(); updateRunning(); await refreshEditor(true);
  } finally { state.switching = false; }
}
async function selectThread(id) {
  if (state.switching) return; state.switching = true;
  try {
    window.cancelWorkbenchAnnotation?.();state.selectedSkills=[];renderSelectedSkills();
    await disconnectInput(); const result = await api('/api/thread/select', { id }); if(result.conversation){const index=state.conversations.findIndex(c=>c.id===id||c.id===result.conversation.id);if(index>=0)state.conversations[index]=result.conversation;else state.conversations.push(result.conversation)} state.thread = result.thread.id; state.project = result.conversation?.projectId||null; if(result.conversation&&!state.conversations.some(c=>c.id===state.thread))state.conversations.unshift(result.conversation); state.selected = null;window.setClientPanel('right','chat');
    loadHistory(result.thread); displayedThreadUpdate=currentConversation()?.updatedAt||0; renderSidebar(); renderRequests(); await refreshEditor(true);
  } finally { state.switching = false; }
}
async function newThread() {
  if (!state.project) return showNewProject();
  const result = await api('/api/thread/create', { projectId: state.project }); state.conversations.unshift(result.conversation); state.thread = result.conversation.id; state.items.clear();
  renderSidebar(); renderMessages(true); renderRequests(); updateRunning(); $('prompt').focus(); return result;
}
function showDialog(title, content, submitText, submit) {
  $('dialog-title').textContent = title; $('dialog-content').innerHTML = content; $('dialog-error').textContent = ''; $('dialog-submit').textContent = submitText; $('dialog-submit').disabled = false;
  $('dialog-submit').onclick = async () => {
    if($('dialog-submit').disabled)return;$('dialog-submit').disabled = true; $('dialog-submit').textContent='处理中…'; $('dialog-error').textContent = '';
    try { await submit(); $('dialog').close(); } catch (error) { $('dialog-error').textContent = error.message; } finally { $('dialog-submit').disabled = false;$('dialog-submit').textContent=submitText; }
  };
  $('dialog').showModal(); icons(); setTimeout(() => $('dialog-content').querySelector('input')?.focus(), 30);
}
function showNewProject() {
  showDialog('创建新系统', '<p class="dialog-description">从一个独立的 App 项目开始。源码、资源、规范和对话会分别保存。</p><label class="field">系统名称<input id="project-name" placeholder="例如：旅行手账" maxlength="80" autocomplete="off"></label>', '创建系统', async () => {
    const p = await api('/api/project/create', { name: $('project-name').value }); state.project = p.id; state.thread = null; state.selected = null; state.items.clear();
    await refreshRegistry(); await refreshEditor(true); renderMessages(true); toast('系统已创建，现在可以直接描述你的需求');
  });
}
$('new-project').onclick = showNewProject; $('new-thread').onclick = attempt(newThread);
$('workbench-nav').onclick = () => { $('inspector').classList.add('hidden'); $('prompt').focus(); };
$('import-project').onclick = () => showDialog('导入已有项目', '<p class="dialog-description">填写包含 app.json 的 HTML 原生项目文件夹路径。</p><label class="field">项目文件夹<input id="import-path" placeholder="/Users/…/我的 App"></label>', '导入项目', async () => {
  const p = await api('/api/project/import', { path: $('import-path').value }); state.project = p.id; state.thread = null; state.items.clear(); await refreshRegistry(); await refreshEditor(true); renderMessages(true); toast('项目已导入');
});
$('rename-thread').onclick = () => { if (!state.thread) return toast('发送消息或新建对话后可以重命名'); showDialog('重命名对话', `<label class="field">对话名称<input id="thread-name" value="${escape(currentConversation().title)}" maxlength="100"></label>`, '保存', async () => { await api('/api/thread/rename', { id: state.thread, title: $('thread-name').value }); await refreshRegistry(); }); };
$('reveal').onclick = attempt(() => api('/api/reveal', { id: state.project }));
async function showSettings(external = false) {
  showDialog(external ? '外部窗口' : '连接与设置', `<p class="dialog-description">日常工作在本客户端完成。模拟器在后台持续同步。</p><div class="settings-row"><div>Codex 连接<small>${state.ready ? '已连接 · 使用本机 ChatGPT 登录' : '尚未连接'}</small></div><button type="button" class="secondary" id="reconnect">重新连接</button></div><div class="settings-row"><div>HTML Native Studio<small>显示当前新版工作台</small></div><button type="button" class="secondary" data-window="show-studio">显示</button></div><div class="settings-row"><div>iOS 模拟器<small>打开独立模拟器窗口</small></div><button type="button" class="secondary" data-window="show-simulator">显示</button></div><div class="settings-row"><div>隐藏所有外部窗口</div><button type="button" class="secondary" data-window="hide">隐藏</button></div><p class="inspector-note">这是接入 Codex App Server 的独立工作客户端。App Server 为实验性接口；官方 Codex 应用保持独立。</p>`, '完成', async () => {});
  $('dialog-content').querySelectorAll('[data-window]').forEach(b => b.onclick = attempt(async () => { await api('/api/window', { action: b.dataset.window }); toast(b.dataset.window === 'hide' ? '外部窗口已隐藏，后台继续同步' : '窗口已显示'); }));
  $('reconnect').onclick = attempt(async () => { await api('/api/reconnect', {}); await loadCodex(); toast('已重新连接 Codex'); });
}
$('settings').onclick = () => showSettings(); $('external').onclick = () => showSettings(true);
$('top-external').onclick=()=>showSettings(true);
async function loadCodex() {
  try {
    const result = await api('/api/codex'); state.ready = result.loggedIn; state.models = result.models || [];
    $('account-status').textContent = result.loggedIn ? '已连接 · ChatGPT 登录' : '需要登录'; $('account-dot').classList.toggle('offline', !result.loggedIn);
    const saved = localStorage.getItem('studio-model') || '';
    $('model').innerHTML = '<option value="">默认模型</option>' + state.models.map(m => `<option value="${escape(m.model)}">${escape(m.displayName)}</option>`).join('');
    if (state.models.some(m => m.model === saved)) $('model').value = saved;
    renderModelPicker(); updateEffort(); updateRunning(); refreshUsage();
    if (!result.loggedIn) showDialog('登录 Codex', '<p class="dialog-description">使用你的 ChatGPT 账号登录后，即可在工作台中对话并修改代码。</p>', '打开登录页面', async () => { const login = await api('/api/login', {}); if (login.authUrl) openExternal(login.authUrl); });
  } catch (error) { state.ready = false; $('account-status').textContent = '连接失败'; $('account-dot').classList.add('offline'); updateRunning(); toast(error.message, true); }
}
let speedTier=localStorage.getItem('studio-speed')==='priority'?'priority':'default';
function updateSpeed(){
  const model=state.models.find(m=>m.model===$('model').value)||state.models.find(m=>m.isDefault);
  const supported=model?.serviceTiers?.some(t=>t.id==='priority');
  if(!supported)speedTier='default';
  const fast=speedTier==='priority',button=$('speed');
  button.disabled=!supported;button.classList.toggle('fast',fast);button.setAttribute('aria-pressed',String(fast));button.setAttribute('aria-label',fast?'加速已开启，点击关闭':'加速未开启，点击开启');
  button.querySelector('span').textContent=fast?'加速':'标准';
  button.title=supported?(fast?'加速模式 · 消耗更多额度，点击恢复标准速度':'标准速度 · 点击开启加速，会消耗更多额度'):'当前模型不支持加速';
  localStorage.setItem('studio-speed',speedTier);
}
$('speed').onclick=()=>{speedTier=speedTier==='priority'?'default':'priority';updateSpeed()};
function updateEffort() {
  const previous=$('effort').value;
  updateSpeed();
  const model = state.models.find(m => m.model === $('model').value) || state.models.find(m => m.isDefault);
  const labels = { none: '无', minimal: '极低', low: '低', medium: '中', high: '高', xhigh: '极高', max: '最大', ultra: '超高' };
  $('effort').innerHTML = '<option value="">默认</option>' + (model?.supportedReasoningEfforts || []).map(e => `<option value="${e.reasoningEffort}">${labels[e.reasoningEffort] || e.reasoningEffort}</option>`).join('');
  if([...$('effort').options].some(o=>o.value===previous))$('effort').value=previous;
}
function renderModelPicker(){const selected=state.models.find(m=>m.model===$('model').value);$('model-picker').textContent=(selected?.displayName||'默认模型')+' ▾';$('model-picker').title='选择 Codex 模型：'+(selected?.displayName||'默认模型');$('model-picker').setAttribute('aria-label',$('model-picker').title);}
$('model-picker').onclick=()=>{
  const choices=[{model:'',displayName:'默认模型',description:'使用 Codex 默认模型'},...state.models];
  showDialog('选择模型',`<div class="model-options" role="group" aria-label="可用模型">${choices.map(m=>`<button type="button" class="model-option ${m.model===$('model').value?'selected':''}" data-model="${escape(m.model)}" aria-pressed="${m.model===$('model').value}"><span><strong>${escape(m.displayName)}</strong><small>${escape(m.description||'')}</small></span><span class="model-check">${m.model===$('model').value?'✓':''}</span></button>`).join('')}</div>`,'完成',async()=>{});
  $('dialog-content').querySelectorAll('[data-model]').forEach(b=>b.onclick=()=>{$('model').value=b.dataset.model;$('model').onchange();$('dialog').close();$('model-picker').focus()});
};
$('model').onchange = () => { renderModelPicker(); localStorage.setItem('studio-model', $('model').value); updateEffort(); renderUsage(); };
$('composer').onsubmit = attempt(async event => {
  event.preventDefault(); if (state.running[state.thread]) { await api('/api/turn/stop', { threadId: state.thread }); return; }
  const value = $('prompt').value.trim(); if ((!value && !state.attachments.length) || state.pendingSend) return;
  state.pendingSend = true; updateRunning();
  let sendThread=state.thread;const outgoing={text:value||state.attachments.map(a=>a.name||'附件').join('、'),matchText:value||'请查看这张参考图。',known:new Set(state.items.keys()),status:'发送中…'};pendingMessages.set(sendThread,outgoing);renderMessages(true);
  try {
    if (!state.thread) {await newThread();pendingMessages.delete(sendThread);sendThread=state.thread;pendingMessages.set(sendThread,outgoing);renderMessages(true);}
    const submissionKey=JSON.stringify([state.thread,value,state.attachments.map(a=>a.id),state.selectedSkills.map(s=>s.path)]);
    if(state.submissionKey!==submissionKey){state.submissionKey=submissionKey;state.clientUserMessageId=crypto.randomUUID()}
    outgoing.id=state.clientUserMessageId;
    const delivery=await api('/api/turn/start', { clientUserMessageId:state.clientUserMessageId,threadId: state.thread, text: value, model: $('model').value, effort: $('effort').value, serviceTier:speedTier, attachments: state.attachments.map(a => a.id), skills: state.selectedSkills.map(s=>s.path) });
    outgoing.status='已提交，等待 Codex 接收';renderMessages(true);
    state.submissionKey=null;state.clientUserMessageId=null;
    if(delivery.queued)toast('已交给 Codex 原对话，沿用原对话的模型与权限；请保持 Codex 打开');
    if(state.thread===sendThread&&$('prompt').value.trim()===value){$('prompt').value = ''; $('prompt').style.height = ''; state.selectedSkills=[];renderSelectedSkills(); state.attachments.forEach(a => URL.revokeObjectURL(a.preview)); state.attachments = []; renderAttachments();} void refreshRegistry().catch(error=>toast(error.message,true));
  } catch(error) {outgoing.status='发送未确认，草稿已保留：'+error.message;renderMessages(true);throw error;} finally { state.pendingSend = false; updateRunning(); }
});
$('prompt').onkeydown = event => { if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); if (!state.running[state.thread]&&!state.remoteRunning[state.thread]) $('composer').requestSubmit(); } };
$('prompt').oninput = () => { $('prompt').style.height = 'auto'; $('prompt').style.height = Math.min(170, $('prompt').scrollHeight) + 'px'; };
document.addEventListener('keydown', event => { if ((event.metaKey && !event.ctrlKey) && event.key.toLowerCase() === 'n') { event.preventDefault(); attempt(newThread)(); } });
function renderAttachments() { $('attachments').innerHTML = state.attachments.map(a => `<div class="attachment">${['file','folder'].includes(a.kind)?icon(a.kind==='folder'?'folder':'file-text'):`<button type="button" class="attachment-edit" data-edit="${a.id}" aria-label="标注图片 ${escape(a.name)}"><img src="${a.preview}" alt="${escape(a.name)}"></button>`}<span>${escape(a.name)}</span>${!a.kind||a.kind==='image'?`<button type="button" data-copy="${a.id}" aria-label="复制图片" title="复制图片">${icon('copy')}</button>`:''}<button type="button" data-remove="${a.id}" aria-label="移除附件">${icon('x')}</button></div>`).join(''); $('attachments').querySelectorAll('[data-copy]').forEach(b=>b.onclick=attempt(()=>copyWorkbenchImage(state.attachments.find(a=>a.id===b.dataset.copy).preview))); $('attachments').querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>window.editWorkbenchAttachment(b.dataset.edit)); $('attachments').querySelectorAll('[data-remove]').forEach(b => b.onclick = () => { const a = state.attachments.find(a => a.id === b.dataset.remove); URL.revokeObjectURL(a.preview); state.attachments = state.attachments.filter(a => a.id !== b.dataset.remove); renderAttachments(); }); icons(); }
async function addFiles(files) { for (const file of files) { if(file.size>16*1024*1024)throw new Error('每个文件不能超过 16 MB'); if (state.attachments.length >= 6) throw new Error('每次最多附加 6 个文件'); const data = await new Promise((resolve, reject) => { const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(file); }); const result = await api('/api/upload', { data, name: file.name }); state.attachments.push({ ...result, preview: URL.createObjectURL(file) }); renderAttachments(); } }
$('attach').onclick = () => $('file-input').click(); $('file-input').onchange = attempt(async () => { await addFiles($('file-input').files); $('file-input').value = ''; });
$('prompt').addEventListener('paste', attempt(async event => { const images = [...(event.clipboardData?.files || [])]; if (images.length) { event.preventDefault(); await addFiles(images); } }));
function renderRequests() {
  const list = [...state.requests.values()].filter(r => r.params.threadId === state.thread);
  $('requests').innerHTML = list.map(r => {
    const questions = r.params.questions;
    if(r.method==='mcpServer/elicitation/request'){
      const p=r.params,schema=p.requestedSchema,fields=Object.entries(schema?.properties||{}).map(([name,f])=>{
        const attr=`data-mcp-field="${escape(name)}" data-type="${escape(f.type)}" ${(schema.required||[]).includes(name)?'required':''}`;
        const options=f.oneOf||f.items?.anyOf||(f.enum||f.items?.enum)?.map((value,index)=>({const:value,title:f.enumNames?.[index]||value}));
        const input=options?`<select ${attr} ${f.type==='array'?'multiple':''}><option value="">请选择</option>${options.map(o=>`<option value="${escape(o.const)}">${escape(o.title)}</option>`).join('')}</select>`:f.type==='boolean'?`<select ${attr}><option value="">请选择</option><option value="true">是</option><option value="false">否</option></select>`:`<input ${attr} type="${['number','integer'].includes(f.type)?'number':'text'}" ${f.type==='integer'?'step="1"':''}>`;
        return `<label class="field">${escape(f.title||name)}${f.description?`<small>${escape(f.description)}</small>`:''}${input}</label>`;
      }).join('');
      const url=typeof p.url==='string'&&/^https?:\/\//.test(p.url)?`<a href="${escape(p.url)}" target="_blank" rel="noopener noreferrer">打开插件页面</a>`:'';
      return `<form class="request" data-mcp-request="${escape(r.id)}"><strong>${escape(p.serverName||'插件')}需要补充信息</strong><p>${escape(p.message||'插件未提供说明，请取消并重试。')}</p>${url}${fields}<button type="submit">${p.mode==='url'?'我已完成':'提交'}</button><button type="button" data-approval="${escape(r.id)}" data-decision="decline">取消</button></form>`;
    }
    if (questions) return `<div class="request" data-request="${r.id}"><strong>Codex 需要你的补充</strong>${questions.map(q => `<label class="field">${escape(q.question)}${q.options?.length ? `<select data-answer="${escape(q.id)}">${q.options.map(o => `<option value="${escape(o.label)}">${escape(o.label)}</option>`).join('')}</select>` : `<input data-answer="${escape(q.id)}" placeholder="填写回答">`}</label>`).join('')}<button data-answer-send="${r.id}">提交回答</button></div>`;
    return `<div class="request"><strong>需要确认的操作</strong><p>${escape(r.params.reason || r.method)}</p><pre>${escape(r.params.command || JSON.stringify(r.params.permissions || r.params.changes || {}, null, 2))}</pre><button data-approval="${r.id}" data-decision="accept">允许这次操作</button><button data-approval="${r.id}" data-decision="decline">拒绝</button></div>`;
  }).join('');
  $('requests').querySelectorAll('[data-mcp-request]').forEach(form=>form.onsubmit=event=>{
    event.preventDefault();attempt(async()=>{
      const content=Object.create(null);
      for(const el of form.querySelectorAll('[data-mcp-field]')){
        if(!el.value&&!el.required)continue;
        content[el.dataset.mcpField]=el.dataset.type==='array'?[...el.selectedOptions].map(o=>o.value).filter(Boolean):el.dataset.type==='boolean'?el.value==='true':['number','integer'].includes(el.dataset.type)?Number(el.value):el.value;
      }
      await api('/api/request/respond',{id:form.dataset.mcpRequest,decision:'accept',content});state.requests.delete(form.dataset.mcpRequest);renderRequests();
    })();
  });
  $('requests').querySelectorAll('[data-approval]').forEach(b => b.onclick = attempt(async () => { await api('/api/request/respond', { id: b.dataset.approval, decision: b.dataset.decision }); state.requests.delete(b.dataset.approval); renderRequests(); }));
  $('requests').querySelectorAll('[data-answer-send]').forEach(b => b.onclick = attempt(async () => { const answers = {}; b.closest('.request').querySelectorAll('[data-answer]').forEach(i => answers[i.dataset.answer] = { answers: [i.value] }); await api('/api/request/respond', { id: b.dataset.answerSend, answers }); state.requests.delete(b.dataset.answerSend); renderRequests(); }));
}
function eventMessage(event) {
  state.sequence = Math.max(state.sequence, event.sequence || 0); const p = event.params || {};
  if(/^(project\/|thread\/(name|archived|unarchived|started|project)|threadSection\/)/.test(event.method))scheduleSidebarSync();
  if (event.method === 'client/request') { state.requests.set(String(p.id), p); renderRequests(); return; }
  if (event.method === 'client/request/resolved') { state.requests.delete(String(p.id)); renderRequests(); return; }
  if (event.method === 'client/offline') { state.ready = false; $('account-status').textContent = '连接已断开'; $('account-dot').classList.add('offline'); updateRunning(); toast(p.message, true); return; }
  if (event.method === 'account/login/completed') { loadCodex(); return; }
  if (event.method === 'account/rateLimits/updated') { refreshUsage(); return; }
  if (event.method === 'turn/started') { state.running[p.threadId] = p.turn.id; updateRunning(); renderSidebar(); }
  if (event.method === 'turn/completed') { delete state.remoteRunning[p.threadId];delete state.running[p.threadId];state.items.delete('reconnect:'+p.threadId); updateRunning(); renderSidebar(); refreshUsage(); }
  if (p.threadId !== state.thread) return;
  if (event.method === 'item/started' || event.method === 'item/completed') state.items.set(p.item.id, {...p.item,_turnId:p.turnId});
  if (event.method === 'item/agentMessage/delta') { const item = state.items.get(p.itemId) || { id: p.itemId, type: 'agentMessage', text: '', _turnId:p.turnId }; item.text += p.delta; state.items.set(item.id, item); }
  if (event.method === 'item/commandExecution/outputDelta') { const item = state.items.get(p.itemId); if (item) item.aggregatedOutput = (item.aggregatedOutput || '') + p.delta; }
  if (event.method === 'turn/completed') {
    if (p.turn.error) state.items.set('error:' + p.turn.id, { type: 'clientError', text: p.turn.error.message });
    for (const [id, request] of state.requests) if (request.params.threadId === p.threadId) state.requests.delete(id);
    renderRequests(); attempt(refreshRegistry)(); attempt(() => refreshEditor())();
  }
  if (event.method === 'error') { const message=p.error?.message||p.message||'执行出错';const retry=p.willRetry===true||/^Reconnecting\.\.\./i.test(message);state.items.set(retry?'reconnect:'+p.threadId:'error:'+Date.now(),{type:'clientError',text:retry?'连接中断，正在重试；已生成的内容会保留。':message}); }
  renderMessages();
}
let stream;
function connectEvents() {
  stream?.close(); stream = new EventSource('/api/events?after=' + state.sequence); stream.onmessage = e => eventMessage(JSON.parse(e.data));
  stream.onerror = () => { $('chat-status').textContent = '正在恢复连接'; };
  stream.onopen = () => { updateRunning(); };
}
let refreshBusy = false;
async function refreshEditor(force = false) {
  // The embedded native editor owns preview state; do not fetch and render a second hidden editor.
  if(nativeHost){if(force)renderSidebar();return;}
  if (!state.project || refreshBusy) return; refreshBusy = true;
  try {
    const s = await studio('/status'); state.editing = s.editing;
    window.receivePreviewMode(!s.editing);
    const issue = s.error || (s.conflicts.length ? `${s.conflicts.length} 处同步冲突` : '');
    $('sync-status').innerHTML = `<span class="status-dot"></span>${issue ? '同步需处理' : '已同步'}`; $('sync-status').classList.toggle('error', !!issue); $('sync-status').title = issue || 'HTML 与 iOS 保持同步';
    if (s.active !== previewId()) { $('sync-status').title = '其他窗口切换了项目，请重新选择当前项目'; return; }
    const result = await studio('/editor-state?id=' + previewId() + '&compile=' + (project()?.compileRevision || ''));
    const changed = force || !state.editor || result.revision !== state.editor.revision;
    state.editor = result;
    if (result.project) state.projects = state.projects.map(p => p.id === state.project ? {...result.project,...p,pages:result.project.pages,compileRevision:result.project.compileRevision} : p);
    if (changed) {
      const p = project(); $('page-select').innerHTML = (p?.pages || []).map(page => `<option value="${escape(page.id)}">${escape(page.name || page.id)}</option>`).join(''); $('page-select').value = result.page.id;
      if (!$('inspector').contains(document.activeElement)) renderInspector(); updateSelection();
    }
    if (force) { if(!nativeHost)$('html-preview').src = '/studio/web'; renderSidebar(); }
    if (!nativeHost && !s.editing && !inputSession && !inputConnecting) connectInput();
  } finally { refreshBusy = false; }
}
async function setMode(editing) { await disconnectInput(); await studio('/mode', { editing }); state.editing = editing; await refreshEditor(); if (!editing) await connectInput(); toast(editing ? '已切换到编辑模式' : '可以直接操作两个预览，页面状态会同步'); }
$('edit-mode').onclick = attempt(() => setMode(true)); $('run-mode').onclick = attempt(() => setMode(false));
$('page-select').onchange = attempt(async () => { const id = $('page-select').value; await studio('/event', { side: 'ios', projectID: state.project, event: { type: 'navigate', page: id }, eventID: crypto.randomUUID() }); state.selected = null; await refreshEditor(); });
$('inspect').onclick = () => { $('inspector').classList.toggle('hidden'); renderInspector(); }; $('close-inspector').onclick = () => $('inspector').classList.add('hidden');
function selectNode(id) { state.selected = id; $('inspector').classList.remove('hidden'); renderInspector(); updateSelection(); try { $('html-preview').contentWindow.studioSelect(id); } catch {} }
function renderInspector() {
  const page = state.editor?.page; if (!page) return;
  const nodes = page.nodes.filter(n => !n.hidden), node = page.nodes.find(n => n.id === state.selected);
  let html = `<label class="field">当前图层<select id="node-select"><option value="">请选择图层</option>${nodes.map(n => `<option value="${escape(n.id)}" ${n.id === state.selected ? 'selected' : ''}>${escape(n.name || n.id)} · ${escape(n.type)}</option>`).join('')}</select></label>`;
  if (node) {
    const fields = [['x','X'],['y','Y'],['width','宽度'],['height','高度'],['fontSize','字号'],['cornerRadius','圆角']];
    html += `<label class="field">文字<textarea id="prop-text">${escape(node.text)}</textarea></label><div class="field-grid">${fields.map(([key, label]) => `<label class="field">${label}<input type="number" step="0.5" data-prop="${key}" value="${node[key] ?? 0}"></label>`).join('')}</div><label class="field">填充颜色<input data-prop="fill" value="${escape(node.fill)}"></label><label class="field">文字颜色<input data-prop="color" value="${escape(node.color)}"></label><button class="primary" id="save-properties">保存 iOS 外观</button>`;
  } else html += '<p class="inspector-note">点击 iOS 或 HTML 预览中的内容选择图层，也可以添加新的文字或色块。</p>';
  html += '<div class="field-grid" style="margin-top:14px"><button class="secondary" id="add-text">添加文字</button><button class="secondary" id="add-block">添加色块</button></div><p class="inspector-note">这里保存 iOS 外观调整。HTML 源码由下方对话修改，工作台会自动合并并提示冲突。</p>';
  $('inspector-content').innerHTML = html; $('node-select').onchange = () => selectNode($('node-select').value);
  if (node) $('save-properties').onclick = attempt(async () => {
    if (!state.editing) throw new Error('请先切换到编辑模式');
    const snapshot = structuredClone(state.editor.page), edited = snapshot.nodes.find(n => n.id === state.selected);
    $('inspector-content').querySelectorAll('[data-prop]').forEach(el => { edited[el.dataset.prop] = el.type === 'number' ? Number(el.value) : el.value; }); edited.text = $('prop-text').value;
    if (edited.width <= 0 || edited.height <= 0) throw new Error('宽高必须大于 0');
    for (const key of ['fill','color']) if (!/^#[0-9a-f]{6}([0-9a-f]{2})?$/i.test(edited[key])) throw new Error('颜色格式应为 #RRGGBB 或 #RRGGBBAA');
    await savePage(snapshot); toast('iOS 外观已保存');
  });
  $('add-text').onclick = attempt(() => addNode('text')); $('add-block').onclick = attempt(() => addNode('container'));
}
async function savePage(page) { await studio('/save', { id: state.project, compileRevision: project().compileRevision, pages: [page] }); await refreshEditor(true); }
async function addNode(type) {
  if (!state.editing) throw new Error('请先切换到编辑模式');
  const page = structuredClone(state.editor.page), id = 'client-' + crypto.randomUUID();
  const base = page.nodes[0] || {};
  page.nodes.push({ ...base, id, name: type === 'text' ? '新文字' : '新色块', type, parent: '', sharedKey: null, source: null, textKey: null, text: type === 'text' ? '新文字' : '', x: 30, y: (page.contentInsets?.top || 100) + 30, width: 150, height: type === 'text' ? 36 : 100, hidden: false, locked: false, action: '', fill: type === 'text' ? '#00000000' : '#DDE9F8', color: '#243C55', fontSize: 20, fontWeight: 500, opacity: 1, cornerRadius: type === 'text' ? 0 : 12, rotation: 0, scale: 1, clip: false, strokeWidth: 0, strokeColor: '#00000000', gradient: null, shadow: null });
  state.selected = id; await savePage(page); toast(type === 'text' ? '已添加文字' : '已添加色块');
}
function updateSelection() {
  const node = state.editor?.page.nodes.find(n => n.id === state.selected), box = $('selection-box'), page = state.editor?.page;
  if (!node || !state.editing || node.hidden) { box.style.display = 'none'; return; }
  Object.assign(box.style, { display: 'block', left: node.x / page.width * 100 + '%', top: node.y / page.height * 100 + '%', width: node.width / page.width * 100 + '%', height: node.height / page.height * 100 + '%' });
}
window.addEventListener('message', attempt(async event => {
  if (event.origin !== location.origin || event.source !== $('html-preview').contentWindow) return;
  const m = event.data.studioMessage; if (!m) return;
  if (m.type === 'select') selectNode(m.id);
  if (m.type === 'toggleMode') await setMode(!state.editing);
  if (m.type === 'symbol') { const result = await api('/api/symbol?name=' + encodeURIComponent(m.name) + '&color=' + encodeURIComponent(m.color)); $('html-preview').contentWindow.studioSymbol(m.key, result.data); }
  if (m.type === 'openURL') openExternal(m.url);
  if (m.type === 'resourceDrop') toast('请选择图层后，通过属性面板修改 iOS 外观');
}));
function openExternal(url) { const parsed = new URL(url); if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('只支持打开网页链接'); if (window.webkit?.messageHandlers?.native) window.webkit.messageHandlers.native.postMessage({ action: 'openURL', url: parsed.href }); else window.open(parsed.href, '_blank', 'noopener'); }
let frameURL = null, frameFailures = 0;
async function pollFrame() {
  try {
    const response = await fetch('/api/frame', { headers: { 'X-Client-Token': token } }); if (!response.ok) throw new Error('等待模拟器');
    const next = URL.createObjectURL(await response.blob()), previous = frameURL; frameURL = next; $('ios-frame').src = next; $('ios-frame').onload = () => { if (previous) URL.revokeObjectURL(previous); };
    $('ios-wait').classList.add('hidden'); frameFailures = 0;
  } catch { frameFailures++; if (frameFailures > 6) { $('ios-wait').textContent = '正在连接模拟器…'; $('ios-wait').classList.remove('hidden'); } }
  setTimeout(pollFrame, document.hidden ? 1500 : 150);
}
let inputSession = null, inputConnecting = false, inputQueue = [], inputSending = false, pointerDown = false;
async function connectInput() { if (state.editing || !state.project || inputConnecting || inputSession) return; inputConnecting = true; try { const result = await studio('/ios-input-connect', { id: state.project }); inputSession = result.session; } catch (error) { toast(error.message, true); } finally { inputConnecting = false; } }
async function disconnectInput() { const old = inputSession; inputSession = null; inputQueue = []; pointerDown = false; if (old) await studio('/ios-input-disconnect', { session: old }).catch(() => {}); }
function input(event) { if (!inputSession) return; if (event.kind === 'move' && inputQueue.at(-1)?.kind === 'move') inputQueue[inputQueue.length - 1] = event; else inputQueue.push(event); pumpInput(); }
async function pumpInput() {
  if (inputSending || !inputQueue.length || !inputSession) return; inputSending = true;
  try { await studio('/ios-input', { id: state.project, session: inputSession, events: inputQueue.splice(0, 16) }); } catch (error) { await disconnectInput(); toast(error.message, true); } finally { inputSending = false; if (inputQueue.length) pumpInput(); }
}
function point(event) { const b = $('ios-frame').getBoundingClientRect(); return { x: Math.max(0, Math.min(1, (event.clientX - b.left) / b.width)), y: Math.max(0, Math.min(1, (event.clientY - b.top) / b.height)) }; }
$('ios-device').onpointerdown = event => {
  const p = point(event); $('ios-device').focus();
  if (state.editing) { const page = state.editor?.page; if (!page) return; const n = [...page.nodes].reverse().find(n => !n.hidden && !n.locked && p.x * page.width >= n.x && p.x * page.width <= n.x + n.width && p.y * page.height >= n.y && p.y * page.height <= n.y + n.height); if (n) selectNode(n.id); return; }
  if (!inputSession) return; event.preventDefault(); pointerDown = true; $('ios-device').setPointerCapture(event.pointerId); input({ kind: 'down', ...p });
};
$('ios-device').onpointermove = event => { if (pointerDown) input({ kind: 'move', ...point(event) }); };
$('ios-device').onpointerup = event => { if (pointerDown) input({ kind: 'up', ...point(event) }); pointerDown = false; };
$('ios-device').onpointercancel = () => { if (pointerDown) input({ kind: 'cancel' }); pointerDown = false; };
$('ios-device').onkeydown = event => { if (state.editing || event.metaKey || event.ctrlKey || event.altKey) return; const codes = { Enter: 40, Escape: 41, Backspace: 42, Tab: 43 }; if (codes[event.key]) { event.preventDefault(); input({ kind: 'key', code: codes[event.key] }); } else if (event.key.length === 1) { event.preventDefault(); input({ kind: 'text', text: event.key }); } };
async function watchJob(endpoint, job, label) {
  for (;;) { const result = await studio(endpoint + '?job=' + encodeURIComponent(job)); const phase = result.status || result.state; if (result.error || phase === 'failed') throw new Error(result.error || label + '失败'); if (['done', 'completed', 'succeeded', 'success'].includes(phase) || result.path) { toast(label + '完成' + (result.path ? '：' + result.path : '')); return result; } $('sync-status').textContent = result.stage || label + '中…'; await new Promise(r => setTimeout(r, 1200)); }
}
$('repair').onclick = attempt(async () => { await studio('/repair-sync', { id: state.project }); await refreshEditor(true); toast('同步检查已完成'); });
$('run-ios').onclick = attempt(async () => { const r = await studio('/run-ios', { id: state.project }); await watchJob('/run-ios-status', r.job, 'iOS 启动'); });
$('export').onclick = attempt(async () => { if (!state.editor) return; $('export').disabled = true; try { const r = await studio('/export-start', { id: state.project, compileRevision: project().compileRevision, pages: [state.editor.page] }); await watchJob('/export-status', r.job, 'iOS 工程导出'); } finally { $('export').disabled = false; } });
async function boot() {
  icons();
  try {
    const s = await refreshRegistry(); state.project = state.projects.some(p => p.id === s.registry.selectedProject) ? s.registry.selectedProject : s.status.active || state.projects[0]?.id;
    state.thread = state.conversations.find(c => c.id === s.registry.selectedThread)?.id || null;if(state.thread)state.project=currentConversation().projectId; state.sequence = s.sequence;
    for (const request of s.pendingRequests) state.requests.set(String(request.id), request);
    connectEvents();
    if (state.project && project()?.nativePreview && s.status.active !== previewId()) await api('/api/project/activate', { id: state.project });
    if (state.thread) loadHistory((await api('/api/history?id=' + state.thread)).thread);
    renderSidebar(); renderRequests(); await refreshEditor(true);
  } catch (error) { toast(error.message, true); }
  await loadCodex(); if(!nativeHost)pollFrame(); setInterval(() => { if (!nativeHost && !document.hidden && !state.switching) refreshEditor().catch(() => {}); }, 1200);
  try{const panels=JSON.parse(localStorage.getItem('studio-panels'));if(panels){window.setClientPanel('left',panels.left);window.setClientPanel('right',panels.right)}}catch{}
  window.reportNativeLayout();
  applyZoom(true);
  setInterval(()=>{if(!document.hidden)refreshUsage()},60000);
  let sidebarBusy=false;setInterval(async()=>{if(document.hidden||state.switching||sidebarBusy||$('dialog').open||!$('sidebar-menu').classList.contains('hidden'))return;sidebarBusy=true;try{await refreshRegistry(false,true);const c=currentConversation();if(c&&c.updatedAt!==displayedThreadUpdate&&!state.running[state.thread]){await syncConversationTail();displayedThreadUpdate=c.updatedAt}}catch{$('sidebar-sync-state').textContent='同步中断，点击菜单重试'}finally{sidebarBusy=false}},2000);
  setInterval(()=>syncConversationTail().catch(()=>{}),1500);
  addEventListener('focus',scheduleSidebarSync);document.addEventListener('visibilitychange',()=>{if(!document.hidden)scheduleSidebarSync()});
}
window.nativeProjectChanged=async id=>{
  if(!nativeHost || !id || id===previewId())return;
  try{await api('/api/project/activate',{id});state.project=id;state.thread=null;state.selected=null;state.items.clear();await refreshRegistry();await refreshEditor();renderMessages(true);renderRequests()}
  catch(error){toast(error.message,true);if(state.project)nativeMessage({action:'project',id:previewId()})}
};
boot();

let capabilityData=null,capabilityTab='skills',capabilityBusy=false;
function renderSelectedSkills(){
  $('selected-skills').innerHTML=state.selectedSkills.map((s,i)=>`<div class="attachment skill-chip">${icon('sparkles')}<span>${escape(s.name)}</span><button type="button" data-remove-skill="${i}" aria-label="移除技能 ${escape(s.name)}">${icon('x')}</button></div>`).join('');
  $('selected-skills').querySelectorAll('[data-remove-skill]').forEach(b=>b.onclick=()=>{state.selectedSkills.splice(Number(b.dataset.removeSkill),1);renderSelectedSkills()});icons();
}
function renderCapabilities(){
  const q=$('capability-search').value.toLowerCase().trim(),all=$('capability-all').checked;
  $('capability-all-label').hidden=capabilityTab!=='skills';
  const rows=capabilityTab==='skills'?capabilityData.skills.filter(s=>(all||s.enabled)&&`${s.name} ${s.description}`.toLowerCase().includes(q)):capabilityTab==='plugins'?capabilityData.plugins.filter(p=>`${p.label} ${p.description}`.toLowerCase().includes(q)):capabilityData.apps.filter(a=>a.runtimeName.toLowerCase().includes(q));
  $('capability-count').textContent=`${rows.length} 项 · 与 Codex 共用`;
  $('capability-list').innerHTML=rows.map((r,i)=>{
    if(capabilityTab==='skills')return `<div class="capability-row"><div><strong>${escape(r.interface?.displayName||r.name)}</strong><small>${escape(r.shortDescription||r.description)}</small><span class="capability-status">${escape(r.name)} · ${r.enabled?'已启用':'已停用'}</span></div><div class="capability-actions"><button type="button" class="secondary" data-use-skill="${i}" ${r.enabled?'':'disabled'}>使用</button><button type="button" class="subtle" data-toggle-skill="${i}">${r.enabled?'停用':'启用'}</button></div></div>`;
    if(capabilityTab==='plugins')return `<div class="capability-row"><div><strong>${escape(r.label)}</strong><small>${escape(r.description)}</small><span class="capability-status">${r.enabled?'已启用':'已停用'}${r.version?' · '+escape(r.version):''}</span></div><button type="button" class="secondary" data-plugin-skills="${i}">查看技能</button></div>`;
    return `<div class="capability-row"><div><strong>${escape(r.runtimeName)}</strong><small>${r.callable?'当前连接可调用':r.enabled?'已启用，当前未就绪':'已停用'}</small></div>${icon(r.callable?'circle-check':'circle-minus')}</div>`;
  }).join('')||'<p class="dialog-description">没有匹配的项目</p>';
  $('capability-list').querySelectorAll('[data-use-skill]').forEach(b=>b.onclick=()=>{const s=rows[Number(b.dataset.useSkill)];if(!state.selectedSkills.some(x=>x.path===s.path))state.selectedSkills.push({name:s.name,path:s.path});renderSelectedSkills();$('dialog').close();$('prompt').focus()});
  $('capability-list').querySelectorAll('[data-toggle-skill]').forEach(b=>b.onclick=attempt(async()=>{const s=rows[Number(b.dataset.toggleSkill)];b.disabled=true;try{await api('/api/skill/toggle',{projectId:state.project,path:s.path,enabled:!s.enabled});await reloadCapabilities(true)}finally{b.disabled=false}}));
  $('capability-list').querySelectorAll('[data-plugin-skills]').forEach(b=>b.onclick=()=>{const p=rows[Number(b.dataset.pluginSkills)];capabilityTab='skills';$('capability-search').value=p.name+':';$('capability-tabs').querySelectorAll('button').forEach(x=>x.classList.toggle('selected',x.dataset.capabilityTab==='skills'));renderCapabilities()});
  icons();
}
async function reloadCapabilities(force=false){
  if(capabilityBusy)return;capabilityBusy=true;$('capability-refresh').disabled=true;
  try{capabilityData=await api('/api/capabilities?'+new URLSearchParams({...state.project?{projectId:state.project}:{},...force?{refresh:'1'}:{}}));if(!$('capability-list'))return;renderCapabilities();$('capability-note').textContent=capabilityData.errors.length?'部分项目加载失败，请刷新重试':'技能和插件直接读取 Codex。选择技能后，随下一条消息使用；刷新列表不会调用模型。';}
  catch(error){if($('capability-note'))$('capability-note').textContent='同步失败：'+error.message}
  finally{capabilityBusy=false;if($('capability-refresh'))$('capability-refresh').disabled=false}
}
async function showCapabilities(tab='skills'){
  capabilityTab=tab;
  showDialog('技能与插件',`<div class="capability-toolbar"><div id="capability-tabs" class="segmented"><button type="button" data-capability-tab="skills" class="${tab==='skills'?'selected':''}">技能</button><button type="button" data-capability-tab="plugins" class="${tab==='plugins'?'selected':''}">已安装插件</button><button type="button" data-capability-tab="apps">已连接应用</button></div><button type="button" id="capability-refresh" class="icon-btn" aria-label="刷新技能和插件">${icon('refresh-cw')}</button></div><label class="field"><input id="capability-search" placeholder="搜索 imagegen、技能或插件…"></label><div class="capability-filter"><span id="capability-count">正在同步…</span><label id="capability-all-label"><input id="capability-all" type="checkbox"> 显示已停用</label></div><div id="capability-list" class="capability-list"></div><p id="capability-note" class="inspector-note">正在读取 Codex 中已安装的技能和插件…</p>`,'完成',async()=>{});
  $('dialog').classList.add('capabilities-dialog');
  $('capability-tabs').querySelectorAll('button').forEach(b=>b.onclick=()=>{capabilityTab=b.dataset.capabilityTab;$('capability-tabs').querySelectorAll('button').forEach(x=>x.classList.toggle('selected',x===b));if(capabilityData)renderCapabilities()});
  $('capability-search').oninput=()=>{if(capabilityData)renderCapabilities()};$('capability-all').onchange=()=>{if(capabilityData)renderCapabilities()};$('capability-refresh').onclick=()=>reloadCapabilities(true);
  await reloadCapabilities(true);
}
$('dialog').addEventListener('close',()=>{$('dialog').classList.remove('capabilities-dialog')});
$('skills-nav').onclick=()=>showCapabilities('skills');$('plugins-nav').onclick=()=>showCapabilities('plugins');$('choose-skill').onclick=()=>showCapabilities('skills');
let tailSyncBusy=false,lastTailSignature='',lastTailThread='';
async function syncConversationTail(){
  const id=state.thread;
  if(!id||document.hidden||$('dialog').open||state.switching||state.pendingSend||tailSyncBusy)return;
  tailSyncBusy=true;const startSequence=state.sequence;
  try{
    const value=await api('/api/history?id='+encodeURIComponent(id)+'&tail=1'+(lastTailThread===id?'&revision='+encodeURIComponent(lastTailSignature):''));
    if(state.thread!==id||state.switching||state.sequence!==startSequence)return;
    if(value.unchanged)return;
    const active=state.running[id];if(active&&value.thread.turns.some(t=>t.id===active&&['completed','failed','interrupted'].includes(t.status)))delete state.running[id];
    lastTailThread=id;lastTailSignature=value.revision;delete state.remoteRunning[id];
    for(const turn of value.thread.turns||[]){for(const item of turn.items||[])state.items.set(item.id,{...item,_turnId:turn.id});if(turn===value.thread.turns.at(-1)&&turn.status==='inProgress')state.remoteRunning[id]=turn.id;if(turn.error)state.items.set('error:'+turn.id,{type:'clientError',text:turn.error.message})}
    renderMessages();updateRunning();
  }finally{tailSyncBusy=false}
}

$('memory-nav').onclick=attempt(async()=>{
  const value=await api('/api/memory');
  showDialog('Codex 记忆',`<p class="dialog-description">${value.enabled&&value.useMemories?'工作台已开启读取 Codex 记忆':'Codex 当前未启用记忆读取'}。共用原目录，记忆内容由 Codex 维护；工作台不额外启动后台记忆提取。</p><div class="memory-location">${escape(value.directory)}</div><p class="inspector-note">${value.updatedAt?'更新于 '+new Date(value.updatedAt).toLocaleString('zh-CN'):'还没有记忆摘要'}</p><div class="memory-summary">${value.summary?markdown(value.summary):'<p>Codex 创建记忆后会在这里显示。</p>'}</div>`,'完成',async()=>{});
  $('dialog').classList.add('memory-dialog');
});
$('dialog').addEventListener('close',()=>{$('dialog').classList.remove('memory-dialog')});

installAnnotation({
  nativeHost,nativeMessage,toast,icons,
  getAttachment:id=>state.attachments.find(a=>a.id===id),
  async commit(blob,editingId){
    if(!editingId&&state.attachments.length>=6)throw new Error('每次最多附加 6 个文件，请先移除一个');
    const file=new File([blob],'标注-'+new Date().toISOString().replace(/[:.]/g,'-')+'.png',{type:'image/png'});
    if(editingId){const index=state.attachments.findIndex(a=>a.id===editingId);if(index<0)throw new Error('原附件已移除');const data=await new Promise(resolve=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.readAsDataURL(file)});const result=await api('/api/upload',{data,name:file.name});URL.revokeObjectURL(state.attachments[index].preview);state.attachments[index]={...result,preview:URL.createObjectURL(file)};renderAttachments();}
    else await addFiles([file]);
    $('prompt').focus();toast('标注图片已添加，请输入修改要求后发送');
  }
});

// Keep protected conversation images inside the authenticated workbench.
const imageViewer=document.createElement('div');imageViewer.id='image-viewer';imageViewer.className='hidden';imageViewer.setAttribute('role','dialog');imageViewer.setAttribute('aria-label','图片预览');imageViewer.setAttribute('aria-modal','true');
imageViewer.innerHTML='<button class="viewer-close" aria-label="关闭图片预览">×</button><div class="viewer-stage"><img alt="原图预览" draggable="false"></div><div class="viewer-controls"><button data-zoom="-1" aria-label="缩小图片">−</button><button data-zoom="0" aria-label="重置图片缩放">100%</button><button data-zoom="1" aria-label="放大图片">＋</button><button class="viewer-attach">添加到输入框</button></div>';
document.body.append(imageViewer);
let viewerZoom=1,viewerSource='',viewerFocus=null;
const viewerImage=imageViewer.querySelector('img'),viewerStage=imageViewer.querySelector('.viewer-stage');
function setViewerZoom(value){viewerZoom=Math.min(5,Math.max(.25,value));viewerImage.style.width=(viewerImage.naturalWidth*viewerZoom)+'px';viewerImage.style.height=(viewerImage.naturalHeight*viewerZoom)+'px';imageViewer.querySelector('[data-zoom="0"]').textContent=Math.round(viewerZoom*100)+'%'}
function closeImageViewer(){document.body.classList.remove('viewing-image');document.querySelector('.app').inert=false;document.querySelector('.client-topbar').inert=false;imageViewer.classList.add('hidden');window.imageViewerActive=false;window.reportNativeLayout();viewerFocus?.focus?.()}
function openImageViewer(src){viewerFocus=document.activeElement;viewerSource=src;viewerImage.onload=()=>setViewerZoom(Math.min(1,(innerWidth-100)/viewerImage.naturalWidth,(innerHeight-150)/viewerImage.naturalHeight));viewerImage.src=src;document.body.classList.add('viewing-image');document.querySelector('.app').inert=true;document.querySelector('.client-topbar').inert=true;imageViewer.classList.remove('hidden');window.imageViewerActive=true;window.reportNativeLayout();imageViewer.querySelector('.viewer-close').focus()}
imageViewer.querySelector('.viewer-close').onclick=e=>{e.preventDefault();e.stopPropagation();closeImageViewer()};
viewerStage.onclick=e=>{if(e.target===viewerStage)closeImageViewer()};
imageViewer.querySelectorAll('[data-zoom]').forEach(b=>b.onclick=()=>setViewerZoom(Number(b.dataset.zoom)===0?1:viewerZoom*(Number(b.dataset.zoom)>0?1.25:.8)));
imageViewer.addEventListener('keydown',e=>{if(e.key==='Escape'){e.preventDefault();e.stopPropagation();closeImageViewer()}if(e.key==='Tab'){const buttons=[...imageViewer.querySelectorAll('button')],i=buttons.indexOf(document.activeElement);e.preventDefault();buttons[(i+(e.shiftKey?-1:1)+buttons.length)%buttons.length].focus()}});
function localImageUrl(src){try{const url=new URL(src,location.href);return url.origin===location.origin&&/^\/api\/conversation-media\/[a-f0-9-]+$/.test(url.pathname)?url.pathname:null}catch{return null}}
async function attachConversationImage(src){const url=localImageUrl(src);if(!url)throw new Error('请拖入聊天记录中的图片或本地图片文件');const response=await fetch(url);if(!response.ok)throw new Error('图片读取失败，请刷新对话后重试');const blob=await response.blob();if(!blob.type.startsWith('image/'))throw new Error('不是有效图片');await addFiles([new File([blob],'参考图片.'+(blob.type.split('/')[1]||'png'),{type:blob.type})]);$('prompt').focus();toast('图片已添加到输入框')}
imageViewer.querySelector('.viewer-attach').onclick=attempt(async()=>{await attachConversationImage(viewerSource);closeImageViewer();$('prompt').focus()});
$('messages').addEventListener('click',e=>{const img=e.target.closest('img')||e.target.closest('.user-image-thumb')?.querySelector('img');if(!img)return;e.preventDefault();e.stopPropagation();openImageViewer(img.src)},true);
$('messages').addEventListener('dragstart',e=>{const img=e.target.closest('img')||e.target.closest('.user-image-thumb')?.querySelector('img');if(!img||!localImageUrl(img.src))return;e.dataTransfer.setData('application/x-workbench-image',img.src);e.dataTransfer.setData('text/uri-list',img.src);e.dataTransfer.effectAllowed='copy'});
const dropArea=document.querySelector('.composer-wrap');
dropArea.addEventListener('dragover',e=>{e.preventDefault();e.dataTransfer.dropEffect='copy';dropArea.classList.add('image-drop-target')});
dropArea.addEventListener('dragleave',e=>{if(!dropArea.contains(e.relatedTarget))dropArea.classList.remove('image-drop-target')});
dropArea.addEventListener('drop',attempt(async e=>{e.preventDefault();e.stopPropagation();dropArea.classList.remove('image-drop-target');const entries=[...e.dataTransfer.items].map(i=>i.webkitGetAsEntry?.()).filter(Boolean);if(nativeHost&&[...e.dataTransfer.types].includes('Files'))return;if(entries.some(x=>x.isDirectory)){const paths=e.dataTransfer.getData('text/uri-list').split('\n').filter(x=>x.startsWith('file:'));if(paths.length){await window.receiveComposerFiles(paths);return}throw new Error('浏览器不能提供文件夹的本机路径，请在桌面应用中拖入。');}const files=[...e.dataTransfer.files];if(files.length){await addFiles(files);$('prompt').focus();return}const src=e.dataTransfer.getData('application/x-workbench-image')||e.dataTransfer.getData('text/uri-list').split('\n').find(s=>s&&!s.startsWith('#'));if(src)await attachConversationImage(src)}));

async function showConnectWorkbench(id=state.project){
 const p=state.projects.find(p=>p.id===id);if(!p)return toast('请先选择一个项目',true);
 const value=await api('/api/project/preview-options');
 showDialog('接入工作台',`<p class="dialog-description">为「${escape(p.name)}」关联手机预览，同一项目的对话共用此关联。支持空文件夹和空 iOS 工程，所需文件会放入独立的 HTMLNativeStudio 文件夹。</p><label class="field">预览来源<select id="workbench-link-target"><option value="">自动接入当前项目（创建或复用工作台目录）</option>${value.projects.map(n=>`<option value="${escape(n.id)}" ${n.id===p.nativeProjectId?'selected':''}>${escape(n.name)} · ${escape(n.sourcePath)}</option>`).join('')}</select></label><p class="dialog-description">自动接入会创建空白手机页面、配置和编写规范，保留外层原有工程。也可以选择已有工作台作为预览来源。</p>`,'接入',async()=>{const result=await api('/api/project/connect',{id,nativeId:$('workbench-link-target').value||undefined});const keepThread=state.project===id?state.thread:null;await refreshRegistry(true);state.project=result.projectId;state.thread=keepThread;if(!keepThread){state.items.clear();renderMessages(true)}state.editor=null;renderSidebar();await refreshEditor(true);toast('已按项目关联手机预览')});
}
$('connect-workbench').onclick=attempt(()=>showConnectWorkbench());

function showRemoveProject(id){
 const p=state.projects.find(p=>p.id===id);if(!p)return;
 showDialog('移除项目',`<p class="dialog-description">将「${escape(p.name)}」从${p.codexId?'工作台和 Codex 的项目列表':'工作台项目列表'}移除。电脑上的源码文件夹和工作台文件会保留，之后可以通过“添加项目”重新接入。</p>`,'移除项目',async()=>{
  await api('/api/project/remove',{id});
  if(state.project===id){window.cancelWorkbenchAnnotation?.();await disconnectInput();state.project=null;state.editor=null;state.selected=null;}
  expandedProjectIds.delete(id);saveSidebarPrefs();state.projects=state.projects.filter(p=>p.id!==id);state.conversations.forEach(c=>{if(c.projectId===id)c.projectId=null});renderSidebar();toast('项目已移除，本地文件已保留');refreshRegistry(true).catch(()=>{});
 });
}

$('messages').addEventListener('click',e=>{const link=e.target.closest('a');const match=link?.getAttribute('href')?.match(/^\/api\/conversation-file\/([a-f0-9-]+)$/);if(!match)return;e.preventDefault();e.stopPropagation();attempt(()=>api('/api/conversation-file/reveal',{id:match[1]}))()},true);

window.receiveComposerFiles=attempt(async paths=>{
 if(state.attachments.length+paths.length>6)throw new Error('每次最多附加 6 个文件或文件夹');
 const result=await api('/api/attachment/local',{paths});state.attachments.push(...result.attachments);renderAttachments();$('prompt').focus();window.reportNativeLayout();
});
window.composerDropError=message=>toast(message,true);
window.imageCopyFinished=ok=>toast(ok?'图片已复制到电脑剪贴板':'图片复制失败',!ok);
async function copyWorkbenchImage(src){
 const response=await fetch(src);if(!response.ok)throw new Error('图片读取失败');const blob=await response.blob();
 if(window.webkit?.messageHandlers?.native){const data=await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=reject;reader.readAsDataURL(blob)});nativeMessage({action:'copyImage',data});}
 else{const bitmap=await createImageBitmap(blob),canvas=document.createElement('canvas');canvas.width=bitmap.width;canvas.height=bitmap.height;canvas.getContext('2d').drawImage(bitmap,0,0);bitmap.close();const png=await new Promise(resolve=>canvas.toBlob(resolve,'image/png'));await navigator.clipboard.write([new ClipboardItem({'image/png':png})]);window.imageCopyFinished(true);}
}
const copyViewer=document.createElement('button');copyViewer.type='button';copyViewer.textContent='复制图片';copyViewer.onclick=attempt(()=>copyWorkbenchImage(viewerSource));imageViewer.querySelector('.viewer-controls').append(copyViewer);
for(const container of [$('attachments'),$('messages')])container.addEventListener('contextmenu',e=>{const img=e.target.closest('img');if(!img)return;e.preventDefault();showSidebarMenu(img,[{label:'复制图片',icon:'copy',run:()=>copyWorkbenchImage(img.src)}])});

window.receivePreviewMode=running=>{state.editing=!running;for(const [id,selected] of [['top-edit-mode',!running],['top-run-mode',running],['edit-mode',!running],['run-mode',running]]){$(id).classList.toggle('selected',selected);$(id).setAttribute('aria-pressed',String(selected))}};
for(const [id,running] of [['top-edit-mode',false],['top-run-mode',true]])$(id).onclick=attempt(async()=>{if(!project()||project().nativePreview===false){toast('请先选择已接入工作台的项目');return}if(nativeHost)nativeMessage({action:'previewMode',running});else await setMode(!running)});

// Keep ordinary typing and IME input free of mode-switch shortcuts.
document.addEventListener('keydown',event=>{
 if(event.code!=='KeyW'||!event.metaKey||event.ctrlKey||event.altKey||event.shiftKey||event.repeat||event.isComposing)return;
 if($('dialog').open||window.imageViewerActive||window.annotationActive)return;
 event.preventDefault();event.stopPropagation();$(state.editing?'top-run-mode':'top-edit-mode').click();
},true);

window.receiveClipboardImage=attempt(async data=>{
 const blob=await (await fetch(data)).blob();await addFiles([new File([blob],'剪贴板图片.png',{type:'image/png'})]);$('prompt').focus();window.reportNativeLayout();
});

$('prompt').addEventListener('keydown',event=>{
 if(nativeHost&&event.metaKey&&!event.ctrlKey&&!event.altKey&&event.code==='KeyV'&&!event.isComposing){event.preventDefault();event.stopPropagation();nativeMessage({action:'pasteClipboard'});}
});
window.receiveClipboardText=text=>{const input=$('prompt');input.setRangeText(text,input.selectionStart,input.selectionEnd,'end');input.dispatchEvent(new Event('input'));};

function topIOSAction(action){if(!project()||project().nativePreview===false){toast('请先选择已接入工作台的项目');return}if(!nativeHost){toast('请在桌面工作台使用，或通过后台镜像操作');return}nativeMessage({action:'iosToolbar',command:action})}
$('top-run-ios').onclick=()=>topIOSAction('run');$('top-link-ios').onclick=()=>topIOSAction('link');
$('top-sync-menu').onclick=()=>showSidebarMenu($('top-sync-menu'),[{label:'检查并修复同步',icon:'refresh-cw',run:()=>topIOSAction('repair')},{label:'查看同步详情',icon:'info',run:()=>topIOSAction('details')}]);
window.receiveSyncStatus=text=>{$('top-sync-menu').textContent=(text||'同步状态')+' ▾';$('top-sync-menu').title=(text||'同步状态')+' · 点击检查并修复同步';};

for(const scroller of document.querySelectorAll('.client-topbar,.topbar-center')){
 let hideScrollTimer;
 scroller.addEventListener('scroll',()=>{scroller.classList.add('scrolling');clearTimeout(hideScrollTimer);hideScrollTimer=setTimeout(()=>scroller.classList.remove('scrolling'),800)},{passive:true});
}

// Editing tool shortcuts leave text fields and IME input untouched.
document.addEventListener('keydown',event=>{
 const tool={KeyA:'move',KeyS:'resize',KeyD:'rotate'}[event.code];
 if(!tool||!event.metaKey||event.ctrlKey||event.altKey||event.shiftKey!==(event.code==='KeyS')||event.repeat||event.isComposing)return;
 const element=document.activeElement;
 if(element?.isContentEditable||((element?.tagName==='INPUT'||element?.tagName==='TEXTAREA')&&!element.readOnly&&!element.disabled))return;
 if(!nativeHost||!state.editing||$('dialog').open||window.imageViewerActive||window.annotationActive)return;
 event.preventDefault();event.stopPropagation();nativeMessage({action:'editorTool',tool});
},true);

