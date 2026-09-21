import UIKit

final class ProjectChooser:UIViewController,UITableViewDataSource,UITableViewDelegate {
 let projects:[StudioProject],current:String?;let table=UITableView(frame:.zero,style:.insetGrouped)
 var onSelect:((StudioProject)->Void)?,onCreate:(()->Void)?
 init(_ projects:[StudioProject],current:String?){self.projects=projects;self.current=current;super.init(nibName:nil,bundle:nil);title="选择项目";preferredContentSize=CGSize(width:620,height:470)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .systemGroupedBackground;table.dataSource=self;table.delegate=self;table.rowHeight=76;view.addSubview(table)
  navigationItem.leftBarButtonItem=UIBarButtonItem(title:"关闭",primaryAction:UIAction{[weak self]_ in self?.dismiss(animated:true)})
  navigationItem.rightBarButtonItem=UIBarButtonItem(title:"新建空白项目",primaryAction:UIAction{[weak self]_ in self?.dismiss(animated:true){self?.onCreate?()}})
 }
 override func viewDidLayoutSubviews(){super.viewDidLayoutSubviews();table.frame=view.bounds}
 func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{projects.count}
 func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{let p=projects[indexPath.row],c=UITableViewCell(style:.subtitle,reuseIdentifier:nil);c.textLabel?.text=p.name;c.textLabel?.font = .systemFont(ofSize:17,weight:.medium);c.detailTextLabel?.text=p.sourcePath;c.detailTextLabel?.lineBreakMode = .byTruncatingMiddle;c.imageView?.image=UIImage(systemName:"folder");c.accessoryType=p.id==current ? .checkmark:.none;return c}
 func tableView(_ tableView:UITableView,didSelectRowAt indexPath:IndexPath){let p=projects[indexPath.row];dismiss(animated:true){self.onSelect?(p)}}
}
extension StudioController {
 func chooseProject(){Bridge.shared.request("/projects"){[weak self]result in guard let self=self else{return};do{let projects=try JSONDecoder().decode([StudioProject].self,from:result.get());let chooser=ProjectChooser(projects,current:self.project?.id);chooser.onSelect={[weak self]p in self?.switchProject(p)};chooser.onCreate={[weak self]in self?.newHTMLProject()};let nav=UINavigationController(rootViewController:chooser);nav.modalPresentationStyle = .formSheet;self.present(nav,animated:true)}catch{self.error(error)}}}
 func switchProject(_ next:StudioProject){guard project?.id != next.id else{return};saveTimer?.invalidate();previewTimer?.invalidate();if dirty,let p=project,let data=try? JSONEncoder().encode(p){Bridge.shared.request("/save",body:data){[weak self]result in if case .failure(let error)=result{self?.error(error)}else{self?.useProject(next)}}}else{useProject(next)}}
}
