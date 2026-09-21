import UIKit
extension StudioController {
 var selectionIDs:Set<String>{
  guard let page=page else{return []}
  let available=page.nodes.filter{!$0.hidden && !$0.locked}
  if let id=isolatedSelection,id==selected,available.contains(where:{$0.id==id}){return [id]}
  if !multiSelection.isEmpty{return Set(available.filter{multiSelection.contains($0.id)}.map(\.id))}
  guard let n=available.first(where:{$0.id==selected})else{return []}
  return n.groupID.isEmpty ? [n.id] : Set(available.filter{$0.groupID==n.groupID}.map(\.id))
 }
 func refreshSelection(){left.selected=selected;left.selectedIDs=selectionIDs;layers.reloadData();renderInspector()}
 func chooseLayer(_ id:String?){
  claimEditorKeyboard()
  let browsing=inspectorTabs.selectedSegmentIndex==2
  if id != selected{isolatedSelection=nil}
  if !browsing{inspectorTabs.selectedSegmentIndex=0};showInspectorMode();highlightSource(nil);right.selected=nil
  if (left.tool=="multi" || left.tool=="clickMulti"),let id=id {
   var ids=selectionIDs
   if ids.contains(id){ids.remove(id)}else{ids.insert(id)}
   selected=ids.sorted().first;multiSelection=ids
  }else{multiSelection=[];selected=id}
  refreshSelection();if browsing{refreshIOSBrowser(focus:id)}
 }
 func selectRegion(_ rect:CGRect){
  guard let page=page else{return};var ids=Set(page.nodes.filter{$0.hasVisibleSelectionContent && rect.insetBy(dx:-1,dy:-1).contains($0.selectionBounds) && !left.clippingRect(for:$0,map:Dictionary(page.nodes.map{($0.id,$0)},uniquingKeysWith:{_,last in last})).intersection($0.selectionBounds).isEmpty}.map(\.id))
  let groups=Set(page.nodes.filter{ids.contains($0.id) && !$0.groupID.isEmpty}.map(\.groupID))
  ids.formUnion(page.nodes.filter{groups.contains($0.groupID) && !$0.hidden && !$0.locked}.map(\.id))
  selected=ids.sorted().first;multiSelection=ids;setTool("select");refreshSelection();setStatus("已选中 \(ids.count) 个图层，点击「组合」后可整体移动")
 }
 func groupSelection(){
  let ids=selectionIDs;guard ids.count>1 else{setStatus("先点击「多选」选择多个图层，或选中背景后使用「选中区域内全部图层」");return}
  checkpoint();let group=UUID().uuidString
  // Keep previous groups intact when combining selections.
  let oldGroups=Set(page!.nodes.filter{ids.contains($0.id) && !$0.groupID.isEmpty}.map(\.groupID))
  let allIDs=Set(page!.nodes.filter{ids.contains($0.id) || oldGroups.contains($0.groupID)}.map(\.id))
  for i in project!.pages[pageIndex].nodes.indices where allIDs.contains(project!.pages[pageIndex].nodes[i].id){project!.pages[pageIndex].nodes[i].groupID=group}
  multiSelection=[];setTool("move");changed();setStatus("已组合 \(allIDs.count) 个图层，拖动任意成员即可整体移动")
 }
 func ungroupSelection(){
  let ids=selectionIDs;guard let page=page else{return};let groups=Set(page.nodes.filter{ids.contains($0.id) && !$0.groupID.isEmpty}.map(\.groupID));guard !groups.isEmpty else{setStatus("当前没有已保存的组合");return}
  checkpoint();for i in project!.pages[pageIndex].nodes.indices where groups.contains(project!.pages[pageIndex].nodes[i].groupID){project!.pages[pageIndex].nodes[i].groupID=""}
  multiSelection=[];setTool("select");changed();setStatus("已取消组合，可以单独编辑各图层")
 }
}
