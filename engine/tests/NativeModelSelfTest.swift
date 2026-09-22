import UIKit
import SceneKit

/// Included only by the isolated export verification target.
enum NativeModelSelfTest {
 static func run(){
  var results=[[String:Any]]()
  for url in Bundle.main.urls(forResourcesWithExtension:"glb",subdirectory:nil) ?? [] {
   do {
    let root=try NativeGLB(Data(contentsOf:url)).scene(),gpu=try NativePaintGPU(),scene=SCNScene(),camera=SCNNode();scene.rootNode.addChildNode(root);camera.position=SCNVector3(0,1.1,3.7);camera.look(at:SCNVector3Zero);scene.rootNode.addChildNode(camera);try gpu.attach(root)
    let blank=gpu.snapshot(),start=CACurrentMediaTime()
    for index in 0..<30{gpu.stamp(CGPoint(x:140+index*3,y:180),size:CGSize(width:361,height:330),camera:camera,radius:14,opacity:1,color:.red)}
    let elapsed=(CACurrentMediaTime()-start)*1000/30,painted=gpu.snapshot();guard blank != painted else{throw NativeGLBError.invalid("GPU did not paint")}
    let view=NativeModelView(frame:CGRect(x:0,y:0,width:361,height:330));view.gpu?.restore(painted)
    guard let png=view.record()?["png"] as? String,let bytes=Data(base64Encoded:png),let image=UIImage(data:bytes)?.cgImage else{throw NativeGLBError.invalid("PNG encode failed")};view.readPNG(image);guard view.snapshot()==painted else{throw NativeGLBError.invalid("PNG roundtrip changed pixels")}
    gpu.restore(blank);guard gpu.snapshot()==blank else{throw NativeGLBError.invalid("Undo mismatch")};gpu.restore(painted);guard gpu.snapshot()==painted else{throw NativeGLBError.invalid("Redo mismatch")}
    root.eulerAngles.y=1.2;gpu.stamp(CGPoint(x:180,y:170),size:CGSize(width:361,height:330),camera:camera,radius:40,opacity:1,color:.blue);guard gpu.snapshot() != painted else{throw NativeGLBError.invalid("Rotated model did not paint")}
    gpu.clear();guard gpu.snapshot()==blank else{throw NativeGLBError.invalid("Clear mismatch")}
    results.append(["model":url.lastPathComponent,"passed":true,"meanStampMilliseconds":elapsed])
   }catch{results.append(["model":url.lastPathComponent,"passed":false,"error":error.localizedDescription])}
  }
  let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0];try? JSONSerialization.data(withJSONObject:results,options:.prettyPrinted).write(to:folder.appendingPathComponent("model-self-test.json"),options:.atomic)
 }
}
