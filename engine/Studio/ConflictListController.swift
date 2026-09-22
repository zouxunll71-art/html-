import UIKit
final class ConflictListController:UITableViewController {
 let projectID:String;var conflicts:[[String:Any]];var onResolved:(()->Void)?;var resolving=false
 init(projectID:String,conflicts:[[String:Any]]){self.projectID=projectID;self.conflicts=conflicts;super.init(style:.insetGrouped)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();refreshTitle();tableView.rowHeight=UITableView.automaticDimension;tableView.estimatedRowHeight=100;navigationItem.rightBarButtonItem=UIBarButtonItem(title:"关闭",style:.done,target:self,action:#selector(close))}
 @objc func close(){dismiss(animated:true)}
 func refreshTitle(){title=conflicts.isEmpty ? "没有两端修改差异":"\(conflicts.count) 项差异 · 导出采用 iOS"}
 override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{conflicts.count}
 override func tableView(_ tableView:UITableView,titleForHeaderInSection section:Int)->String?{"导出默认保持当前 iOS 页面效果，不必逐项处理。这里可查看差异；只有想改回 HTML 或恢复旧图层时才手动选择。"}
 func value(_ object:Any?)->String{guard let object=object,!(object is NSNull) else{return "无"};if let number=object as? NSNumber{return String(format:"%.4g",number.doubleValue)};if JSONSerialization.isValidJSONObject(object),let data=try? JSONSerialization.data(withJSONObject:object,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8){return text};return String(describing:object)}
 func field(_ c:[String:Any])->String{let key=c["field"] as? String ?? "";return ["x":"横向位置","y":"纵向位置","width":"宽度","height":"高度","fontSize":"字号","lineHeight":"行高","*":"整个图层"][key] ?? key}
 override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell {
  let c=conflicts[indexPath.row],cell=UITableViewCell(style:.subtitle,reuseIdentifier:nil),key=c["key"] as? String ?? ""
  cell.textLabel?.text="\(key.components(separatedBy:"/").first ?? "页面") · \(field(c))";cell.textLabel?.numberOfLines=0
  cell.detailTextLabel?.text="\(c["reason"] as? String ?? "属性发生冲突")\n\(key)";cell.detailTextLabel?.numberOfLines=0;cell.accessoryType = .disclosureIndicator;return cell
 }
 override func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){
  tableView.deselectRow(at:indexPath,animated:true);guard !resolving else{return};let c=conflicts[indexPath.row]
  let deleted=c["field"] as? String=="*"
  let detail="原因：\(c["reason"] as? String ?? "两端修改了同一属性")\n图层：\(c["key"] as? String ?? "")\n属性：\(field(c))\n原值：\(value(c["base"]))\nHTML：\(value(c["html"]))\niOS：\(value(c["ios"]))"+(deleted ? "\n\n采用 HTML：删除该旧图层的覆盖记录。保留 iOS：尝试将原图层恢复为 iOS 独立图层；源页面已删除时需先恢复页面。":"")
  let alert=UIAlertController(title:"选择保留的修改",message:detail,preferredStyle:.alert)
  for choice in ["ios","html"]{alert.addAction(UIAlertAction(title:choice=="ios" ? "保留 iOS 修改":"采用 HTML",style:.default){[weak self]_ in self?.resolve(c,choice:choice)})}
  alert.addAction(UIAlertAction(title:"暂不处理",style:.cancel));present(alert,animated:true)
 }
 func resolve(_ conflict:[String:Any],choice:String){
  guard let key=conflict["key"] as? String,let field=conflict["field"] as? String else{return};resolving=true
  Bridge.shared.json("/conflict",["projectID":projectID,"key":key,"field":field,"choice":choice]){[weak self] result in
   guard let self=self else{return}
   if case .failure(let error)=result{self.resolving=false;self.showError(error.localizedDescription);return}
   self.onResolved?()
   Bridge.shared.request("/status"){[weak self] result in
    guard let self=self else{return};self.resolving=false
    do{let data=try result.get();guard let status=try JSONSerialization.jsonObject(with:data) as? [String:Any],status["active"] as? String==self.projectID else{self.showError("项目已切换，请关闭并重新打开冲突列表");return};self.conflicts=status["conflicts"] as? [[String:Any]] ?? [];self.refreshTitle();self.tableView.reloadData()}catch{self.showError(error.localizedDescription)}
   }
  }
 }
 func showError(_ text:String){let alert=UIAlertController(title:"处理未完成",message:text,preferredStyle:.alert);alert.addAction(UIAlertAction(title:"知道了",style:.cancel));present(alert,animated:true)}
}
