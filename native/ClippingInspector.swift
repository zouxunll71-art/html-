import UIKit
extension StudioController {
 func clippingOwner(_ node:StudioNode)->StudioNode? {
  let map=Dictionary((page?.nodes ?? []).map{($0.id,$0)},uniquingKeysWith:{_,last in last})
  var parent=node.parent,seen=Set<String>()
  while let id=parent,seen.insert(id).inserted,let item=map[id]{if item.clipsContent{return item};parent=item.parent}
  return nil
 }
 func addClippingInspector(_ node:StudioNode) {
  guard !running,let owner=clippingOwner(node) else{return}
  let notice=label("受父容器裁切：\(sourceBrowser.displayName(owner))\n橙色虚线表示裁切边界，透明区域也会裁切。",12)
  notice.numberOfLines=0;notice.textColor = .systemOrange;propertyStack.addArrangedSubview(notice)
  propertyStack.addArrangedSubview(button("选中裁切容器 · 整体移动",{[weak self] in self?.chooseLayer(owner.id)}))
  if page?.nodes.contains(where:{$0.parent==node.id}) != true {
   propertyStack.addArrangedSubview(button("将此图层移出这一层裁切容器",{[weak self] in self?.releaseClippedLayer(node.id,ownerID:owner.id)}))
  }
 }
 func releaseClippedLayer(_ id:String,ownerID:String) {
  guard !running,!historyGesture,let p=page,let index=p.nodes.firstIndex(where:{$0.id==id}),!p.nodes[index].locked,let owner=p.nodes.first(where:{$0.id==ownerID}),!p.nodes.contains(where:{$0.parent==id}) else{return}
  let node=p.nodes[index],map=Dictionary(p.nodes.map{($0.id,$0)},uniquingKeysWith:{_,last in last})
  let target=owner.parent.flatMap{map[$0]}
  let old=node.selectionTransform(in:map,includeSelf:false),next=target?.selectionTransform(in:map) ?? .identity
  guard let pose=ClippingGeometry.release(frame:node.frame,rotation:node.rotation,scale:node.scale ?? 1,old:old,target:next) else{setStatus("父容器缩放为零，无法安全移出");return}
  checkpoint()
  project!.pages[pageIndex].nodes[index].parent=owner.parent
  project!.pages[pageIndex].nodes[index].x=pose.center.x-node.width/2
  project!.pages[pageIndex].nodes[index].y=pose.center.y-node.height/2
  project!.pages[pageIndex].nodes[index].rotation=pose.rotation
  project!.pages[pageIndex].nodes[index].scale=pose.scale
  changed();setStatus("已移出这一层裁切容器并保留位置，可撤销；外层裁切仍有效")
 }
}
