import UIKit
import ImageIO

/// Main-thread, cost-bounded LRU. Never retains every image in the project.
final class AssetImageCache {
 private var entries:[String:(UIImage,Int,Int)]=[:]
 private var clock=0,cost=0
 let limit:Int
 init(megabytes:Int=64){limit=megabytes*1024*1024}
 var count:Int{entries.count}
 subscript(id:String)->UIImage? {
  get{guard let entry=entries[id] else{return nil};clock+=1;entries[id]=(entry.0,entry.1,clock);return entry.0}
  set{
   if let old=entries.removeValue(forKey:id){cost-=old.1}
   guard let image=newValue else{return}
   let bytes=image.cgImage.map{$0.bytesPerRow*$0.height} ?? Int(image.size.width*image.size.height*4)
   guard bytes<=limit else{return}
   while cost+bytes>limit,let oldest=entries.min(by:{$0.value.2<$1.value.2}){cost-=oldest.value.1;entries.removeValue(forKey:oldest.key)}
   clock+=1;entries[id]=(image,bytes,clock);cost+=bytes
  }
 }
 func removeAll(){entries.removeAll();cost=0}
}

enum AssetImages {
 static let queue:OperationQueue={let q=OperationQueue();q.name="studio.image.decode";q.maxConcurrentOperationCount=3;q.qualityOfService = .userInitiated;return q}()
 static func decode(_ data:Data,maxPixels:Int=1024)->UIImage? {
  guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixels,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else{return nil}
  return UIImage(cgImage:cg)
 }
 static func load(_ url:URL,maxPixels:Int,completion:@escaping(UIImage?)->Void){queue.addOperation{let image=autoreleasepool{(try? Data(contentsOf:url)).flatMap{decode($0,maxPixels:maxPixels)}};DispatchQueue.main.async{completion(image)}}}
}
