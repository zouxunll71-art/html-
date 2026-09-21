import {pathKey} from './project-paths.mjs';
// Public App Server APIs are the source of truth; never read or edit Codex databases.
export class SidebarSync {
  constructor(rpc){this.rpc=rpc;this.cached=null;this.at=0;this.pending=null;this.threads=new Map();this.projects=new Map();}
  invalidate(){this.at=0;}
  async pages(method,params={}){let data=[],cursor=null;do{const page=await this.rpc.call(method,{...params,limit:100,cursor});data.push(...page.data);cursor=page.nextCursor;}while(cursor);return data;}
  async read(force=false){
    if(!force&&this.cached&&Date.now()-this.at<8000)return this.cached;
    if(this.pending)return this.pending;
    this.pending=(async()=>{await this.rpc.start();const [projects,threads,sections]=await Promise.all([this.pages('project/list'),this.pages('thread/list',{sortKey:'updated_at',useStateDbOnly:true}),this.pages('threadSection/list')]);
      this.projects=new Map(projects.map(p=>[p.id,p]));this.threads=new Map(threads.map(t=>[t.id,t]));this.cached={projects,threads,sections,updatedAt:Date.now()};this.at=Date.now();return this.cached;
    })().finally(()=>{this.pending=null});return this.pending;
  }
}
export function mergedSidebar(nativeProjects,owned,catalog,bindings={},hiddenNativeProjects=[]){
  const nativeByPath=new Map(nativeProjects.map(p=>[pathKey(p.sourcePath),p]));
  const projects=catalog.projects.map(p=>{const sourcePath=p.roots[0]?.path||'',native=nativeProjects.find(n=>n.id===bindings[p.id])||nativeByPath.get(pathKey(sourcePath)),linked=!!bindings[p.id];return {...(native||{}),id:linked?'codex:'+p.id:native?.id||'codex:'+p.id,codexId:p.id,name:p.name,sourcePath,sourceRoots:p.roots.map(r=>r.path),nativeProjectId:native?.id,previewSourcePath:native?.sourcePath,nativePreview:!!native};});
  for(const p of nativeProjects)if(!hiddenNativeProjects.includes(p.id)&&!projects.some(x=>x.id===p.id||x.nativeProjectId===p.id))projects.push({...p,nativePreview:true});
  const pinned=catalog.sections.find(s=>s.name==='Pinned');const own=new Map(owned.map(c=>[c.id,c]));
  const conversations=catalog.threads.map(t=>{const local=own.get(t.id),p=resolveThreadProject(t,local,projects);return {...local,id:t.id,projectId:p?.id||null,sourcePath:t.cwd,title:t.name||local?.title||t.preview?.replace(/\s+/g,' ').slice(0,80)||'新对话',createdAt:t.createdAt*1000,updatedAt:(t.recencyAt||t.updatedAt)*1000,pinned:!!pinned&&t.section?.id===pinned.id,sectionId:t.section?.id||null,external:!local||!!local.external,archived:false,hasStarted:true};});
  for(const c of owned)if(!conversations.some(t=>t.id===c.id)&&!c.external&&!c.archived&&c.hasStarted===false)conversations.push(c);
  return {projects,conversations,sections:catalog.sections,updatedAt:catalog.updatedAt};
}

export function resolveThreadProject(thread,local,projects){
 // Explicit official association wins. Saved client association survives a moved root.
 const explicit=projects.find(p=>p.codexId===thread.projectId);
 if(explicit)return explicit;
 const saved=projects.find(p=>p.id===local?.projectId);
 if(saved)return saved;
 const cwd=pathKey(thread.cwd);
 if(!cwd)return undefined;
 const matches=projects.flatMap(p=>(p.sourceRoots||[p.sourcePath]).filter(Boolean).map(root=>({p,root:pathKey(root)}))).filter(({root})=>cwd===root||cwd.startsWith(root+'/'));
 matches.sort((a,b)=>b.root.length-a.root.length);
 return matches[0]?.p;
}
