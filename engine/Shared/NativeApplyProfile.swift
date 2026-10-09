import Foundation

/// Main-thread, opt-in aggregation. No node-level timers, serialization or logs.
/// Nested timings are inclusive and must not be added to their parent duration.
final class NativeApplyProfile {
 static var active:NativeApplyProfile?
 let metadata:[String:Any]
 let clock:()->Double
 let started:Double
 var context="runtime"
 private(set) var timings:[String:Double]=[:]
 private(set) var counts:[String:Int]=[:]
 private(set) var scenePasses:[String:[String:Any]]=[:]
 private(set) var sceneWorkCounts:[String:[String:Any]]=[:]
 init(metadata:[String:Any],clock:@escaping()->Double={ProcessInfo.processInfo.systemUptime*1000}){
  self.metadata=metadata;self.clock=clock;started=clock()
 }
 static func begin(_ metadata:[String:Any],enabled:Bool)->NativeApplyProfile?{
  guard enabled,active==nil else{return nil}
  let value=NativeApplyProfile(metadata:metadata);active=value;return value
 }
 static func finish(_ profile:NativeApplyProfile?){
  guard let profile=profile,active === profile else{return}
  active=nil
  if let data=try? JSONSerialization.data(withJSONObject:profile.report(),options:.sortedKeys),let text=String(data:data,encoding:.utf8){NSLog("STUDIO_APPLY_PHASES %@",text)}
 }
 static func measure<T>(_ key:String,_ body:()->T)->T{
  guard let profile=active else{return body()}
  let start=profile.clock(),previous=profile.context;profile.context=key
  defer{profile.add(key,profile.clock()-start);profile.context=previous}
  return body()
 }
 func add(_ key:String,_ elapsed:Double){timings[key,default:0]+=elapsed;counts[key,default:0]+=1}
 func scenePass(kind:String,page:String,context:String,start:Double){
  let key=kind+"|"+context+"|"+page
  var value=scenePasses[key] ?? ["kind":kind,"context":context,"page":page,"count":0,"ms":0.0]
  value["count"]=(value["count"] as? Int ?? 0)+1;value["ms"]=(value["ms"] as? Double ?? 0)+clock()-start;scenePasses[key]=value
 }
 func sceneWork(page:String,context:String,counts:[String:Int]){
  let key=context+"|"+page
  var value=sceneWorkCounts[key] ?? ["page":page,"context":context,"passes":0]
  value["passes"]=(value["passes"] as? Int ?? 0)+1
  for (name,count) in counts{value[name]=(value[name] as? Int ?? 0)+count}
  sceneWorkCounts[key]=value
 }
 func report()->[String:Any]{
  var result=metadata;result["schema"]="studio-native-apply-phases/1";result["startedMonotonicMs"]=started;result["totalMs"]=clock()-started
  var phases=Dictionary(uniqueKeysWithValues:["scrollOnly","prepare","snapshot","render","assetsSchedule"].map{($0,timings[$0] ?? 0)})
  phases["render",default:0]+=timings["render.finalLayout"] ?? 0
  result["phaseMs"]=phases
  result["detailMs"]=timings;result["counts"]=counts;result["scenePasses"]=scenePasses.keys.sorted().compactMap{scenePasses[$0]}
  result["sceneWork"]=sceneWorkCounts.keys.sorted().compactMap{sceneWorkCounts[$0]}
  return result
 }
}
