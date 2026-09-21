import UIKit
/// Real UIKit controls in both the simulator and the exported application.
final class NativeControlHost:UIView {
 let kind:String;let control:UIView;var baseSize:CGSize;var onAction:(()->Void)?
 init(kind:String){self.kind=kind
  switch kind {
  case "nativeCheckbox":control=UIButton(type:.system);baseSize=CGSize(width:32,height:32)
  case "nativeSwitch":control=UISwitch();baseSize=CGSize(width:51,height:31)
  case "nativeButton":control=UIButton(type:.system);baseSize=CGSize(width:160,height:44)
  case "nativeTextField":control=UITextField();baseSize=CGSize(width:220,height:40)
  case "nativeTextView":control=UITextView();baseSize=CGSize(width:220,height:120)
  case "nativeSlider":control=UISlider();baseSize=CGSize(width:220,height:32)
  case "nativeProgress":control=UIProgressView(progressViewStyle:.default);baseSize=CGSize(width:220,height:4)
  case "nativeSegment":control=UISegmentedControl(items:["第一项","第二项"]);baseSize=CGSize(width:220,height:32)
  case "nativeStepper":control=UIStepper();baseSize=CGSize(width:94,height:32)
  case "nativeSpinner":control=UIActivityIndicatorView(style:.medium);baseSize=CGSize(width:24,height:24)
  default:control=UILabel();baseSize=CGSize(width:180,height:32)
  }
  super.init(frame:.zero);addSubview(control)
  if let c=control as? UIControl{c.addTarget(self,action:#selector(changed(_:)),for:kind=="nativeCheckbox" || kind=="nativeButton" ? .touchUpInside : kind=="nativeTextField" ? .editingChanged : .valueChanged)}
 }
 required init?(coder:NSCoder){fatalError()}
 func configure(_ n:StudioNode){
  control.tintColor=UIColor(studioHex:n.color)
  if let b=control as? UIButton {
   if kind=="nativeCheckbox"{b.setImage(UIImage(systemName:"square"),for:.normal);b.setImage(UIImage(systemName:"checkmark.square.fill"),for:.selected);b.setPreferredSymbolConfiguration(.init(pointSize:26,weight:.regular),forImageIn:.normal);b.isSelected=n.isOn;b.accessibilityLabel=n.text.isEmpty ? "勾选" : n.text}
   else{var config=UIButton.Configuration.filled();config.title=n.text;config.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{var a=$0;a.font = .systemFont(ofSize:n.fontSize);return a};config.baseBackgroundColor=UIColor(studioHex:n.color);config.baseForegroundColor = .white;b.configuration=config}
  }
  if let c=control as? UISwitch{c.isOn=n.isOn;c.onTintColor=UIColor(studioHex:n.color)}
  if let c=control as? UITextField{c.borderStyle = .roundedRect;c.text=n.text;c.placeholder=n.placeholder;c.font = .systemFont(ofSize:n.fontSize);c.textColor=UIColor(studioHex:n.color)}
  if let c=control as? UITextView{c.text=n.text;c.font = .systemFont(ofSize:n.fontSize);c.textColor=UIColor(studioHex:n.color);c.layer.borderWidth=1;c.layer.borderColor=UIColor.separator.cgColor;c.layer.cornerRadius=6}
  if let c=control as? UISlider{c.value=Float(n.value)}
  if let c=control as? UIProgressView{c.progress=Float(n.value);c.progressTintColor=UIColor(studioHex:n.color)}
  if let c=control as? UIStepper{c.minimumValue=0;c.maximumValue=100;c.value=Double(n.value)}
  if let c=control as? UISegmentedControl{c.setTitleTextAttributes([.font:UIFont.systemFont(ofSize:n.fontSize)],for:.normal);c.setTitleTextAttributes([.font:UIFont.systemFont(ofSize:n.fontSize)],for:.selected);c.removeAllSegments();for(i,title)in n.options.enumerated(){c.insertSegment(withTitle:title,at:i,animated:false)};c.selectedSegmentIndex=min(max(0,Int(n.value)),n.options.count-1);c.selectedSegmentTintColor=UIColor(studioHex:n.color).withAlphaComponent(0.2)}
  if let c=control as? UIActivityIndicatorView{c.color=UIColor(studioHex:n.color);n.isOn ? c.startAnimating() : c.stopAnimating();c.hidesWhenStopped=false}
 }
 @objc func changed(_ sender:UIControl){if kind=="nativeCheckbox",let b=sender as? UIButton{b.isSelected.toggle()};onAction?()}
 override func layoutSubviews(){super.layoutSubviews();control.transform = .identity;control.bounds=CGRect(origin:.zero,size:baseSize);control.center=CGPoint(x:bounds.midX,y:bounds.midY);control.transform=CGAffineTransform(scaleX:bounds.width/baseSize.width,y:bounds.height/baseSize.height)}
}
