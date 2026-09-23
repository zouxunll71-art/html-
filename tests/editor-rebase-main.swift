import Foundation

typealias O = [String:Any]
func node(_ id:String,_ x:Double,_ type:String="image")->O {["id":id,"type":type,"x":x,"y":10.0,"width":20.0,"height":30.0,"parent":"","text":"old"]}
func page(_ id:String,_ nodes:[O])->O {["id":id,"nodes":nodes]}
func project(_ pages:[O],_ rev:String="a")->O {["id":"test-project","pages":pages,"compileRevision":rev,"assets":[rev]]}
func nodes(_ p:O,_ id:String)->[O] {(p["pages"] as! [O]).first{$0["id"] as? String==id}!["nodes"] as! [O]}
func check(_ yes:Bool,_ label:String){if !yes{fatalError(label)};print("PASS "+label)}

@main struct Tests { static func main() {
 let base=project([page("home",[node("a",10)]),page("detail",[node("b",20)])])
 var local=base;local["pages"]=[page("home",[node("a",44)]),page("detail",[node("b",65)])]
 var changed=node("a",10);changed["text"]="new text"
 let remote=project([page("home",[changed,node("new",90)]),page("detail",[node("b",20)])],"b")
 let first=EditorRebase.merge(base:base,local:local,remote:remote)
 check(nodes(first.project,"home")[0]["x"] as? Double==44,"local move survives source update")
 check(nodes(first.project,"home")[0]["text"] as? String=="new text","untouched local text follows HTML")
 check(nodes(first.project,"home").count==2,"new HTML layers survive")
 check((first.project["assets"] as? [String])==["b"],"catalog always refreshes")
 check(nodes(first.project,"detail")[0]["x"] as? Double==65,"offscreen page draft retained")
 let again=EditorRebase.merge(base:remote,local:first.project,remote:remote)
 check(EditorRebase.equal(again.project,first.project),"repeat refresh does not lose edits")
 let clean=EditorRebase.merge(base:base,local:base,remote:remote)
 check(EditorRebase.equal(clean.project,remote),"clean snapshot follows complete remote")
 let removed=EditorRebase.merge(base:base,local:local,remote:project([page("home",[node("new",90)]),page("detail",[node("b",20)])],"c"))
 check(removed.unresolved.contains("a") && nodes(removed.project,"home").count==1,"removed source nodes are archived, not resurrected")
 let typed=EditorRebase.merge(base:base,local:local,remote:project([page("home",[node("a",20,"nativeButton")]),page("detail",[node("b",20)])],"c"))
 check(typed.unresolved.contains("a"),"type changes require retained draft")
 var deleted=base;deleted["pages"]=[page("home",[]),page("detail",[node("b",20)])]
 let deletion=EditorRebase.merge(base:base,local:deleted,remote:remote)
 check(nodes(deletion.project,"home")[0]["hidden"] as? Bool==true && nodes(deletion.project,"home")[1]["hidden"]==nil,"local deletion hides only original node")
 var nested=node("child",25);nested["parent"]="parent"
 let nestedBase=project([page("nested",[node("parent",10,"container"),nested])])
 var edited=nested;edited["width"]=60.0
 let nestedLocal=project([page("nested",[node("parent",10,"container"),edited])])
 var nestedRemote=nested;nestedRemote["x"]=40.0
 let nestedResult=EditorRebase.merge(base:nestedBase,local:nestedLocal,remote:project([page("nested",[node("parent",25,"container"),nestedRemote,node("new-child",45)])],"b"))
 check(nodes(nestedResult.project,"nested")[1]["width"] as? Double==60 && nodes(nestedResult.project,"nested")[1]["x"] as? Double==40,"nested resize keeps fresh parent position")
 var other=remote;other["id"]="other"
 check(EditorRebase.merge(base:base,local:local,remote:other).unresolved==["project changed"],"cross-project edits never applied")
 }}
