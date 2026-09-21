import UIKit
extension StudioPage {
 mutating func supplement(from snapshot:AndroidSnapshot) {
  func key(_ n:StudioNode)->String { n.type+"|"+n.name+"|"+(n.type=="text" ? n.text : "") }
  var available:[String:[Int]]=[:]
  for i in nodes.indices{available[key(nodes[i]),default:[]].append(i)}
  var mapped:[String]=[];var missing:Set<String>=[]
  for source in snapshot.nodes {
   let k=key(source)
   func distance(_ i:Int)->CGFloat{abs(nodes[i].x-source.x)+abs(nodes[i].y-source.y)+abs(nodes[i].width-source.width)+abs(nodes[i].height-source.height)}
   if let index=available[k]?.min(by:{distance($0)<distance($1)}) {
    available[k]?.removeAll{$0==index};mapped.append(nodes[index].id)
    // Upgrade fields absent from older extraction without changing edited geometry or text.
    if nodes[index].fontFamily==nil{nodes[index].fontFamily=source.fontFamily}
    if nodes[index].italic==nil{nodes[index].italic=source.italic}
    if nodes[index].lineHeight==nil{nodes[index].lineHeight=source.lineHeight}
    if nodes[index].letterSpacing==nil{nodes[index].letterSpacing=source.letterSpacing}
    if nodes[index].textSpans==nil{nodes[index].textSpans=source.textSpans}
   } else {
    var node=source;node.id=UUID().uuidString;mapped.append(node.id);missing.insert(node.id);nodes.append(node)
   }
  }
  // Put new backgrounds before the existing foregrounds, preserving old nodes' relative order.
  for i in mapped.indices.reversed() where missing.contains(mapped[i]) {
   guard let index=nodes.firstIndex(where:{$0.id==mapped[i]}) else{continue}
   let node=nodes.remove(at:index)
   let next=mapped.dropFirst(i+1).first
   if let next=next,let anchor=nodes.firstIndex(where:{$0.id==next}){nodes.insert(node,at:anchor)}else{nodes.append(node)}
  }
  templateRoutes=snapshot.templateRoutes
  if paintOrderVersion != 1 && snapshot.paintOrderVersion==1 && Set(mapped).count==nodes.count {
   let byID=Dictionary(nodes.map{($0.id,$0)},uniquingKeysWith:{_,latest in latest})
   nodes=mapped.compactMap{byID[$0]};paintOrderVersion=1
  }
 }
}
