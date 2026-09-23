import UIKit

extension StudioController {
 func editorObject(_ value:StudioProject)throws->[String:Any] {try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]}
 func editorDraftURL(_ id:String)->URL {
  let root=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("HTMLNativeStudio-CodexClient/EditorDrafts",isDirectory:true)
  return root.appendingPathComponent(id+".json")
 }
 func journalEditorDraft(archive:Bool=false)->Bool {
  guard let p=project,let base=editorBase else{return true}
  do {
   let local=try editorObject(p),original=try editorObject(base)
   guard !EditorRebase.changedPages(base:original,local:local).isEmpty else{return true}
   let url=editorDraftURL(p.id);try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
   let body:[String:Any]=["base":original,"local":local,"savedAt":Date().timeIntervalSince1970]
   let data=try JSONSerialization.data(withJSONObject:body,options:[.sortedKeys])
   try data.write(to:url,options:.atomic)
   if archive {try data.write(to:url.deletingPathExtension().appendingPathExtension(String(Int(Date().timeIntervalSince1970*1000))+".json"),options:.atomic)}
   return true
  } catch {setStatus("布局草稿备份失败，已保留当前编辑："+error.localizedDescription);return false}
 }
 func beginEditorSnapshot(_ fresh:StudioProject) {
  editorBase=fresh
  guard let data=try? Data(contentsOf:editorDraftURL(fresh.id)),let body=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let base=body["base"] as? [String:Any],let local=body["local"] as? [String:Any],let remote=try? editorObject(fresh) else{return}
  let merged=EditorRebase.merge(base:base,local:local,remote:remote)
  if let data=try? JSONSerialization.data(withJSONObject:merged.project),let recovered=try? JSONDecoder().decode(StudioProject.self,from:data){project=recovered;dirty=EditorRebase.changedPages(base:remote,local:merged.project).contains(page?.id ?? "");if !merged.unresolved.isEmpty{setStatus("部分旧图层已变化，原布局草稿保留在 EditorDrafts")}}
 }
 func acceptEditorSnapshot(_ fresh:StudioProject,raw:[String:Any],revision:Int) {
  guard let local=project,fresh.id==local.id else{return}
  let route=raw["id"] as? String ?? ""
  do {
   let base=editorBase ?? local,original=try editorObject(base),current=try editorObject(local),remote=try editorObject(fresh)
   let changes=EditorRebase.changedPages(base:original,local:current)
   if !changes.isEmpty && !journalEditorDraft(archive:base.compileRevision != fresh.compileRevision){
    project?.assets=fresh.assets;reloadCatalog();return
   }
   let result=EditorRebase.merge(base:original,local:current,remote:remote)
   let next=try JSONDecoder().decode(StudioProject.self,from:JSONSerialization.data(withJSONObject:result.project))
   // Rebase undo snapshots as well: undo must not resurrect an old asset catalog or delete new layers.
   func history(_ values:[Data])->[Data] {values.compactMap{data in
    guard let old=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{return nil}
    return try? JSONSerialization.data(withJSONObject:EditorRebase.merge(base:original,local:old,remote:remote).project)
   }}
   if base.compileRevision != fresh.compileRevision{undoStates=history(undoStates);redoStates=history(redoStates);assetCache.removeAll();libraryThumbs.removeAll()}
   let changed = !NSDictionary(dictionary:rawScene).isEqual(to:raw) || !EditorRebase.equal(current,result.project)
   project=next;editorBase=fresh;rawScene=raw;activePage=route;observedRevision=revision
   if let index=next.pages.firstIndex(where:{$0.id==route}){pageIndex=index}
   pageIndex=min(pageIndex,max(0,next.pages.count-1))
   if let id=selected,page?.nodes.contains(where:{$0.id==id}) != true{selected=nil}
   multiSelection=multiSelection.intersection(Set(page?.nodes.map{$0.id} ?? []))
   dirty=EditorRebase.changedPages(base:remote,local:result.project).contains(route)
   closeWebButton.isHidden = !(raw["browserOpen"] as? Bool ?? false)
   if changed{view.setNeedsLayout();updatePage()}else{reloadCatalog()}
   if dirty {saveTimer?.invalidate();saveTimer=Timer.scheduledTimer(withTimeInterval:0.2,repeats:false){[weak self]_ in self?.save(silent:true)}}
   if !result.unresolved.isEmpty{setStatus("资源库已更新；已变化图层的旧调整保留在 EditorDrafts")}
  } catch {setStatus("编辑器更新失败，已保留当前布局："+error.localizedDescription)}
 }
 func editorSaveCompleted(_ sent:StudioProject,pageID:String,generation:Int) {
  guard project?.id==sent.id else{return}
  if let index=editorBase?.pages.firstIndex(where:{$0.id==pageID}),let saved=sent.pages.first(where:{$0.id==pageID}){editorBase?.pages[index]=saved}
  if editGeneration==generation,!historyGesture {dirty=false}
  if let local=project,let base=editorBase,let a=try? editorObject(base),let b=try? editorObject(local),EditorRebase.changedPages(base:a,local:b).isEmpty {try? FileManager.default.removeItem(at:editorDraftURL(local.id))}else{_ = journalEditorDraft()}
 }
 func editorSyncFailure(_ error:Error) {
  _ = journalEditorDraft(archive:true)
  // Version/route conflicts are recoverable only by fetching a new snapshot, never by retrying an old body.
  observedRevision = -1
  setStatus(error.localizedDescription+"；正在刷新资源与编辑数据")
  pollRoute()
 }
}
