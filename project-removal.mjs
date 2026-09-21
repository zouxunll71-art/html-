// Remove a sidebar registration only. No source files or thread records are deleted here.
export async function removeProject(p,{rpc,registry,runningThreadIds=[],conversations=[]}){
 if(runningThreadIds.some(id=>conversations.some(c=>c.id===id&&(c.projectId===p.id||c.sourcePath===p.sourcePath))))throw new Error('此项目还有正在执行的对话，请等待完成后移除');
 if(p.codexId)await rpc.call('project/delete',{projectId:p.codexId});
 const nativeId=p.nativeProjectId||(p.nativePreview?p.id:null);
 if(nativeId)registry.hiddenNativeProjects=[...new Set([...(registry.hiddenNativeProjects||[]),nativeId])];
 if(p.codexId&&registry.previewBindings)delete registry.previewBindings[p.codexId];
 for(const c of registry.conversations)if(c.projectId===p.id)c.projectId=null;
 if(registry.selectedProject===p.id)registry.selectedProject=null;
}
