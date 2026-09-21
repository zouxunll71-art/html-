import UIKit
extension StudioController {
 func claimEditorKeyboard(){guard !running else{return};view.endEditing(true);becomeFirstResponder()}
 var nudgeCommands:[UIKeyCommand]{[UIKeyCommand.inputLeftArrow,UIKeyCommand.inputRightArrow,UIKeyCommand.inputUpArrow,UIKeyCommand.inputDownArrow].flatMap{input in [UIKeyModifierFlags(),.shift].map{flags in let command=UIKeyCommand(input:input,modifierFlags:flags,action:#selector(keyNudge(_:)));command.wantsPriorityOverSystemBehavior=true;return command}}}
 var canNudge:Bool{!running && canToggleModeFromKeyboard && !selectionIDs.isEmpty}
 @objc func keyNudge(_ command:UIKeyCommand){
  guard canNudge,let input=command.input else{return};let step:CGFloat=command.modifierFlags.contains(.shift) ? 10:1
  let dx:CGFloat=input==UIKeyCommand.inputLeftArrow ? -step : input==UIKeyCommand.inputRightArrow ? step:0
  let dy:CGFloat=input==UIKeyCommand.inputUpArrow ? -step : input==UIKeyCommand.inputDownArrow ? step:0
  let ids=selectionIDs;checkpoint()
  for index in project!.pages[pageIndex].nodes.indices where ids.contains(project!.pages[pageIndex].nodes[index].id){project!.pages[pageIndex].nodes[index].x+=dx;project!.pages[pageIndex].nodes[index].y+=dy}
  changed();setStatus("已微调 \(Int(step)) pt · Shift + 方向键移动 10 pt · 可撤销")
 }
 func snappedDelta(_ delta:CGPoint,ids:Set<String>)->CGPoint {
  guard snappingEnabled,let page=page else{return delta}
  let selectedNodes=page.nodes.filter{ids.contains($0.id)}
  let rect=selectedNodes.reduce(CGRect.null){$0.union($1.visualBounds)}
  guard !rect.isNull else{return delta}
  let map=Dictionary(page.nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
  func related(_ n:StudioNode)->Bool{
   var parent=n.parent;var seen=Set<String>()
   while let id=parent,seen.insert(id).inserted{if ids.contains(id){return true};parent=map[id]?.parent}
   for node in selectedNodes{parent=node.parent;seen=[];while let id=parent,seen.insert(id).inserted{if id==n.id{return true};parent=map[id]?.parent}}
   return false
  }
  let canvas=CGRect(x:0,y:0,width:page.width,height:page.height)
  let targets=[canvas]+page.nodes.filter{!ids.contains($0.id) && !$0.hidden && $0.opacity>0 && $0.visualBounds.intersects(canvas) && !related($0)}.map{$0.visualBounds}
  let proposed=rect.offsetBy(dx:delta.x-snapCorrection.x,dy:delta.y-snapCorrection.y)
  let result=AlignmentGeometry.snap(proposed,to:targets,threshold:5)
  let adjusted=CGPoint(x:delta.x+result.correction.x-snapCorrection.x,y:delta.y+result.correction.y-snapCorrection.y)
  snapCorrection=result.correction;left.guideX=result.x;left.guideY=result.y
  return adjusted
 }
 func toggleSnapping(){snappingEnabled.toggle();UserDefaults.standard.set(!snappingEnabled,forKey:"disableAlignmentSnapping");refreshSnapMenu();setStatus(snappingEnabled ? "拖动吸附已开启 · 靠近边缘或中心时显示参考线":"拖动吸附已关闭")}
 func refreshSnapMenu(){
  let action=UIAction(title:"拖动吸附到边缘 / 中心",image:UIImage(systemName:"align.horizontal.center"),state:snappingEnabled ? .on:.off){[weak self]_ in self?.toggleSnapping()}
  let rest=moreTools.menu?.children.filter{($0 as? UIAction)?.identifier.rawValue != "editor.snapping"} ?? []
  let toggle=UIAction(title:action.title,image:action.image,identifier:UIAction.Identifier("editor.snapping"),state:action.state){[weak self]_ in self?.toggleSnapping()}
  moreTools.menu=UIMenu(children:[toggle]+rest)
 }
}
