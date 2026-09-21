import UIKit
final class AssetCompressionController:UIViewController {
 static var jobs:[String:String]=[:]
 let projectID:String
 let status=UILabel(),progress=UIProgressView(progressViewStyle:.default),mode=UISegmentedControl(items:["严格无损","JPEG 视觉压缩"]),start=UIButton(type:.system),copyPath=UIButton(type:.system)
 var job:String?,timer:Timer?,output=""
 init(_ id:String){projectID=id;super.init(nibName:nil,bundle:nil);title="资源压缩";preferredContentSize=CGSize(width:560,height:520)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){super.viewDidLoad();view.backgroundColor = .systemBackground
  navigationItem.rightBarButtonItem=UIBarButtonItem(title:"关闭",style:.done,target:self,action:#selector(close))
  let description=UILabel();description.numberOfLines=0;description.font = .systemFont(ofSize:14);description.text="在桌面生成可导入的 HTML 项目副本，原文件保留。\n严格无损：优化 PNG，像素、尺寸、透明度不变。\n视觉压缩：额外将 JPEG 以质量 85 压缩，需检查画质。\n已优化或不能缩小的图片保持原样。副本不包含工作台独有的 iOS 编辑覆盖。"
  mode.selectedSegmentIndex=0;start.setTitle("压缩资源并生成副本",for:.normal);start.addTarget(self,action:#selector(begin),for:.touchUpInside)
  status.numberOfLines=0;status.font = .systemFont(ofSize:14);status.text="所有已登记资源都会核对；字体保持原样。压缩时可关闭窗口，稍后重新打开查看进度。"
  copyPath.setTitle("复制结果文件夹路径",for:.normal);copyPath.isHidden=true;copyPath.addAction(UIAction{[weak self]_ in UIPasteboard.general.string=self?.output},for:.touchUpInside)
  let stack=UIStackView(arrangedSubviews:[description,mode,start,progress,status,copyPath]);stack.axis = .vertical;stack.spacing=18;stack.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:22)])
  if let existing=Self.jobs[projectID]{job=existing;start.isEnabled=false;mode.isEnabled=false;timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self]_ in self?.poll()};poll()}
 }
 @objc func begin(){start.isEnabled=false;mode.isEnabled=false;copyPath.isHidden=true;progress.progress=0;status.text="正在检查资源，准备压缩…"
  Bridge.shared.json("/compress-assets",["id":projectID,"mode":mode.selectedSegmentIndex==0 ? "lossless":"visual"]){[weak self]result in guard let self=self else{return};switch result{case .failure(let e):self.failed(e.localizedDescription);case .success(let data):guard let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let job=obj["job"] as? String else{self.failed("未收到压缩任务");return};self.job=job;Self.jobs[self.projectID]=job;self.timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true){[weak self]_ in self?.poll()};self.poll()}}
 }
 func failed(_ text:String){timer?.invalidate();timer=nil;status.text=text;start.isEnabled=true;mode.isEnabled=true}
 func poll(){guard let job=job else{return};Bridge.shared.request("/compression-status?job=\(job)"){[weak self]result in guard let self=self else{return};switch result{case .failure(let e):self.failed(e.localizedDescription);case .success(let data):guard let obj=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return};let done=obj["done"] as? Int ?? 0,total=obj["total"] as? Int ?? 0;self.progress.progress=total>0 ? Float(done)/Float(total):0;self.status.text="\(obj["stage"] as? String ?? "处理中") · \(done) / \(total)"
   if obj["state"] as? String=="failed"{self.failed((obj["error"] as? String ?? "压缩失败")+"\n原项目未修改。");return}
   if obj["state"] as? String=="done",let report=obj["report"] as? [String:Any]{self.timer?.invalidate();self.timer=nil;self.output=report["path"] as? String ?? "";self.copyPath.isHidden=false;let before=report["before"] as? Int64 ?? 0,after=report["after"] as? Int64 ?? 0;self.status.text="完成：\(report["changed"] ?? 0) 个文件缩小\n\(ByteCountFormatter.string(fromByteCount:before,countStyle:.file)) → \(ByteCountFormatter.string(fromByteCount:after,countStyle:.file))\n桌面副本已生成。完整明细在「资源压缩报告.json」。";self.progress.progress=1;self.start.isEnabled=true;self.mode.isEnabled=true;self.start.setTitle("再次生成压缩副本",for:.normal)}
  }}}
 @objc func close(){timer?.invalidate();timer=nil;dismiss(animated:true)}
 deinit{timer?.invalidate()}
}
extension StudioController {
 func showAssetCompression(){guard let p=project else{setStatus("请先导入项目");return};let controller=UINavigationController(rootViewController:AssetCompressionController(p.id));controller.modalPresentationStyle = .formSheet;controller.isModalInPresentation=true;present(controller,animated:true)}
}
