import UIKit

final class SourceBrowser:UIView,UITableViewDataSource,UITableViewDelegate,UITableViewDragDelegate,UISearchBarDelegate {
 let caption=UILabel(),crumb=UILabel(),preview=UIImageView(),name=UILabel(),detail=UILabel(),empty=UILabel()
 let back=UIButton(type:.system),whole=UIButton(type:.system),inside=UIButton(type:.system),copy=UIButton(type:.system),copyAll=UIButton(type:.system),search=UISearchBar()
 let table=UITableView(frame:.zero,style:.plain)
 var editingExisting=false {didSet{table.dragInteractionEnabled = !editingExisting;refresh();setNeedsLayout()}}
 var cachedRows=[StudioNode](),depths=[String:Int]()
 var expanded=Set<String>()
 var onLayerAction:((String,String)->Void)?
 var nodes=[StudioNode]() {didSet{indexNodes()}}
 var scope:String?,selectedID:String?,projectID="",signature="",busy=false
 var thumbnail:((StudioNode)->UIImage?)?,onSelect:((String)->Void)?,onCopy:((String,Bool)->Void)?,onDrop:((String,CGPoint,UIWindow)->Void)?
 private(set) var map=[String:StudioNode](),duplicateIDs=Set<String>()
 private var childGroups=[String:[StudioNode]]()
 private func indexNodes(){
  map.removeAll(keepingCapacity:true);duplicateIDs.removeAll(keepingCapacity:true)
  for node in nodes{if map.updateValue(node,forKey:node.id) != nil{duplicateIDs.insert(node.id)}}
  childGroups=Dictionary(grouping:nodes,by:{$0.parent ?? ""})
  if !duplicateIDs.isEmpty{NSLog("Layer browser received %ld duplicate identifiers; ambiguous edits disabled",duplicateIDs.count)}
 }
 func children(_ id:String)->[StudioNode]{childGroups[id] ?? []}
 var treeRows:[(StudioNode,Int)] {
  let ids=Set(nodes.map{$0.id});var seen=Set<String>(),result=[(StudioNode,Int)]()
  let groups=childGroups
  func visit(_ n:StudioNode,_ depth:Int){guard seen.insert(n.id).inserted else{return};result.append((n,depth));if expanded.contains(n.id){for child in groups[n.id] ?? []{visit(child,depth+1)}}}
  for n in nodes where (n.parent ?? "").isEmpty || !ids.contains(n.parent ?? ""){visit(n,0)}
  return result
 }
 var rows:[StudioNode]{let term=search.text?.trimmingCharacters(in:.whitespacesAndNewlines) ?? "";if !term.isEmpty{return nodes.filter{displayName($0).localizedCaseInsensitiveContains(term) || $0.id.localizedCaseInsensitiveContains(term)}};if editingExisting{return treeRows.map{$0.0}};guard let scope=scope else{return nodes.filter{($0.parent ?? "").isEmpty}};let c=children(scope);return c.isEmpty ? nodes.filter{$0.id==scope}:c}
 func displayName(_ n:StudioNode)->String{if !n.text.isEmpty{let text=n.text.replacingOccurrences(of:"\n",with:" ");return text};let short=n.name.components(separatedBy:"/").last ?? n.name;return n.name.contains("/") ? kind(n)+" · "+short : (short.isEmpty ? kind(n):short)}
 func kind(_ n:StudioNode)->String{if n.type=="image"{return "图片"};if n.type=="text"{return "文字"};if n.type=="scroll"{return "滚动区域"};if n.type=="container"{return "组合区域"};if n.type.hasPrefix("native"){return ["nativeButton":"按钮","nativeCheckbox":"勾选框","nativeTextField":"输入框","nativeTextView":"多行输入","nativeSwitch":"开关","nativeSlider":"滑块","nativeStepper":"步进器","nativeSegment":"分段选项","nativeProgress":"进度条","nativeSpinner":"加载指示"][n.type] ?? "控件"};return "背景"}
 override init(frame:CGRect){super.init(frame:frame);backgroundColor = .white
  caption.text="从 HTML 取资源";caption.font = .systemFont(ofSize:17,weight:.semibold)
  crumb.font = .systemFont(ofSize:12);crumb.textColor=UIColor(studioHex:"#526273");crumb.lineBreakMode = .byTruncatingMiddle
  preview.contentMode = .scaleAspectFit;preview.backgroundColor=UIColor(studioHex:"#F0F3F7");preview.layer.cornerRadius=8;preview.clipsToBounds=true
  name.font = .systemFont(ofSize:14,weight:.semibold);name.numberOfLines=2;detail.font = .systemFont(ofSize:12);detail.textColor=UIColor(studioHex:"#526273");detail.numberOfLines=2
  back.setTitle("‹ 上一级",for:.normal);whole.setTitle("整个页面",for:.normal);inside.setTitle("查看内部 ›",for:.normal)
  for b in [back,whole,inside]{b.titleLabel?.font = .systemFont(ofSize:13,weight:.medium)}
  back.addAction(UIAction{[weak self]_ in guard let self=self,let scope=self.scope else{return};self.scope=self.map[scope]?.parent;self.search.text="";self.refresh()},for:.touchUpInside)
  whole.addAction(UIAction{[weak self]_ in self?.scope=self?.nodes.first?.id;if let self=self,self.editingExisting{self.expanded=Set(self.nodes.map{$0.id})};self?.search.text="";self?.refresh()},for:.touchUpInside)
  inside.addAction(UIAction{[weak self]_ in guard let self=self,let id=self.selectedID else{return};self.scope=id;self.expanded.insert(id);self.search.text="";self.refresh()},for:.touchUpInside)
  copy.configuration = .filled();copy.configuration?.baseBackgroundColor=UIColor(studioHex:"#235BDE");copy.configuration?.baseForegroundColor = .white;copy.setTitle("添加这一层到 iOS",for:.normal);copy.addAction(UIAction{[weak self]_ in guard let self=self,let id=self.selectedID else{return};self.onCopy?(id,false)},for:.touchUpInside)
  copyAll.configuration = .bordered();copyAll.setTitle("连同内部一起添加",for:.normal);copyAll.addAction(UIAction{[weak self]_ in guard let self=self,let id=self.selectedID else{return};self.onCopy?(id,true)},for:.touchUpInside)
  search.placeholder="搜索本页文字、图片或图层";search.searchBarStyle = .minimal;search.delegate=self
  table.dataSource=self;table.delegate=self;table.dragDelegate=self;table.dragInteractionEnabled=true;table.rowHeight=76;table.delaysContentTouches=false;table.canCancelContentTouches=false;table.backgroundColor = .white;table.separatorColor=UIColor(studioHex:"#E7ECF2");table.keyboardDismissMode = .onDrag
  empty.text="点击右侧手机中的元素\n这里会显示它的内部图层\n\n拖动缩略图到左侧，也可点击添加";empty.numberOfLines=0;empty.font = .systemFont(ofSize:14);empty.textColor=UIColor(studioHex:"#526273");empty.textAlignment = .center
  [caption,crumb,preview,name,detail,back,whole,inside,copy,copyAll,search,table,empty].forEach{addSubview($0)}
  refresh()
 }
 required init?(coder:NSCoder){fatalError()}
 override func layoutSubviews(){super.layoutSubviews();let w=bounds.width,h=bounds.height
  caption.frame=CGRect(x:16,y:10,width:w-32,height:28);crumb.frame=CGRect(x:16,y:40,width:w-32,height:22)
  preview.frame=CGRect(x:16,y:74,width:84,height:74);name.frame=CGRect(x:112,y:73,width:w-128,height:40);detail.frame=CGRect(x:112,y:115,width:w-128,height:33)
  back.frame=CGRect(x:12,y:158,width:80,height:32);whole.frame=CGRect(x:96,y:158,width:80,height:32);inside.frame=CGRect(x:w-108,y:158,width:96,height:32)
  search.frame=CGRect(x:5,y:194,width:w-10,height:48);table.frame=CGRect(x:8,y:248,width:w-16,height:max(60,h-365))
  copy.frame=CGRect(x:16,y:h-103,width:w-32,height:42);copyAll.frame=CGRect(x:16,y:h-53,width:w-32,height:36);empty.frame=CGRect(x:20,y:200,width:w-40,height:max(90,h-320))
 }
 func update(_ nodes:[StudioNode],projectID:String,signature:String,focus:String?=nil){let changedProject=self.projectID != projectID;self.nodes=nodes;self.projectID=projectID;self.signature=signature
  if changedProject{expanded=Set(nodes.filter{($0.parent ?? "").isEmpty}.map{$0.id});scope=nil;selectedID=nil;search.text=""}
  if let id=focus,map[id] != nil{selectedID=id;var parent=map[id]?.parent;var visited=Set<String>();while let p=parent,visited.insert(p).inserted{expanded.insert(p);parent=map[p]?.parent};scope=children(id).isEmpty ? map[id]?.parent:id;search.text=""}
  if scope==nil || map[scope!] == nil{scope=nodes.first?.id};if let id=selectedID,map[id]==nil{selectedID=nil};refresh()
 }
 func reloadRows(){let tree=treeRows;depths=Dictionary(tree.map{($0.0.id,$0.1)},uniquingKeysWith:{_,latest in latest});cachedRows=rows;table.reloadData()}
 func refresh(){caption.text=editingExisting ? "iOS 图层树":"从 HTML 取资源";copyAll.isHidden=editingExisting;whole.setTitle(editingExisting ? "全部展开":"整个页面",for:.normal);back.isHidden=editingExisting;empty.text=editingExisting ? "当前页面没有图层":"点击右侧手机选择资源";let n=selectedID.flatMap{map[$0]};name.text=n.map{displayName($0)} ?? "先选择一个图层";detail.text=n.map{"\(kind($0)) · \(Int($0.width)) × \(Int($0.height))\n\(editingExisting ? "点选图层，再编辑属性":"拖到左侧可精确放置")"} ?? "点击手机或下方缩略图";preview.image=n.flatMap{thumbnail?($0)}
  let current=scope.flatMap{map[$0]};crumb.text=current.map{"当前范围：\(displayName($0))"} ?? "整个页面";back.isEnabled=current?.parent?.isEmpty==false
  let hasChildren=n.map{!children($0.id).isEmpty} ?? false;inside.isEnabled=hasChildren;copyAll.isEnabled=hasChildren && !busy;copy.isEnabled=n != nil && !busy
  copy.setTitle(editingExisting ? "编辑所选图层属性" : busy ? "添加中…" : hasChildren ? "仅添加这层背景到 iOS":"添加这一层到 iOS",for:.normal)
  if !duplicateIDs.isEmpty{crumb.text="检测到重复图层编号，请检查同步";if let id=selectedID,duplicateIDs.contains(id){detail.text="此图层编号重复，修复同步后再编辑";copy.isEnabled=false;copyAll.isEnabled=false}}
  empty.isHidden = !nodes.isEmpty;table.isHidden=nodes.isEmpty;search.isHidden=nodes.isEmpty;reloadRows()
 }
 func searchBar(_ searchBar:UISearchBar,textDidChange searchText:String){reloadRows()}
 func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{cachedRows.count}
 func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{
  let n=cachedRows[indexPath.row],cell=ResourceLayerCell(style:.default,reuseIdentifier:nil),count=children(n.id).count
  cell.indent=editingExisting && (search.text ?? "").isEmpty ? CGFloat(depths[n.id] ?? 0)*12:0;cell.title.text=(n.hidden ? "◌ ":"")+(n.locked ? "🔒 ":"")+displayName(n);cell.expand.setTitle(editingExisting ? (expanded.contains(n.id) ? "收起":"展开") : "展开 ›",for:.normal);cell.subtitle.text="\(editingExisting ? n.name+" · " : "")\(kind(n)) · \(Int(n.width)) × \(Int(n.height))";cell.thumb.image=thumbnail?(n);cell.expand.isHidden=count==0;cell.backgroundColor=n.id==selectedID ? UIColor(studioHex:"#EAF2FF"):.white
  cell.expand.addAction(UIAction{[weak self]_ in guard let self=self else{return};if self.editingExisting{if !self.expanded.insert(n.id).inserted{self.expanded.remove(n.id)}}else{self.selectedID=n.id;self.scope=n.id;self.onSelect?(n.id)};self.refresh()},for:.touchUpInside)
  cell.expand.isEnabled = !duplicateIDs.contains(n.id)
  cell.thumb.isUserInteractionEnabled = !editingExisting && !duplicateIDs.contains(n.id)
  cell.thumb.onTap={[weak self]in self?.selectedID=n.id;self?.onSelect?(n.id);self?.refresh()};cell.thumb.onDrop={[weak self]point,window in self?.onDrop?(n.id,point,window)}
  cell.accessibilityLabel="\(displayName(n))，\(kind(n))，\(count) 个子图层";return cell
 }
 func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){let n=cachedRows[indexPath.row];selectedID=n.id;if !duplicateIDs.contains(n.id){onSelect?(n.id)};refresh()}
 func tableView(_ tableView:UITableView,accessoryButtonTappedForRowWith indexPath:IndexPath){let n=cachedRows[indexPath.row];guard !duplicateIDs.contains(n.id) else{return};selectedID=n.id;scope=n.id;onSelect?(n.id);refresh()}
 func tableView(_ tableView:UITableView,contextMenuConfigurationForRowAt indexPath:IndexPath,point:CGPoint)->UIContextMenuConfiguration? {
  guard editingExisting else{return nil};let n=cachedRows[indexPath.row];guard !duplicateIDs.contains(n.id) else{return nil}
  return UIContextMenuConfiguration(identifier:nil,previewProvider:nil){[weak self]_ in UIMenu(children:[
   UIAction(title:"重命名",image:UIImage(systemName:"pencil")){_ in self?.onLayerAction?(n.id,"rename")},
   UIAction(title:n.hidden ? "显示图层":"隐藏图层",image:UIImage(systemName:n.hidden ? "eye":"eye.slash")){_ in self?.onLayerAction?(n.id,"hidden")},
   UIAction(title:n.locked ? "解锁图层":"锁定图层",image:UIImage(systemName:n.locked ? "lock.open":"lock")){_ in self?.onLayerAction?(n.id,"locked")}
  ])}
 }
 func tableView(_ tableView:UITableView,itemsForBeginning session:UIDragSession,at indexPath:IndexPath)->[UIDragItem]{guard !busy && !editingExisting else{return []};let n=cachedRows[indexPath.row];guard !duplicateIDs.contains(n.id) else{return []};selectedID=n.id;onSelect?(n.id);let body:[String:Any]=["projectID":projectID,"signature":signature,"node":n.id];guard let data=try? JSONSerialization.data(withJSONObject:body),let value=String(data:data,encoding:.utf8) else{return []};let item=UIDragItem(itemProvider:NSItemProvider(object:("html-node:"+value) as NSString));item.previewProvider={[weak self] in let image=UIImageView(image:self?.thumbnail?(n));image.frame=CGRect(x:0,y:0,width:110,height:90);image.contentMode = .scaleAspectFit;let p=UIDragPreviewParameters();p.backgroundColor = .clear;return UIDragPreview(view:image,parameters:p)};return [item]}
}
