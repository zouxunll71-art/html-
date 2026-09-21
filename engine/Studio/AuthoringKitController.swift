import UIKit

final class AuthoringKitController:UIViewController {
 let projectID:String?;let source:String;let guide:String
 var onNew:(()->Void)?
 private let status=UILabel();private let copyButton=UIButton(type:.system)
 init(projectID:String?,source:String,guide:String){self.projectID=projectID;self.source=source;self.guide=guide;super.init(nibName:nil,bundle:nil);modalPresentationStyle = .formSheet;preferredContentSize=CGSize(width:780,height:670)}
 required init?(coder:NSCoder){fatalError()}
 override var keyCommands:[UIKeyCommand]?{[UIKeyCommand(input:UIKeyCommand.inputEscape,modifierFlags:[],action:#selector(close))]}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .systemBackground
  let title=UILabel();title.text="HTML 模板与 Codex 编写规范";title.font = .systemFont(ofSize:20,weight:.semibold)
  let close=UIButton(type:.system);close.setTitle("关闭",for:.normal);close.addTarget(self,action:#selector(self.close),for:.touchUpInside)
  let intro=UILabel();intro.text="native-rules/2 · 新项目 393 × 852\n"+(source.isEmpty ? "新建模板项目会自动附带 AGENTS.md、编写规范与校验入口。" : "当前项目："+source);intro.numberOfLines=0;intro.font = .systemFont(ofSize:13);intro.textColor = .secondaryLabel
  let text=UITextView();text.text=guide;text.font = .systemFont(ofSize:14);text.isEditable=false;text.isSelectable=true;text.accessibilityIdentifier="authoring.guide"
  let new=UIButton(type:.system);new.setTitle("新建模板项目",for:.normal);new.addAction(UIAction{[weak self]_ in guard let self=self else{return};self.dismiss(animated:true){self.onNew?()}},for:.touchUpInside)
  copyButton.setTitle(projectID == nil ? "复制 Codex 编写说明" : "安装规范并复制 Codex 指令",for:.normal);copyButton.addAction(UIAction{[weak self]_ in self?.copyInstructions()},for:.touchUpInside)
  let path=UIButton(type:.system);path.setTitle("复制项目路径",for:.normal);path.isEnabled = !source.isEmpty;path.addAction(UIAction{[weak self]_ in guard let self=self else{return};UIPasteboard.general.string=self.source;self.status.text="项目路径已复制"},for:.touchUpInside)
  let actions=UIStackView(arrangedSubviews:[new,copyButton,path]);actions.axis = .horizontal;actions.spacing=18;actions.distribution = .fillProportionally
  status.text="现有项目安装规范会保留原有 AGENTS.md 内容和 CODEX_TASK.md。";status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabel;status.numberOfLines=0
  for v in [title,close,intro,text,actions,status]{v.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(v)}
  let g=view.safeAreaLayoutGuide
  NSLayoutConstraint.activate([
   title.leadingAnchor.constraint(equalTo:g.leadingAnchor,constant:24),title.topAnchor.constraint(equalTo:g.topAnchor,constant:22),title.trailingAnchor.constraint(lessThanOrEqualTo:close.leadingAnchor,constant:-12),
   close.trailingAnchor.constraint(equalTo:g.trailingAnchor,constant:-20),close.centerYAnchor.constraint(equalTo:title.centerYAnchor),close.widthAnchor.constraint(equalToConstant:54),close.heightAnchor.constraint(equalToConstant:40),
   intro.topAnchor.constraint(equalTo:title.bottomAnchor,constant:12),intro.leadingAnchor.constraint(equalTo:title.leadingAnchor),intro.trailingAnchor.constraint(equalTo:g.trailingAnchor,constant:-24),
   text.topAnchor.constraint(equalTo:intro.bottomAnchor,constant:14),text.leadingAnchor.constraint(equalTo:g.leadingAnchor,constant:20),text.trailingAnchor.constraint(equalTo:g.trailingAnchor,constant:-20),text.bottomAnchor.constraint(equalTo:actions.topAnchor,constant:-12),
   actions.leadingAnchor.constraint(equalTo:title.leadingAnchor),actions.trailingAnchor.constraint(equalTo:intro.trailingAnchor),actions.heightAnchor.constraint(equalToConstant:44),actions.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-8),
   status.leadingAnchor.constraint(equalTo:title.leadingAnchor),status.trailingAnchor.constraint(equalTo:intro.trailingAnchor),status.bottomAnchor.constraint(equalTo:g.bottomAnchor,constant:-18)
  ])
 }
 private func copyInstructions(){
  copyButton.isEnabled=false;status.text="正在准备 Codex 编写说明…"
  let completed:(Result<Data,Error>)->Void={[weak self] result in
   guard let self=self else{return};self.copyButton.isEnabled=true
   switch result {
   case .success(let data):
    guard let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let prompt=payload["prompt"] as? String else{self.status.text="无法读取编写说明";return}
    UIPasteboard.general.string=prompt;self.status.text=self.projectID == nil ? "说明已复制；请先新建模板项目，再让 Codex 在该目录编写。" : "规范已写入当前项目，Codex 指令已复制。粘贴给 Codex 后补充你的需求即可。"
   case .failure(let error):self.status.text=error.localizedDescription
   }
  }
  if let id=projectID{Bridge.shared.json("/install-authoring-kit",["id":id],completion:completed)}else{Bridge.shared.request("/authoring-kit",completion:completed)}
 }
 @objc private func close(){dismiss(animated:true)}
}
extension StudioController {
 func showAuthoringKit(){
  let pid=project?.id;let query=pid.map{"?id="+$0} ?? ""
  Bridge.shared.request("/authoring-kit"+query){[weak self] result in
   guard let self=self else{return}
   switch result {
   case .success(let data):
    guard let p=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let guide=p["guide"] as? String else{return}
    let panel=AuthoringKitController(projectID:pid,source:p["source"] as? String ?? "",guide:guide)
    panel.onNew={[weak self] in self?.ask("新建 HTML 模板项目",value:"我的 App"){[weak self] name in self?.newHTMLProject(name:name)}}
    self.present(panel,animated:true)
   case .failure(let e):self.error(e)
   }
  }
 }
}
