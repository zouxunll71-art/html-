import UIKit
extension StudioController {
 func setupIOSBrowser(){
  iosBrowser.editingExisting=true;view.addSubview(iosBrowser)
  iosBrowser.onLayerAction={[weak self] id,action in self?.editTreeLayer(id,action)}
  iosBrowser.thumbnail={[weak self] n in self?.layerThumbnail(n)}
  iosBrowser.onSelect={[weak self] id in
   guard let self=self else{return};self.claimEditorKeyboard();self.selected=id;self.multiSelection=[];self.isolatedSelection=id;self.highlightSource(nil);self.refreshSelection()
  }
  iosBrowser.onCopy={[weak self] id,_ in
   guard let self=self else{return};self.claimEditorKeyboard();self.selected=id;self.multiSelection=[];self.isolatedSelection=id;self.inspectorTabs.selectedSegmentIndex=0;self.showInspectorMode();self.refreshSelection()
  }
 }
 func editTreeLayer(_ id:String,_ action:String){
  guard !running,let n=page?.nodes.first(where:{$0.id==id}) else{return}
  selected=id;multiSelection=[];isolatedSelection=id
  if action=="rename"{
   let alert=UIAlertController(title:"重命名图层",message:nil,preferredStyle:.alert);alert.addTextField{$0.text=n.name}
   alert.addAction(UIAlertAction(title:"取消",style:.cancel));alert.addAction(UIAlertAction(title:"保存",style:.default){[weak self,weak alert]_ in guard let value=alert?.textFields?.first?.text?.trimmingCharacters(in:.whitespacesAndNewlines),!value.isEmpty else{return};self?.mutate{$0.name=value}});present(alert,animated:true)
  }else{mutate{if action=="hidden"{$0.hidden.toggle()}else if action=="locked"{$0.locked.toggle()}}}
 }
 func refreshIOSBrowser(focus:String?=nil){
  guard !running,inspectorTabs.selectedSegmentIndex==2,let p=project,let page=page else{return}
  iosBrowser.update(page.nodes,projectID:p.id+":"+page.id,signature:"",focus:focus)
 }
 func openIOSLayers(){
  guard !running else{return};inspectorTabs.selectedSegmentIndex=2;showInspectorMode();refreshIOSBrowser(focus:selected)
  setStatus("展开查看父子图层；右键可重命名、隐藏或锁定；选中后编辑属性")
 }
}
