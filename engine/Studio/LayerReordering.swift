import UIKit

private struct LayerDragIdentity {let project:String;let page:String;let node:String}
extension StudioController {
 func stampLayerOrder(){guard project != nil else{return};for i in project!.pages[pageIndex].nodes.indices{project!.pages[pageIndex].nodes[i].layerOrder=Double(i)}}
 func beginLayerDrag(at index:IndexPath)->[UIDragItem]{
  guard !running,!historyGesture,let p=project,let page=page,index.row<page.nodes.count else{return []}
  let node=Array(page.nodes.reversed())[index.row];guard !node.locked else{return []}
  let item=UIDragItem(itemProvider:NSItemProvider(object:node.name as NSString));item.localObject=LayerDragIdentity(project:p.id,page:page.id,node:node.id);return [item]
 }
 func tableView(_ tableView:UITableView,dragSessionWillBegin session:UIDragSession){if tableView===layers{historyGesture=true;setStatus("拖到目标位置松开；靠近列表顶部或底部可继续滚动")}}
 func tableView(_ tableView:UITableView,dragSessionDidEnd session:UIDragSession){if tableView===layers{historyGesture=false}}
 func tableView(_ tableView:UITableView,dragSessionAllowsMoveOperation session:UIDragSession)->Bool{tableView===layers}
 func tableView(_ tableView:UITableView,canHandle session:UIDropSession)->Bool{tableView===layers && session.localDragSession != nil && session.items.count==1 && session.items.first?.localObject is LayerDragIdentity}
 func tableView(_ tableView:UITableView,dropSessionDidUpdate session:UIDropSession,withDestinationIndexPath destination:IndexPath?)->UITableViewDropProposal{
  guard !running,let identity=session.items.first?.localObject as? LayerDragIdentity,identity.project==project?.id,identity.page==page?.id else{return UITableViewDropProposal(operation:.forbidden)}
  return UITableViewDropProposal(operation:.move,intent:.insertAtDestinationIndexPath)
 }
 func tableView(_ tableView:UITableView,performDropWith coordinator:UITableViewDropCoordinator){
  guard tableView===layers,!running,let item=coordinator.items.first,let identity=item.dragItem.localObject as? LayerDragIdentity,identity.project==project?.id,identity.page==page?.id,let current=page else{return}
  var rows=Array(current.nodes.reversed());guard let source=rows.firstIndex(where:{$0.id==identity.node}),!rows[source].locked else{return}
  let destination=min(coordinator.destinationIndexPath?.row ?? rows.count-1,rows.count-1)
  guard source != destination else{return}
  let destinationParent=rows[destination].parent
  var ancestor=destinationParent;var seen=Set<String>()
  while let id=ancestor,!id.isEmpty{guard id != identity.node,seen.insert(id).inserted else{setStatus("不能把容器放进自己的子图层");return};ancestor=rows.first(where:{$0.id==id})?.parent}
  // Page coordinates remain unchanged; the server converts them into the new parent's space.

  // Ordering changes only draw order. Parentage and page coordinates stay intact.
  checkpoint();var moved=rows.remove(at:source);moved.parent=destinationParent;rows.insert(moved,at:destination)
  project!.pages[pageIndex].nodes=Array(rows.reversed());stampLayerOrder();historyGesture=false
  tableView.performBatchUpdates({tableView.deleteRows(at:[IndexPath(row:source,section:0)],with:.automatic);tableView.insertRows(at:[IndexPath(row:destination,section:0)],with:.automatic)}){[weak self]_ in self?.changed()}
  coordinator.drop(item.dragItem,toRowAt:IndexPath(row:destination,section:0))
  setStatus("图层顺序已调整，可撤销；正在保存布局")
 }
}
