"""Patch the generated host only through the maintained native source pipeline."""
def patch(source):
 def replace(old,new):
  nonlocal source
  if old not in source:raise RuntimeError('Editor sync integration anchor missing: '+old[:90])
  source=source.replace(old,new,1)
 replace(' var editGeneration=0;', ' var editorBase:StudioProject?\n var editGeneration=0;')
 replace('reloadCatalog();updatePage()\n  Bridge.shared.json("/activate-project"', 'beginEditorSnapshot(p);reloadCatalog();updatePage()\n  Bridge.shared.json("/activate-project"')
 replace('dirty=true;updatePage();saveTimer', 'dirty=true;_ = journalEditorDraft();updatePage();saveTimer')
 replace('func pollRoute(){guard !liveStatusBusy,!historyGesture,!dirty,!scrollRelay.isActive else{return}', 'func pollRoute(){guard !liveStatusBusy,!historyGesture,!saveInFlight,!previewInFlight,!scrollRelay.isActive else{return}')
 replace('guard !self.dirty,!self.historyGesture,!self.scrollRelay.isActive,self.project?.id==p.id', 'guard !self.historyGesture,!self.saveInFlight,!self.previewInFlight,!self.scrollRelay.isActive,self.project?.id==p.id')
 replace('var next=self.project!', 'var next=self.editorBase ?? self.project!')
 start=source.index('    let changed = !NSDictionary(dictionary:self.rawScene)')
 end=source.index('\n   }\n  }\n }',start)
 source=source[:start]+'    self.acceptEditorSnapshot(next,raw:current,revision:receivedRevision)'+source[end:]
 replace('self.pendingPreview=nil;self.error(e)', 'self.pendingPreview=nil;self.editorSyncFailure(e)')
 replace('let generation=editGeneration;saveInFlight=true', 'let generation=editGeneration, savingPage=activePage.isEmpty ? (page?.id ?? "") : activePage;_ = journalEditorDraft();saveInFlight=true')
 replace('switch r{case .failure(let e):self.error(e)\n   case .success:', 'switch r{case .failure(let e):self.editorSyncFailure(e)\n   case .success:')
 replace('if self.project?.id==p.id,self.editGeneration==generation,!self.historyGesture{self.dirty=false}', 'self.editorSaveCompleted(p,pageID:savingPage,generation:generation)')
 return source
