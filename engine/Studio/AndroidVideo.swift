import UIKit
import AVFoundation
import CoreMedia
/// Continuous Android H.264 stream, decoded by AVFoundation, without PNG screenshots.
final class AndroidVideo:UIView,URLSessionDataDelegate {
 override class var layerClass:AnyClass{AVSampleBufferDisplayLayer.self}
 var display:AVSampleBufferDisplayLayer{layer as! AVSampleBufferDisplayLayer}
 private var session:URLSession?;private var task:URLSessionDataTask?;private var buffer=Data();private var sps:Data?;private var pps:Data?;private var format:CMVideoFormatDescription?;var frameCount=0;var onFrame:(()->Void)?;var stopped=false;private var generation=0;private var decodeQueue:OperationQueue?
 override init(frame:CGRect){super.init(frame:frame);display.videoGravity = .resizeAspect;isUserInteractionEnabled=false}
 required init?(coder:NSCoder){fatalError()}
 func start(){stopped=false;buffer.removeAll();format=nil;sps=nil;pps=nil
  let queue=OperationQueue();decodeQueue=queue;queue.maxConcurrentOperationCount=1;queue.qualityOfService = .userInteractive
  let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=86400;config.timeoutIntervalForResource=86400
  session=URLSession(configuration:config,delegate:self,delegateQueue:queue)
  var req=URLRequest(url:URL(string:Bridge.shared.base+"/android-stream")!);req.setValue(Bridge.shared.token,forHTTPHeaderField:"X-Studio-Token")
  task=session?.dataTask(with:req);task?.resume()
 }
 func stop(){stopped=true;task?.cancel();session?.invalidateAndCancel();session=nil;task=nil}
 func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){buffer.append(data);parse();generation+=1;let g=generation
  DispatchQueue.global(qos:.userInteractive).asyncAfter(deadline:.now()+0.012){[weak self]in self?.decodeQueue?.addOperation{[weak self]in guard let self=self,self.generation==g,self.buffer.count>4 else{return};let prefix=self.buffer.starts(with:[0,0,0,1]) ? 4 : 3;self.consume(self.buffer.dropFirst(prefix));self.buffer.removeAll()}}}
 func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){guard !stopped else{return};DispatchQueue.main.asyncAfter(deadline:.now()+1){[weak self]in self?.display.flush();self?.start()}}
 private func parse(){
  // Android Annex B uses both 3- and 4-byte start codes. Keep the unfinished NAL.
  var starts:[(Int,Int)]=[];buffer.withUnsafeBytes{raw in let bytes=raw.bindMemory(to:UInt8.self);var i=0;while i+3<bytes.count{if bytes[i]==0 && bytes[i+1]==0 {if bytes[i+2]==1{starts.append((i,3));i+=3;continue};if bytes[i+2]==0 && bytes[i+3]==1{starts.append((i,4));i+=4;continue}};i+=1}}
  guard starts.count>=2 else{return}
  for i in 0..<(starts.count-1){let a=starts[i].0+starts[i].1,b=starts[i+1].0;if b>a{consume(buffer.subdata(in:a..<b))}}
  buffer.removeSubrange(0..<starts.last!.0)
 }
 private func consume(_ nal:Data){guard let first=nal.first else{return};let type=first&0x1f
  if type==7{sps=nal;format=nil;return};if type==8{pps=nal;format=nil;return}
  guard type==1 || type==5 else{return}
  if format==nil,let sps=sps,let pps=pps{sps.withUnsafeBytes{s in pps.withUnsafeBytes{p in
   let ptrs=[s.bindMemory(to:UInt8.self).baseAddress!,p.bindMemory(to:UInt8.self).baseAddress!];let sizes=[sps.count,pps.count]
   CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:2,parameterSetPointers:ptrs,parameterSetSizes:sizes,nalUnitHeaderLength:4,formatDescriptionOut:&format)
  }}}
  guard let format=format else{return};var length=UInt32(nal.count).bigEndian;var packet=Data(bytes:&length,count:4);packet.append(nal)
  var block:CMBlockBuffer?;guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:packet.count,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:packet.count,flags:0,blockBufferOut:&block)==kCMBlockBufferNoErr,let block=block else{return}
  packet.withUnsafeBytes{_ = CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block,offsetIntoDestination:0,dataLength:packet.count)}
  var sample:CMSampleBuffer?;var size=packet.count;var timing=CMSampleTimingInfo(duration:.invalid,presentationTimeStamp:.invalid,decodeTimeStamp:.invalid)
  guard CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:1,sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample)==noErr,let sample=sample else{return}
  if let array=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true){let dict=unsafeBitCast(CFArrayGetValueAtIndex(array,0),to:CFMutableDictionary.self);CFDictionarySetValue(dict,Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())}
  if display.status == .failed{display.flush()};display.enqueue(sample);frameCount+=1
  if frameCount==1{DispatchQueue.main.async{self.onFrame?()}}
 }
}
