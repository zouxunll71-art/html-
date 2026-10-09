import UIKit
import Darwin

/// Opt-in measurements driven by the existing hidden mirror. Ordinary usage
/// never samples pixels or starts a probe. Times begin inside the workbench,
/// excluding the mirror's automation command polling interval.
final class WorkbenchPerformance {
 static let shared=WorkbenchPerformance()
 private var probe:(tag:String,start:TimeInterval,unix:TimeInterval,pixels:[UInt8])?
 private var timeout:DispatchWorkItem?
 var isActive:Bool{probe != nil}
 static func inputMarker(_ tag:String,side:String){report(["type":"performanceInput","tag":tag+":input","parentTag":tag,"side":side,"machAbsoluteTicks":String(mach_absolute_time()),"monotonicMs":ProcessInfo.processInfo.systemUptime*1000,"source":"host-input-received"])}
 static func report(_ value:[String:Any]){
  guard let data=try? JSONSerialization.data(withJSONObject:value,options:.sortedKeys),let line=String(data:data,encoding:.utf8) else{return}
  NSLog("STUDIO_WORKBENCH_PERF %@",line)
  let url=FileManager.default.temporaryDirectory.appendingPathComponent("studio-workbench-performance.jsonl")
  if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
  if let handle=try? FileHandle(forWritingTo:url){defer{try? handle.close()};try? handle.seekToEnd();try? handle.write(contentsOf:Data((line+"\n").utf8))}
 }
 private func pixels(_ image:CGImage)->[UInt8]?{
  // Sample only central page content; status/tab-bar highlights cannot pass.
  let rect=CGRect(x:CGFloat(image.width)*0.12,y:CGFloat(image.height)*0.15,width:CGFloat(image.width)*0.76,height:CGFloat(image.height)*0.67)
  guard let crop=image.cropping(to:rect) else{return nil}
  var bytes=[UInt8](repeating:0,count:32*64*4)
  let ok=bytes.withUnsafeMutableBytes{data -> Bool in
   guard let ctx=CGContext(data:data.baseAddress,width:32,height:64,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
   ctx.interpolationQuality = .low;ctx.draw(crop,in:CGRect(x:0,y:0,width:32,height:64));return true
  }
  return ok ? bytes:nil
 }
 func begin(_ tag:String,image:CGImage?){
  timeout?.cancel();probe=nil
  guard let image=image,let pixels=pixels(image) else{Self.report(["tag":tag,"side":"ios","error":"missing baseline frame"]);return}
  probe=(tag,ProcessInfo.processInfo.systemUptime,Date().timeIntervalSince1970,pixels)
  Self.inputMarker(tag,side:"ios")
  let job=DispatchWorkItem{[weak self] in guard let self=self,let probe=self.probe,probe.tag==tag else{return};self.probe=nil;Self.report(["tag":tag,"side":"ios","error":"no content change within 5 seconds"])}
  timeout=job;DispatchQueue.main.asyncAfter(deadline:.now()+5,execute:job)
 }
 func presented(_ image:CGImage,endpoint:String="host-image-assignment"){
  guard let p=probe,let current=pixels(image) else{return}
  var changed=0
  for i in stride(from:0,to:current.count,by:4){let delta=(0..<3).reduce(0){$0+abs(Int(current[i+$1])-Int(p.pixels[i+$1]))};if delta>60{changed+=1}}
  guard Double(changed)/2048>=0.05 else{return}
  let elapsed=(ProcessInfo.processInfo.systemUptime-p.start)*1000
  probe=nil;timeout?.cancel();timeout=nil
  Self.report(["tag":p.tag,"side":"ios","inputToContentFrameMs":elapsed,"unixMs":p.unix*1000,"monotonicMs":p.start*1000,"endpoint":endpoint,"changedFraction":Double(changed)/2048])
 }
}
