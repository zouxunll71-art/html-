import Foundation

/// Content identity is separate from decode size. A model/layout revision does
/// not invalidate unchanged image bytes, and project identities never overlap.
struct AssetResourceIdentity:Hashable {
 let project:String
 let asset:String
 let version:String
}

/// Main-thread ownership for decoded resources. Strong entries have a byte
/// budget; weak entries discover resources still owned by live/cached views.
/// Evicting the LRU therefore never forces a second decode of an alive image.
final class AssetResourcePool<Value:AnyObject> {
 private struct Key:Hashable {let identity:AssetResourceIdentity;let pixels:Int}
 private final class WeakValue {weak var value:Value?;init(_ value:Value){self.value=value}}
 private struct Entry {let value:Value;let cost:Int;var used:UInt64}
 private final class Flight {
  let key:Key;let produce:(@escaping(Value?,Int)->Void)->Void
  var callbacks:[(Value?)->Void]
  init(_ key:Key,_ produce:@escaping(@escaping(Value?,Int)->Void)->Void,_ callback:@escaping(Value?)->Void){self.key=key;self.produce=produce;callbacks=[callback]}
 }
 private var strong:[Key:Entry]=[:],weakValues:[AssetResourceIdentity:[Int:WeakValue]]=[:],flights:[Key:Flight]=[:],pending=[Flight]()
 private var clock:UInt64=0,active=0
 private(set) var cost=0
 private(set) var requests=0,strongHits=0,weakHits=0,coalesced=0,loads=0,evictions=0
 let limit:Int,maxConcurrent:Int
 init(limit:Int,maxConcurrent:Int=4){self.limit=max(0,limit);self.maxConcurrent=max(1,maxConcurrent)}
 private func checkThread(){precondition(Thread.isMainThread,"Resource ownership must remain on the main thread")}
 private func touch(_ key:Key){clock &+= 1;if var entry=strong[key]{entry.used=clock;strong[key]=entry}}
 private func pruneWeak(){for identity in Array(weakValues.keys){pruneWeak(identity)}}
 private func pruneWeak(_ identity:AssetResourceIdentity){
  guard let entries=weakValues[identity] else{return}
  let alive=entries.filter{$0.value.value != nil}
  if alive.isEmpty{weakValues.removeValue(forKey:identity)}else{weakValues[identity]=alive}
 }
 func value(for identity:AssetResourceIdentity,pixels:Int)->Value? {
  checkThread();pruneWeak(identity)
  guard let variants=weakValues[identity],let size=variants.keys.filter({$0>=pixels}).min(),let value=variants[size]?.value else{return nil}
  let key=Key(identity:identity,pixels:size)
  if strong[key] != nil{strongHits+=1;touch(key)}else{weakHits+=1}
  return value
 }
 func request(_ identity:AssetResourceIdentity,pixels:Int,produce:@escaping(@escaping(Value?,Int)->Void)->Void,completion:@escaping(Value?)->Void){
  checkThread();requests+=1
  if let value=value(for:identity,pixels:pixels){completion(value);return}
  if let key=flights.keys.filter({$0.identity==identity && $0.pixels>=pixels}).min(by:{$0.pixels<$1.pixels}),let flight=flights[key]{coalesced+=1;flight.callbacks.append(completion);return}
  let key=Key(identity:identity,pixels:pixels),flight=Flight(key,produce,completion)
  flights[key]=flight;pending.append(flight);pump()
 }
 private func pump(){
  while active<maxConcurrent,!pending.isEmpty {
   let flight=pending.removeFirst()
   guard flights[flight.key] === flight else{continue}
   active+=1;loads+=1
   flight.produce{[weak self,flight] value,bytes in
    guard let self=self else{return};self.checkThread();self.active-=1
    if self.flights[flight.key] === flight {
     self.flights.removeValue(forKey:flight.key)
     if let value=value{self.insert(value,key:flight.key,cost:bytes)}
     let callbacks=flight.callbacks;flight.callbacks.removeAll();callbacks.forEach{$0(value)}
    }
    self.pump()
   }
  }
 }
 private func insert(_ value:Value,key:Key,cost bytes:Int){
  pruneWeak(key.identity);weakValues[key.identity,default:[:]][key.pixels]=WeakValue(value)
  if let old=strong.removeValue(forKey:key){cost-=old.cost}
  guard bytes>=0,bytes<=limit else{return}
  while cost>limit-bytes,let oldest=strong.min(by:{$0.value.used<$1.value.used}){cost-=oldest.value.cost;strong.removeValue(forKey:oldest.key);evictions+=1}
  clock &+= 1;strong[key]=Entry(value:value,cost:bytes,used:clock);cost+=bytes
 }
 /// Invalidated in-flight work may finish, but cannot populate a new identity.
 /// Complete obsolete subscribers with nil so ownership/pending state is closed.
 func retainIdentities(_ identities:Set<AssetResourceIdentity>){
  checkThread()
  for key in Array(strong.keys) where !identities.contains(key.identity){cost-=strong.removeValue(forKey:key)!.cost}
  weakValues=weakValues.filter{identities.contains($0.key)};pruneWeak()
  let obsolete=flights.values.filter{!identities.contains($0.key.identity)}
  for flight in obsolete{flights.removeValue(forKey:flight.key)}
  pending.removeAll{!identities.contains($0.key.identity)}
  for flight in obsolete{let callbacks=flight.callbacks;flight.callbacks.removeAll();callbacks.forEach{$0(nil)}}
 }
 func releaseStrong(){checkThread();strong.removeAll();cost=0;pruneWeak()}
 var diagnostics:[String:Int]{checkThread();pruneWeak();return ["requests":requests,"strongHits":strongHits,"weakHits":weakHits,"coalesced":coalesced,"loads":loads,"evictions":evictions,"strongBytes":cost,"strongEntries":strong.count,"liveWeakEntries":weakValues.values.reduce(0){$0+$1.count},"active":active,"queued":pending.count]}
}
