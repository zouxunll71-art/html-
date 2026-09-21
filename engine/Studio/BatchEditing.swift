import UIKit
extension StudioController {
 var batchNodes:[StudioNode]{(page?.nodes ?? []).filter{selectionIDs.contains($0.id)}}
 var batchBounds:CGRect{batchNodes.reduce(CGRect.null){$0.union($1.visualBounds)}}
 func renderBatchInspector(){
  func add(_ v:UIView){propertyStack.addArrangedSubview(v)}
  let nodes=batchNodes
  if nodes.contains(where:{$0.sharedKey != nil}){add(label("导航栏图层的调整同步全部一级页面",11))}
  func common(_ key:KeyPath<StudioNode,CGFloat>)->String{guard let first=nodes.first else{return ""};return nodes.allSatisfy{abs($0[keyPath:key]-first[keyPath:key])<0.01} ? format(first[keyPath:key]) : ""}
  add(label("已多选 \(nodes.count) 个图层",15,.semibold))
  let note=label("点击已选元素可取消选择。\n拖动元素一起移动；拖右下角等比缩放。",12);note.numberOfLines=0;add(note)
  addField("统一宽度 · 每个图层","batch.width",common(\.width));addField("统一高度 · 每个图层","batch.height",common(\.height))
  fields["batch.width"]?.placeholder="多个值，输入后统一";fields["batch.height"]?.placeholder="多个值，输入后统一"
  add(menuButton("统一图标尺寸",["20 × 20","24 × 24","28 × 28","32 × 32"]){[weak self] value in guard let size=Double(value.components(separatedBy:" ")[0])else{return};self?.editBatch{n in let cx=n.x+n.width/2,cy=n.y+n.height/2;n.width=CGFloat(size);n.height=CGFloat(size);n.x=cx-n.width/2;n.y=cy-n.height/2}})
  let sizeNote=label("调整尺寸时保留各自中心位置",11);sizeNote.textColor = .secondaryLabel;add(sizeNote)
  addField("整体位置 X","batch.x",format(batchBounds.minX));addField("整体位置 Y","batch.y",format(batchBounds.minY))
  addField("整体水平移动 ΔX","batch.dx","0");addField("整体垂直移动 ΔY","batch.dy","0")
  addField("统一旋转角度 °","batch.rotation",common(\.rotation))
  add(menuButton("对齐所选元素",["左对齐","水平居中","右对齐","顶部对齐","垂直居中","底部对齐"]){[weak self]in self?.alignBatch($0)})
  add(button("水平等间距",{[weak self]in self?.distributeBatch(horizontal:true)}));add(button("垂直等间距",{[weak self]in self?.distributeBatch(horizontal:false)}))
  add(button("组合并移动",{[weak self]in self?.groupSelection()}));add(button("取消组合",{[weak self]in self?.ungroupSelection()}));add(button("清除选择",{[weak self]in self?.selected=nil;self?.refreshSelection()}))
 }
 func editBatch(_ edit:(inout StudioNode)->Void){
  let ids=selectionIDs;guard !ids.isEmpty,page != nil else{return};checkpoint()
  for i in project!.pages[pageIndex].nodes.indices where ids.contains(project!.pages[pageIndex].nodes[i].id){edit(&project!.pages[pageIndex].nodes[i])}
  changed()
 }
 func commitBatch(_ key:String,_ text:String){
  guard let raw=Double(text),raw.isFinite else{setStatus("请输入有效数字");return};let value=CGFloat(raw)
  if (key=="batch.width" || key=="batch.height") && value<=0{setStatus("宽高必须大于零");return}
  let bounds=batchBounds
  editBatch{n in switch key {
   case "batch.width":n.x+=(n.width-value)/2;n.width=value
   case "batch.height":n.y+=(n.height-value)/2;n.height=value
   case "batch.x":n.x+=value-bounds.minX
   case "batch.y":n.y+=value-bounds.minY
   case "batch.dx":n.x+=value
   case "batch.dy":n.y+=value
   case "batch.rotation":n.rotation=value
   default:break
  }}
 }
 func alignBatch(_ alignment:String){
  let box=batchBounds
  editBatch{n in let r=n.visualBounds;switch alignment {
   case "左对齐":n.x+=box.minX-r.minX
   case "水平居中":n.x+=box.midX-r.midX
   case "右对齐":n.x+=box.maxX-r.maxX
   case "顶部对齐":n.y+=box.minY-r.minY
   case "垂直居中":n.y+=box.midY-r.midY
   case "底部对齐":n.y+=box.maxY-r.maxY
   default:break
  }}
 }
 func distributeBatch(horizontal:Bool){
  let nodes=batchNodes.sorted{horizontal ? $0.visualBounds.minX<$1.visualBounds.minX : $0.visualBounds.minY<$1.visualBounds.minY}
  guard nodes.count>=3 else{setStatus("等间距排列至少需要选择 3 个图层");return}
  let rect=batchBounds
  let sizes=nodes.map{horizontal ? $0.visualBounds.width : $0.visualBounds.height}
  let gap=((horizontal ? rect.width : rect.height)-sizes.reduce(0,+))/CGFloat(nodes.count-1)
  var cursor=horizontal ? rect.minX : rect.minY;var offsets:[String:CGFloat]=[:]
  for (i,n) in nodes.enumerated(){offsets[n.id]=cursor-(horizontal ? n.visualBounds.minX : n.visualBounds.minY);cursor+=sizes[i]+gap}
  editBatch{n in if horizontal{n.x+=offsets[n.id] ?? 0}else{n.y+=offsets[n.id] ?? 0}}
 }
}

extension StudioController {
 func scaleSelection(_ delta:CGPoint){
  let nodes=batchNodes,box=batchBounds;guard !nodes.isEmpty,box.width>0,box.height>0 else{return}
  let minimum=nodes.map{4/min($0.width,$0.height)}.max() ?? 0.01
  let factor=max(minimum,1+(delta.x*box.width+delta.y*box.height)/(box.width*box.width+box.height*box.height))
  let ids=selectionIDs
  for i in project!.pages[pageIndex].nodes.indices where ids.contains(project!.pages[pageIndex].nodes[i].id){
   var n=project!.pages[pageIndex].nodes[i]
   n.x=box.minX+(n.x-box.minX)*factor;n.y=box.minY+(n.y-box.minY)*factor
   n.width*=factor;n.height*=factor;n.fontSize*=factor;n.cornerRadius*=factor;n.strokeWidth*=factor;n.capPoints*=factor
   project!.pages[pageIndex].nodes[i]=n
  }
 }
}
