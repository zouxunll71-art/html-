import Foundation

final class ImageToken {let label:String;init(_ label:String){self.label=label}}
func check(_ condition:Bool,_ message:String){precondition(condition,message);print("PASS "+message)}
func identity(_ project:String="A",_ version:String="v1")->AssetResourceIdentity{AssetResourceIdentity(project:project,asset:"portrait",version:version)}

@main struct AssetPoolTests {
 static func main(){
  let pool=AssetResourcePool<ImageToken>(limit:100,maxConcurrent:2)
  var complete:((ImageToken?,Int)->Void)?
  var first:ImageToken?,second:ImageToken?
  pool.request(identity(),pixels:300,produce:{complete=$0},completion:{first=$0})
  pool.request(identity(),pixels:150,produce:{_ in fatalError("duplicate decode")},completion:{second=$0})
  check(pool.diagnostics["loads"]==1 && pool.diagnostics["coalesced"]==1,"in-flight larger decode coalesces smaller request")
  complete?(ImageToken("a"),80);complete=nil
  check(first === second && pool.cost==80,"subscribers share the same decoded object and byte charge")
  pool.request(identity("B"),pixels:300,produce:{$0(ImageToken("b"),80)},completion:{_ in})
  check(pool.cost==80 && pool.diagnostics["strongEntries"]==1,"LRU stays within decoded byte budget across projects")
  check(pool.value(for:identity(),pixels:200) === first,"evicted object retained by a cached page is reused through weak ownership")
  first=nil;second=nil
  check(pool.value(for:identity(),pixels:200)==nil,"weak registry does not keep evicted pages alive")
  check(pool.value(for:identity("B"),pixels:301)==nil,"lower resolution never satisfies a larger request")
  check(pool.value(for:identity("B","v2"),pixels:200)==nil,"changed bytes cannot hit stale asset identity")
  check(pool.value(for:identity("A"),pixels:200)==nil,"same asset name does not cross project boundary")

  var oversize:ImageToken?
  pool.request(identity("C"),pixels:600,produce:{$0(ImageToken("large"),500)},completion:{oversize=$0})
  check(pool.cost==80 && pool.value(for:identity("C"),pixels:500) === oversize,"oversize visible image adds no strong cache cost but remains discoverable")
  pool.releaseStrong()
  check(pool.cost==0 && pool.value(for:identity("C"),pixels:500) === oversize,"memory warning clears strong cache while preserving live view lookup")
  oversize=nil
  check(pool.value(for:identity("C"),pixels:500)==nil,"memory warning plus view release leaves no hidden ownership")

  let race=AssetResourcePool<ImageToken>(limit:100,maxConcurrent:1)
  var oldFinish:((ImageToken?,Int)->Void)?,newFinish:((ImageToken?,Int)->Void)?
  var oldCallbacks=0,newCallbacks=0
  race.request(identity(),pixels:100,produce:{oldFinish=$0},completion:{check($0==nil,"invalidated subscriber completes without old image");oldCallbacks+=1})
  race.retainIdentities([identity("A","v2")])
  race.request(identity("A","v2"),pixels:100,produce:{newFinish=$0},completion:{check($0?.label=="new","new version receives only new bytes");newCallbacks+=1})
  check(oldCallbacks==1 && newFinish==nil,"obsolete flight keeps concurrency slot until it actually stops")
  oldFinish?(ImageToken("old"),30);oldFinish=nil
  check(newFinish != nil && race.value(for:identity(),pixels:100)==nil,"late invalidated response cannot repopulate cache and releases slot")
  newFinish?(ImageToken("new"),30);newFinish=nil
  check(newCallbacks==1 && race.cost==30 && race.diagnostics["active"]==0,"new identity completes once with balanced active accounting")

  let sizing=AssetResourcePool<ImageToken>(limit:100,maxConcurrent:2)
  var small:((ImageToken?,Int)->Void)?,large:((ImageToken?,Int)->Void)?
  sizing.request(identity(),pixels:100,produce:{small=$0},completion:{_ in})
  sizing.request(identity(),pixels:400,produce:{large=$0},completion:{_ in})
  check(sizing.diagnostics["loads"]==2,"a pending thumbnail cannot suppress a required high resolution decode")
  large?(ImageToken("large"),60);large=nil;small?(ImageToken("small"),20);small=nil
  check(sizing.value(for:identity(),pixels:350)?.label=="large" && sizing.cost==80,"out-of-order resolutions preserve appropriate image detail")

  let churn=AssetResourcePool<ImageToken>(limit:100)
  for i in 0..<500{let key=identity("P\(i)");churn.request(key,pixels:300,produce:{$0(ImageToken("\(i)"),30)},completion:{_ in});check(churn.cost<=100,"budget after insertion \(i)")}
  check(churn.diagnostics["strongEntries"]==3 && (churn.diagnostics["liveWeakEntries"] ?? 0)<=3,"released weak metadata and strong images remain bounded after churn")
  print("AssetResourcePool ownership, invalidation, concurrency and resolution tests passed")
 }
}
