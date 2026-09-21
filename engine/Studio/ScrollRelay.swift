import UIKit

/// Keep one request in flight and replace unsent offsets with the newest one.
/// The phone still displays frames rendered by the real iOS simulator.
final class ScrollRelay:NSObject {
 var generation=0
 var node="",page="",project="",origin=CGPoint.zero,offset=CGPoint.zero,limit=CGPoint.zero,velocity=CGPoint.zero
 var timer:CADisplayLink?,lastTime:CFTimeInterval=0,pending=false,inFlight=false
 var onError:((Error)->Void)?
 var onOffset:((String,CGPoint)->Void)?
 private var dragging=false
 var isActive:Bool{dragging || timer != nil || pending || inFlight}
 func begin(node:String,page:String,project:String,offset:CGPoint,limit:CGPoint){cancel();dragging=true;self.node=node;self.page=page;self.project=project;self.origin=offset;self.offset=offset;self.limit=limit}
 func drag(_ translation:CGPoint){setOffset(CGPoint(x:origin.x-translation.x,y:origin.y-translation.y))}
 func finish(_ speed:CGPoint){dragging=false;velocity=CGPoint(x:max(-5000,min(5000,-speed.x)),y:max(-5000,min(5000,-speed.y)));guard !UIAccessibility.isReduceMotionEnabled,hypot(velocity.x,velocity.y)>60 else{flush();return};lastTime=0;timer=CADisplayLink(target:self,selector:#selector(tick(_:)));timer?.preferredFramesPerSecond=60;timer?.add(to:.main,forMode:.common)}
 func stopMomentum(){dragging=false;timer?.invalidate();timer=nil;velocity = .zero;flush()}
 func cancel(){generation+=1;dragging=false;timer?.invalidate();timer=nil;velocity = .zero;pending=false;node=""}
 private func setOffset(_ next:CGPoint){let value=CGPoint(x:min(limit.x,max(0,next.x)),y:min(limit.y,max(0,next.y)));guard abs(value.x-offset.x)>0.25 || abs(value.y-offset.y)>0.25 else{return};offset=value;onOffset?(node,value);pending=true;flush()}
 @objc private func tick(_ display:CADisplayLink){let dt=lastTime==0 ? 1.0/60 : min(0.05,display.timestamp-lastTime);lastTime=display.timestamp;let before=offset;setOffset(CGPoint(x:offset.x+velocity.x*dt,y:offset.y+velocity.y*dt));velocity.x *= exp(-4.5*dt);velocity.y *= exp(-4.5*dt);if offset.x==before.x{velocity.x=0};if offset.y==before.y{velocity.y=0};if hypot(velocity.x,velocity.y)<15{timer?.invalidate();timer=nil;flush()}}
 private func flush(){guard pending,!inFlight,!node.isEmpty else{return};pending=false;inFlight=true
  let requestGeneration=generation,requestProject=project,requestPage=page,event:[String:Any]=["type":"scroll","node":node,"x":offset.x,"y":offset.y]
  Bridge.shared.json("/event",["side":"ios","projectID":project,"pageID":page,"event":event,"eventID":UUID().uuidString]){[weak self]result in guard let self=self else{return};self.inFlight=false;if self.generation==requestGeneration,self.project==requestProject,self.page==requestPage,case .failure(let error)=result{self.cancel();self.onError?(error)};self.flush()}
 }
}
extension StudioController {
 // Keep flattened selection geometry on the same scroll snapshot as the scene.
 func updateEditorScroll(_ id:String,_ offset:CGPoint){
  guard var current=page,let index=current.nodes.firstIndex(where:{$0.id==id}) else{return}
  let old=CGPoint(x:current.nodes[index].scrollX ?? 0,y:current.nodes[index].scrollY ?? 0)
  let delta=CGPoint(x:offset.x-old.x,y:offset.y-old.y)
  current.nodes[index].scrollX=offset.x;current.nodes[index].scrollY=offset.y
  let map=Dictionary(current.nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
  for i in current.nodes.indices where i != index {
   var parent=current.nodes[i].parent;var visited=Set<String>()
   while let pid=parent,visited.insert(pid).inserted{
    if pid==id{current.nodes[i].x-=delta.x;current.nodes[i].y-=delta.y;break}
    parent=map[pid]?.parent
   }
  }
  project?.pages[pageIndex]=current;left.nodes=current.nodes;left.setNeedsLayout()
  if var raw=rawScene["nodes"] as? [[String:Any]],let i=raw.firstIndex(where:{$0["id"] as? String==id}){raw[i]["scrollX"]=offset.x;raw[i]["scrollY"]=offset.y;rawScene["nodes"]=raw}
 }
 func relayScroll(_ phase:String,_ point:CGPoint,_ translation:CGPoint,_ velocity:CGPoint){
  guard !historyGesture else{return}
  scrollRelay.onOffset={[weak self]node,offset in self?.updateEditorScroll(node,offset)}
  if phase=="begin"{guard let p=project,let page=page,let n=left.nodes.reversed().first(where:{$0.type=="scroll" && $0.frame.contains(point)}),let raw=(rawScene["nodes"] as? [[String:Any]])?.first(where:{$0["id"] as? String==n.id}) else{scrollRelay.cancel();return};scrollRelay.onError={[weak self]in self?.error($0)};scrollRelay.begin(node:n.id,page:page.id,project:p.id,offset:CGPoint(x:raw["scrollX"] as? Double ?? 0,y:raw["scrollY"] as? Double ?? 0),limit:CGPoint(x:max(0,(raw["contentWidth"] as? Double ?? 0)-n.width),y:max(0,(raw["contentHeight"] as? Double ?? 0)-n.height)))}
  scrollRelay.drag(translation)
  if phase=="end"{scrollRelay.finish(velocity)}else if phase=="cancel"{scrollRelay.cancel()}
 }
}
