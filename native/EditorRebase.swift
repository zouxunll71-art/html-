import Foundation

/// Three-way merge of editable snapshots. New catalog/schema always comes from the server.
enum EditorRebase {
 typealias Object = [String:Any]
 static func equal(_ a:Any?,_ b:Any?)->Bool {
  guard let a=a,let b=b else{return a == nil && b == nil}
  return NSDictionary(dictionary:["v":a]).isEqual(to:["v":b])
 }
 static func index(_ values:[Object])->[String:Object] {
  var result=[String:Object]();for item in values {if let id=item["id"] as? String{result[id]=item}};return result
 }
 static func patches(_ base:Object,_ local:Object,ignoring:Set<String>)->Object {
  var changes=Object()
  for key in Set(base.keys).union(local.keys) where !ignoring.contains(key) && !equal(base[key],local[key]) {changes[key]=local[key] ?? NSNull()}
  return changes
 }
 static func apply(_ patch:Object,to value:Object)->Object {
  var out=value;for (key,v) in patch {if v is NSNull{out.removeValue(forKey:key)}else{out[key]=v}};return out
 }
 static func merge(base:Object,local:Object,remote:Object)->(project:Object,unresolved:[String]) {
  guard base["id"] as? String==local["id"] as? String,local["id"] as? String==remote["id"] as? String else{return(remote,["project changed"])}
  var out=remote,unresolved=[String]()
  let basePages=index(base["pages"] as? [Object] ?? []),localPages=index(local["pages"] as? [Object] ?? [])
  let remotePages=remote["pages"] as? [Object] ?? []
  let remoteIDs=Set(remotePages.compactMap{$0["id"] as? String})
  for (id,page) in localPages where !remoteIDs.contains(id) && !equal(page,basePages[id]){unresolved.append(id)}
  out["pages"]=remotePages.map { fresh -> Object in
   guard let id=fresh["id"] as? String,let old=basePages[id],let edited=localPages[id] else{return fresh}
   let before=index(old["nodes"] as? [Object] ?? []),after=index(edited["nodes"] as? [Object] ?? [])
   let nodes=fresh["nodes"] as? [Object] ?? [];let newMap=index(nodes)
   var merged=[Object]()
   // Runtime values, scrolling, and source identities are never stale appearance edits.
   let ignored:Set<String>=["id","type","source","sharedKey","textKey","placeholderKey","symbol","selected","isOn","value","scrollX","scrollY","contentWidth","contentHeight"]
   for node in nodes {
    guard let key=node["id"] as? String,let was=before[key] else{merged.append(node);continue}
    guard let now=after[key] else{var hidden=node;hidden["hidden"]=true;merged.append(hidden);continue}
    let delta=patches(was,now,ignoring:ignored)
    guard !delta.isEmpty else{merged.append(node);continue}
    if !equal(was["type"],node["type"]){unresolved.append(key);merged.append(node);continue}
    if let parent=delta["parent"] as? String,!parent.isEmpty,newMap[parent]==nil,after[parent]==nil {unresolved.append(key);merged.append(node);continue}
    merged.append(apply(delta,to:node))
   }
   for node in edited["nodes"] as? [Object] ?? [] {
    guard let key=node["id"] as? String,newMap[key]==nil else{continue}
    if let was=before[key] {if !patches(was,node,ignoring:ignored).isEmpty{unresolved.append(key)}}
    else if let parent=node["parent"] as? String,!parent.isEmpty,newMap[parent]==nil,before[parent] != nil {unresolved.append(key)}
    else{merged.append(node)}
   }
   var page=fresh;page["nodes"]=merged;return page
  }
  if !equal(base["selectionColor"],local["selectionColor"]){out["selectionColor"]=local["selectionColor"]}
  return(out,unresolved)
 }
 static func changedPages(base:Object,local:Object)->Set<String> {
  let original=index(base["pages"] as? [Object] ?? [])
  return Set((local["pages"] as? [Object] ?? []).compactMap{p in guard let id=p["id"] as? String else{return nil};return equal(p,original[id]) ? nil:id})
 }
}
