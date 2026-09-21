import UIKit
import UniformTypeIdentifiers

final class ProjectImportController:UIViewController,UIDocumentPickerDelegate,UIDropInteractionDelegate {
 let nameField=UITextField(),folderLabel=UILabel(),message=UILabel()
 let choose=UIButton(type:.system),create=UIButton(type:.system),cancel=UIButton(type:.system)
 var folder:URL?;var accessing=false;var busy=false
 var onCreate:((URL,String,@escaping(Error?)->Void)->Void)?
 static func folderURL(_ item:NSSecureCoding?)->URL? {
  if let url=item as? URL{return url.isFileURL ? url:nil}
  if let data=item as? Data{return URL(dataRepresentation:data,relativeTo:nil)}
  if let text=item as? String,let url=URL(string:text),url.isFileURL{return url}
  return nil
 }
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .systemBackground
  preferredContentSize=CGSize(width:540,height:350)
  let stack=UIStackView();stack.axis = .vertical;stack.spacing=16;stack.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:26),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-26),stack.topAnchor.constraint(equalTo:view.topAnchor,constant:26)])
  let title=UILabel();title.text="创建项目";title.font = .systemFont(ofSize:22,weight:.semibold);stack.addArrangedSubview(title)
  nameField.placeholder="项目名称";nameField.borderStyle = .roundedRect;nameField.heightAnchor.constraint(equalToConstant:42).isActive=true;nameField.addAction(UIAction{[weak self]_ in self?.updateState()},for:.editingChanged);stack.addArrangedSubview(nameField)
  let caption=UILabel();caption.text="源文件夹";caption.font = .systemFont(ofSize:13);stack.addArrangedSubview(caption)
  let box=UIStackView();box.axis = .vertical;box.alignment = .center;box.spacing=12;box.isLayoutMarginsRelativeArrangement=true;box.directionalLayoutMargins=NSDirectionalEdgeInsets(top:16,leading:16,bottom:16,trailing:16);box.backgroundColor = .secondarySystemBackground;box.layer.cornerRadius=12
  folderLabel.text="拖入 HTML 项目文件夹（包含 app.json），或点击添加";folderLabel.font = .systemFont(ofSize:13);folderLabel.textColor = .secondaryLabel;folderLabel.numberOfLines=2;folderLabel.textAlignment = .center;folderLabel.lineBreakMode = .byTruncatingMiddle;box.addArrangedSubview(folderLabel)
  choose.configuration = .bordered();choose.setTitle("添加文件夹",for:.normal);choose.addAction(UIAction{[weak self]_ in self?.pickFolder()},for:.touchUpInside);box.addArrangedSubview(choose);stack.addArrangedSubview(box)
  message.font = .systemFont(ofSize:12);message.textColor = .systemRed;message.numberOfLines=2;stack.addArrangedSubview(message)
  let row=UIStackView();row.spacing=12;row.addArrangedSubview(UIView());cancel.setTitle("取消",for:.normal);cancel.addAction(UIAction{[weak self]_ in self?.dismiss(animated:true)},for:.touchUpInside);row.addArrangedSubview(cancel)
  create.configuration = .filled();create.setTitle("创建项目",for:.normal);create.addAction(UIAction{[weak self]_ in self?.submit()},for:.touchUpInside);row.addArrangedSubview(create);stack.addArrangedSubview(row)
  view.addInteraction(UIDropInteraction(delegate:self))
  if let folder=folder{setFolder(folder)};updateState()
 }
 deinit{if accessing{folder?.stopAccessingSecurityScopedResource()}}
 func setFolder(_ url:URL){
  if accessing{folder?.stopAccessingSecurityScopedResource()}
  folder=url;accessing=url.startAccessingSecurityScopedResource()
  if nameField.text?.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty != false{nameField.text=url.lastPathComponent}
  folderLabel.text=url.path;choose.setTitle("更换文件夹",for:.normal);message.text=nil;updateState()
 }
 func updateState(){create.isEnabled = !busy && folder != nil && !(nameField.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines).isEmpty;choose.isEnabled = !busy;cancel.isEnabled = !busy;nameField.isEnabled = !busy;isModalInPresentation=busy}
 func pickFolder(){let picker=UIDocumentPickerViewController(forOpeningContentTypes:[.folder],asCopy:false);picker.delegate=self;picker.allowsMultipleSelection=false;present(picker,animated:true)}
 func documentPicker(_ controller:UIDocumentPickerViewController,didPickDocumentsAt urls:[URL]){if let url=urls.first{setFolder(url)}}
 func submit(){guard !busy,let folder=folder else{return};busy=true;message.text="正在导入项目…";updateState();onCreate?(folder,(nameField.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines)){[weak self]error in guard let self=self else{return};self.busy=false;self.updateState();if let error=error{self.message.text=error.localizedDescription}else{self.dismiss(animated:true)}}}
 func dropInteraction(_ interaction:UIDropInteraction,canHandle session:UIDropSession)->Bool{!busy && session.hasItemsConforming(toTypeIdentifiers:[UTType.fileURL.identifier])}
 func dropInteraction(_ interaction:UIDropInteraction,sessionDidUpdate session:UIDropSession)->UIDropProposal{UIDropProposal(operation:.copy)}
 func dropInteraction(_ interaction:UIDropInteraction,performDrop session:UIDropSession){session.items.first?.itemProvider.loadItem(forTypeIdentifier:UTType.fileURL.identifier,options:nil){[weak self]item,error in DispatchQueue.main.async{if let url=Self.folderURL(item){self?.setFolder(url)}else{self?.message.text=error?.localizedDescription ?? "无法读取文件夹，请点击添加文件夹选择"}}}}
}

extension StudioController {
 func showProjectImport(_ folder:URL?=nil){
  guard !bulkRunning,!splashPinned,!splashRequestBusy else{setStatus("请先结束批量复制或恢复页面跟随，再导入项目");return}
  guard presentedViewController==nil else{return}
  let form=ProjectImportController();form.folder=folder;form.modalPresentationStyle = .formSheet
  form.onCreate={[weak self]url,name,done in
   guard let self=self else{return}
   let begin={
    Bridge.shared.json("/import",["path":url.path,"name":name]){[weak self]r in
     guard let self=self else{return}
     switch r{case .failure(let e):done(e)
     case .success(let data):
      do{let p=try JSONDecoder().decode(StudioProject.self,from:data);self.useProject(p);self.loadProjects();done(nil)}catch{done(error)}
     }
    }
   }
   if self.dirty,let p=self.project,let data=try? JSONEncoder().encode(p){self.saveTimer?.invalidate();Bridge.shared.request("/save",body:data){r in if case .failure(let e)=r{done(e)}else{begin()}}}else{begin()}
  }
  present(form,animated:true)
 }
}
