// The same Codex runtime owns installation and enablement. No mirrored registry.
export class Capabilities {
  constructor(rpc){this.rpc=rpc;this.cache=new Map();this.pending=new Map();}
  invalidate(){this.cache.clear();}
  async read(cwd,force=false){
    const cached=this.cache.get(cwd);
    if(!force&&cached&&Date.now()-cached.updatedAt<30000)return cached;
    if(this.pending.has(cwd))return this.pending.get(cwd);
    const task=(async()=>{
      await this.rpc.start();
      // Installed remote plugins must be materialized before scanning their skills.
      const plugins=await this.rpc.call('plugin/installed',{cwds:[cwd]});
      const [skills,apps]=await Promise.all([this.rpc.call('skills/list',{cwds:[cwd],forceReload:true}),this.rpc.call('app/installed',{})]);
      const value={cwd,updatedAt:Date.now(),skills:skills.data.flatMap(e=>e.skills),plugins:plugins.marketplaces.flatMap(m=>m.plugins.filter(p=>p.installed).map(p=>({id:p.id,name:p.name,label:p.interface?.displayName||p.name,description:p.interface?.shortDescription||'',enabled:p.enabled,version:p.localVersion||p.version,marketplace:m.name,disabledReason:p.disabledReason}))),apps:apps.apps,errors:[...plugins.marketplaceLoadErrors,...skills.data.flatMap(e=>e.errors)]};
      this.cache.set(cwd,value);return value;
    })().finally(()=>this.pending.delete(cwd));this.pending.set(cwd,task);return task;
  }
  async inputs(cwd,selected){
    const catalog=await this.read(cwd,!!selected?.length);
    if(!selected?.length)return [];
    return [...new Set(selected)].map(path=>{const skill=catalog.skills.find(s=>s.path===path&&s.enabled);if(!skill)throw new Error('所选技能已停用或不存在，请重新选择');return {type:'skill',name:skill.name,path:skill.path};});
  }
}
