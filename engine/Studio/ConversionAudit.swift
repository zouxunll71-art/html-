import UIKit
struct ConversionIssue:Decodable {var level:String;var message:String;var page:String;var node:String;var source:Source
 struct Source:Decodable {var file:String?;var line:Int?}
}
struct ConversionReport:Decodable {var pages:[Page];var assets:Int;var issues:[ConversionIssue];var scope:String
 struct Page:Decodable {var id:String;var name:String;var role:String;var count:Int;var text:Int;var image:Int;var background:Int;var control:Int;var hidden:Int;var expectedCount:Int?;var manualChanges:Int?;var checkedLocales:[String]?}
}
final class ConversionAuditController:UITableViewController {
 let projectID:String;var report:ConversionReport?;var status="正在检查页面、弹窗与资源文件…";var onLocate:((ConversionIssue)->Void)?
 init(_ id:String){projectID=id;super.init(style:.insetGrouped);title="转换检查";preferredContentSize=CGSize(width:660,height:580)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();navigationItem.rightBarButtonItem=UIBarButtonItem(title:"关闭",style:.done,target:self,action:#selector(close));tableView.rowHeight=UITableView.automaticDimension;tableView.estimatedRowHeight=80
  let spinner=UIActivityIndicatorView(style:.medium);spinner.startAnimating();navigationItem.leftBarButtonItem=UIBarButtonItem(customView:spinner)
  Bridge.shared.request("/conversion-audit?id=\(projectID)"){[weak self] result in guard let self=self else{return};self.navigationItem.leftBarButtonItem=nil
   switch result{case .success(let data):do{self.report=try JSONDecoder().decode(ConversionReport.self,from:data)}catch{self.status="检查结果读取失败：\(error.localizedDescription)"};case .failure(let error):self.status="检查失败：\(error.localizedDescription)"};self.tableView.reloadData()
  }
 }
 override var keyCommands:[UIKeyCommand]?{[UIKeyCommand(input:UIKeyCommand.inputEscape,modifierFlags:[],action:#selector(close))]}
 @objc func close(){dismiss(animated:true)}
 override func numberOfSections(in tableView:UITableView)->Int{report==nil ? 1:3}
 override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{guard let r=report else{return 1};return section==0 ? 1 : section==1 ? max(1,r.issues.count):r.pages.count}
 override func tableView(_ tableView:UITableView,titleForHeaderInSection section:Int)->String?{section==0 ? "检查范围" : section==1 ? "需要处理 · 点击定位":"页面与弹窗清单"}
 override func tableView(_ tableView:UITableView,cellForRowAt path:IndexPath)->UITableViewCell{
  let cell=UITableViewCell(style:.subtitle,reuseIdentifier:nil);cell.textLabel?.numberOfLines=0;cell.detailTextLabel?.numberOfLines=0;cell.selectionStyle = .none
  guard let r=report else{cell.textLabel?.text=status;return cell}
  if path.section==0{cell.textLabel?.text="\(r.pages.count) 个页面 / 弹窗 · \(r.assets) 个资源 · \(r.issues.filter{$0.level=="error"}.count) 项错误 · \(r.issues.filter{$0.level=="warning"}.count) 项提醒";cell.detailTextLabel?.text=r.scope}
  else if path.section==1{
   if r.issues.isEmpty{cell.textLabel?.text="本次检查未发现结构、资源文件或同步冲突问题"}
   else{let item=r.issues[path.row];cell.textLabel?.text=(item.level=="error" ? "错误 · ":"提醒 · ")+item.message;cell.detailTextLabel?.text=[item.page,item.node,item.source.file.map{$0+":"+String(item.source.line ?? 1)} ?? ""].filter{!$0.isEmpty}.joined(separator:"\n");cell.accessoryType=item.page.isEmpty ? .none:.disclosureIndicator;cell.selectionStyle = .default}
  }else{let p=r.pages[path.row];cell.textLabel?.text=p.name;cell.detailTextLabel?.text="文字 \(p.text) · 图片 \(p.image) · 容器/背景 \(p.background) · 控件 \(p.control)\n共 \(p.count) 层，其中隐藏 \(p.hidden) 层\n源图层 \(p.expectedCount ?? p.count) · 保留手工修改 \(p.manualChanges ?? 0) 层"}
  return cell
 }
 override func tableView(_ tableView:UITableView,didSelectRowAt path:IndexPath){guard path.section==1,let r=report,r.issues.indices.contains(path.row),!r.issues[path.row].page.isEmpty else{return};let issue=r.issues[path.row],locate=onLocate;dismiss(animated:true){locate?(issue)}}
}
extension StudioController {
 func showConversionAudit(){
  guard let p=project else{setStatus("请先导入项目");return}
  guard !dirty && !historyGesture && !previewInFlight else{save(silent:true);setStatus("正在保存当前编辑，请保存完成后再打开转换检查");return}
  let controller=ConversionAuditController(p.id);controller.onLocate={[weak self] issue in self?.locateConversionIssue(issue)}
  let navigation=UINavigationController(rootViewController:controller);navigation.modalPresentationStyle = .formSheet;navigation.preferredContentSize=controller.preferredContentSize;present(navigation,animated:true)
 }
 func locateConversionIssue(_ issue:ConversionIssue){
  guard let p=project,let index=p.pages.firstIndex(where:{$0.id==issue.page}) else{return}
  if running{switchRunMode()};pageIndex=index;selected=issue.node.isEmpty ? nil:issue.node;multiSelection=[];isolatedSelection=selected;updatePage();openIOSLayers()
  dispatchEvent(["type":"navigate","page":issue.page],side:"ios");setStatus(issue.message)
 }
}
