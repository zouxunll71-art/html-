import UIKit
import SceneKit

/// Native model component. The canvas uses a shared linear RGB UV atlas;
/// workbench layer transforms are independent of the model's camera gestures.
final class NativeModelView: UIView {
 typealias Store = (String,[String:Any]?,@escaping(Result<[String:Any]?,Error>)->Void)->Void
 var loadAsset:((String,@escaping(Result<Data,Error>)->Void)->Void)?
 var store:Store?;var onSave:((String)->Void)?;var onAnalysis:(([String:Any])->Void)?
 let renderer=SCNView();let message=UILabel();let world=SCNScene();let camera=SCNNode()
 var object:SCNNode?;var gpu:NativePaintGPU?;var options:[String:Any]=[:];var identity="";var key="";var project="";var asset="";var sequence:Int?;var ready=false;var busy=false;var generation=0
 var undo=[Data](),redo=[Data]();var previous:CGPoint?;var dirty=false;var saveQueue=[(String,[String:Any],((Bool)->Void)?)]();var writing=false
 var syncTimer:Timer?;var remoteRevision=""
 deinit{syncTimer?.invalidate()}
 var mode:Int {options["mode"] as? Int ?? 0}
 override init(frame:CGRect){super.init(frame:frame);setup()}
 required init?(coder:NSCoder){super.init(coder:coder);setup()}
 func setup(){
  renderer.backgroundColor = .clear;renderer.isOpaque=false;renderer.scene=world;renderer.antialiasingMode = .multisampling4X;renderer.autoenablesDefaultLighting=false;renderer.rendersContinuously=false;renderer.isPlaying=false;addSubview(renderer)
  camera.camera=SCNCamera();camera.camera?.fieldOfView=35;camera.camera?.zNear=0.01;camera.camera?.zFar=50;camera.position=SCNVector3(0,1.1,3.7);camera.look(at:SCNVector3Zero);world.rootNode.addChildNode(camera);renderer.pointOfView=camera
  let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=750;ambient.light?.color=UIColor.white;world.rootNode.addChildNode(ambient)
  let light=SCNNode();light.light=SCNLight();light.light?.type = .directional;light.light?.intensity=1300;light.position=SCNVector3(2,3,4);light.look(at:SCNVector3Zero);world.rootNode.addChildNode(light)
  message.font = .systemFont(ofSize:12);message.numberOfLines=0;message.textAlignment = .center;message.textColor=UIColor(studioHex:"#082DB5");message.isUserInteractionEnabled=false;addSubview(message)
  renderer.addGestureRecognizer(UIPanGestureRecognizer(target:self,action:#selector(pan(_:))));renderer.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tap(_:))));renderer.addGestureRecognizer(UIPinchGestureRecognizer(target:self,action:#selector(pinch(_:))))
  syncTimer=Timer.scheduledTimer(withTimeInterval:2,repeats:true){[weak self] _ in self?.syncPainting()}
  do{gpu=try NativePaintGPU()}catch{status("GPU unavailable: \(error.localizedDescription)")}

 }
 override func layoutSubviews(){super.layoutSubviews();renderer.frame=bounds;message.frame=CGRect(x:4,y:max(0,bounds.height-48),width:max(0,bounds.width-8),height:44)}
 override func didMoveToWindow(){super.didMoveToWindow();renderer.isPlaying=false;if window==nil,dirty{persist()}}
 func status(_ text:String){message.text=text;accessibilityValue=text}
 func update(_ node:[String:Any],project:String,editing:Bool){
  options=node["paintOptions"] as? [String:Any] ?? [:];renderer.isUserInteractionEnabled = !editing
  let model=node["modelAsset"] as? String ?? "",work=options["work"] as? String ?? "",newID=project+":"+model+":"+work
  let command=options["command"] as? [String:Any] ?? [:],seq=command["seq"] as? Int ?? 0
  if newID != identity {
   if dirty{persist()};identity=newID;self.project=project;asset=model;key=project+":"+(work.isEmpty ? "draft:"+model : work);generation+=1;let ticket=generation;sequence=seq;ready=false;dirty=false;undo=[];redo=[];object?.removeFromParentNode();object=nil;clear();status("Loading model…")
   loadAsset?(model){[weak self] result in guard let self=self,self.generation==ticket else{return}
    do {let data=try result.get();let decoded=try NativeGLB(data).scene();self.object=decoded;self.world.rootNode.addChildNode(decoded);guard let gpu=self.gpu else{throw NativeGLBError.invalid("GPU unavailable")};try gpu.attach(decoded);self.store?(self.key,nil){[weak self] result in guard let self=self,self.generation==ticket else{return};do{if let record=try result.get(),let png=record["png"] as? String {guard record["model"] as? String==self.asset,let data=Data(base64Encoded:png),let image=UIImage(data:data)?.cgImage,image.width==1024,image.height==1024 else{throw NativeGLBError.invalid("Invalid saved painting")};self.readPNG(image)};self.ready=true;self.refresh();self.status("")}catch{self.status("Model unavailable: \(error.localizedDescription)")}}}
    catch{self.status("Model unavailable: \(error.localizedDescription)")}
   }
  }else if sequence != seq,ready,!editing {sequence=seq;if node["paintCommandOwner"] as? String != "web"{run(command["type"] as? String ?? "")}}
 }
 func syncPainting(){guard ready,!busy,!dirty,!writing,saveQueue.isEmpty,previous==nil,window != nil else{return};let ticket=generation;store?(key,nil){[weak self] result in guard let self=self,self.generation==ticket,!self.dirty,!self.writing,self.previous==nil,case .success(let record)=result,let record=record,let revision=record["revision"] as? String,revision != self.remoteRevision,let png=record["png"] as? String,let data=Data(base64Encoded:png),let image=UIImage(data:data)?.cgImage,record["model"] as? String==self.asset else{return};self.remoteRevision=revision;self.readPNG(image);self.refresh()}}
 func clear(){gpu?.clear()}
 func snapshot()->Data{gpu?.snapshot() ?? Data()}
 func restore(_ data:Data){gpu?.restore(data);dirty=true;refresh()}
 func checkpoint(){undo.append(snapshot());if undo.count>12{undo.removeFirst()};redo=[]}
 func refresh(){gpu?.bind();renderer.setNeedsDisplay()}
 func readPNG(_ image:CGImage){
  // PNG bytes carry linear samples tagged as sRGB for compatibility with WebGL readback.
  let raw=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  raw.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024));gpu?.restore(Data(bytes:raw.data!,count:4096*1024))
 }
 func record()->[String:Any]? {let bytes=snapshot();guard bytes.count==4096*1024,let provider=CGDataProvider(data:bytes as CFData),let image=CGImage(width:1024,height:1024,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:4096,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent),let png=UIImage(cgImage:image).pngData() else{return nil};return ["png":png.base64EncodedString(),"model":asset,"version":1]}

 func persist(){guard ready,dirty,let value=record() else{return};enqueue(key,value,nil);dirty=false}
 func enqueue(_ key:String,_ value:[String:Any],_ completion:((Bool)->Void)?){saveQueue.append((key,value,completion));pump()}
 func pump(){guard !writing,!saveQueue.isEmpty,let store=store else{return};writing=true;let entry=saveQueue.removeFirst();store(entry.0,entry.1){[weak self] result in guard let self=self else{return};self.writing=false;switch result{case .success:entry.2?(true);case .failure(let error):self.dirty=true;self.status("Save failed: \(error.localizedDescription)");entry.2?(false)};self.pump()}}
 func run(_ command:String){guard !busy else{return};switch command {
  case "analyze":if let result=analyzePainting(){onAnalysis?(result)}else{status("Model analysis unavailable")}
  case "undo":if let last=undo.popLast(){redo.append(snapshot());restore(last);persist()}
  case "redo":if let last=redo.popLast(){undo.append(snapshot());restore(last);persist()}
  case "clear":checkpoint();clear();dirty=true;refresh();persist()
  case "save":guard let value=record() else{status("Save failed");return};busy=true;status("Saving…");let id=UUID().uuidString.lowercased(),ticket=generation;enqueue(project+":"+id,value){[weak self] ok in guard let self=self,self.generation==ticket else{return};self.busy=false;if ok{self.persist();self.status("");self.onSave?(id)}}
  default:break
 }}
 func analyzePainting()->[String:Any]? {
  guard ready,let gpu=gpu,let root=object else{return nil};let bytes=[UInt8](snapshot());guard bytes.count==1024*1024*4 else{return nil}
  var total=Array(repeating:Double(0),count:12),painted=total,saturated=total
  let box=root.boundingBox,center=SIMD3<Float>((box.min.x+box.max.x)/2,0,(box.min.z+box.max.z)/2)
  for mesh in gpu.meshes {
   let v=mesh.vertices.contents().bindMemory(to:NativePaintGPU.Vertex.self,capacity:mesh.vertices.length/MemoryLayout<NativePaintGPU.Vertex>.stride)
   let indices=mesh.indices.contents().bindMemory(to:UInt32.self,capacity:mesh.count)
   for i in stride(from:0,to:mesh.count-2,by:3){
    let a=v[Int(indices[i])],b=v[Int(indices[i+1])],c=v[Int(indices[i+2])]
    func point(_ p:SIMD4<Float>)->SIMD3<Float>{mesh.node.simdConvertPosition(SIMD3(p.x,p.y,p.z),to:root)}
    let p=point(a.position),q=point(b.position),r=point(c.position),area=Double(simd_length(simd_cross(q-p,r-p)))/2
    guard area.isFinite,area>0 else{continue};let middle=(p+q+r)/3-center
    let angle=atan2(Double(middle.z),Double(middle.x))+Double.pi
    let region=min(11,max(0,Int(angle/(2*Double.pi)*12)))
    // Four barycentric UV samples per triangle. Unused atlas pixels never contribute.
    let samples:[SIMD3<Float>]=[SIMD3(1/3,1/3,1/3),SIMD3(0.6,0.2,0.2),SIMD3(0.2,0.6,0.2),SIMD3(0.2,0.2,0.6)]
    for weights in samples {
     let uv=a.uv*weights.x+b.uv*weights.y+c.uv*weights.z
     let x=min(1023,max(0,Int(uv.x*1024))),y=min(1023,max(0,Int(uv.y*1024))),offset=(y*1024+x)*4
     let low=Double(min(bytes[offset],bytes[offset+1],bytes[offset+2])),high=Double(max(bytes[offset],bytes[offset+1],bytes[offset+2])),weight=area/4
     total[region]+=weight;if low<245{painted[region]+=weight;saturated[region]+=weight*(high>0 ? (high-low)/high : 0)}
    }
   }
  }
  guard total.reduce(0,+)>0 else{return nil}
  let regions=(0..<12).map{i->[String:Any] in ["coverage":total[i]>0 ? min(1,painted[i]/total[i]):0,"saturation":painted[i]>0 ? min(1,saturated[i]/painted[i]):0]}
  return ["version":1,"regions":regions,"model":asset,"work":options["work"] as? String ?? "","seq":sequence ?? 0]
 }

 @objc func pinch(_ gesture:UIPinchGestureRecognizer){guard ready,!busy else{return};let p=camera.position;let length=sqrt(p.x*p.x+p.y*p.y+p.z*p.z);let next=max(1.7,min(8,length/Float(gesture.scale)));camera.position=SCNVector3(p.x*next/length,p.y*next/length,p.z*next/length);gesture.scale=1;renderer.setNeedsDisplay()}
 @objc func tap(_ gesture:UITapGestureRecognizer){guard ready,!busy,mode != 1 else{return};checkpoint();stamp(gesture.location(in:renderer));refresh();persist()}
 @objc func pan(_ gesture:UIPanGestureRecognizer){guard ready,!busy else{return};let point=gesture.location(in:renderer)
  if mode==1 || gesture.numberOfTouches>1 {let movement=gesture.translation(in:renderer);object?.eulerAngles.y+=Float(movement.x/max(1,bounds.width))*4;if let object=object{object.eulerAngles.x=max(-1.3,min(1.3,object.eulerAngles.x+Float(movement.y/max(1,bounds.height))*3))};gesture.setTranslation(.zero,in:renderer);renderer.setNeedsDisplay();return}
  if gesture.state == .began {checkpoint();previous=point}
  if gesture.state == .began || gesture.state == .changed {let last=previous ?? point,dx=point.x-last.x,dy=point.y-last.y,steps=min(8,max(1,Int(ceil(hypot(dx,dy)/max(2,(options["size"] as? CGFloat ?? 14)*0.35)))));for i in 1...steps{let t=CGFloat(i)/CGFloat(steps);stamp(CGPoint(x:last.x+dx*t,y:last.y+dy*t))};previous=point;refresh()}
  if gesture.state == .ended || gesture.state == .cancelled {previous=nil;persist()}
 }
 func stamp(_ center:CGPoint){
  let radius=max(1,min(50,options["size"] as? CGFloat ?? 14)),opacity=max(0.01,min(1,options["opacity"] as? CGFloat ?? 1)),color=mode==2 ? UIColor.white : UIColor(studioHex:options["color"] as? String ?? "#082DB5")
  gpu?.stamp(center,size:renderer.bounds.size,camera:camera,radius:radius,opacity:opacity,color:color);dirty=true
 }
}
