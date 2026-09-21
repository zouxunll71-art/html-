import UIKit
final class ExtractionProgress:UIView {
 let spinner=UIActivityIndicatorView(style:.medium),text=UILabel()
 override init(frame:CGRect){super.init(frame:frame);backgroundColor = .secondarySystemBackground;layer.cornerRadius=12;layer.shadowOpacity=0.16;layer.shadowRadius=10;layer.shadowOffset=CGSize(width:0,height:3);text.font = .systemFont(ofSize:14,weight:.medium);text.numberOfLines=3;addSubview(spinner);addSubview(text);isUserInteractionEnabled=false;isHidden=true}
 required init?(coder:NSCoder){fatalError()}
 override func layoutSubviews(){super.layoutSubviews();spinner.frame=CGRect(x:14,y:bounds.midY-10,width:20,height:20);text.frame=CGRect(x:46,y:10,width:bounds.width-60,height:bounds.height-20)}
 func show(_ message:String,running:Bool=true){isHidden=false;text.text=message;if running{spinner.startAnimating()}else{spinner.stopAnimating()}}
}
extension StudioController {
 func showCoverage(){
  guard let p=project else{return}
  Bridge.shared.request("/coverage?id=\(p.id)"){[weak self]r in
   guard let self=self else{return}
   switch r{case .failure(let e):self.error(e)
   case .success(let data):
    guard let report=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return}
    if self.isManifest {
     self.showMessage("迁移包校验结果","已导入 \(report["templates"] ?? 0) 个模板、\(report["routes"] ?? 0) 个页面/状态、\(report["assets"] ?? 0) 个资源、\(report["layers"] ?? 0) 个图层。\n\n\(report["notice"] ?? "")")
     return
    }
    let issues=report["issues"] as? [[String:Any]] ?? []
    let detail=issues.prefix(30).map{"\($0["file"] ?? ""):\($0["line"] ?? 0)\n\($0["reason"] ?? "")"}.joined(separator:"\n\n")
    self.showMessage("逐文件提取检查","已检查 \(report["fileCount"] ?? 0) 个文件，\(issues.count) 项需核对。\n\n"+detail+"\n\n完整报告随导出工程保存。")
   }
  }
 }
}
