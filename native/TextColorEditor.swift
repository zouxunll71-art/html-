import UIKit
final class TextColorPanel:UIStackView {
 let preview=UIView(),hex=UITextField(),hue=UISlider(),saturation=UISlider(),brightness=UISlider(),opacitySlider=UISlider()
 var commit:((UIColor)->Void)?
 init(color:UIColor){
  super.init(frame:.zero);axis = .vertical;spacing=7
  let title=UILabel();title.text="文案颜色";title.font = .systemFont(ofSize:13,weight:.semibold);addArrangedSubview(title)
  let row=UIStackView();row.spacing=8;preview.layer.cornerRadius=5;preview.layer.borderWidth=1;preview.layer.borderColor=UIColor.separator.cgColor;preview.widthAnchor.constraint(equalToConstant:30).isActive=true;row.addArrangedSubview(preview)
  hex.borderStyle = .roundedRect;hex.font = .monospacedSystemFont(ofSize:12,weight:.regular);hex.accessibilityLabel="文案颜色 HEX";hex.addTarget(self,action:#selector(hexChanged),for:.editingDidEnd);row.addArrangedSubview(hex);row.heightAnchor.constraint(equalToConstant:30).isActive=true;addArrangedSubview(row)
  let palette=UIStackView();palette.spacing=5;palette.distribution = .fillEqually
  for value in ["#FFFFFF","#111111","#082DB5","#D51B17","#FFC52B","#2C8658","#9450B3"]{
   let button=UIButton(type:.system);button.backgroundColor=UIColor(studioHex:value);button.layer.cornerRadius=5;button.layer.borderWidth=1;button.layer.borderColor=UIColor.separator.cgColor;button.accessibilityLabel="文案颜色 "+value
   button.addAction(UIAction{[weak self]_ in self?.load(UIColor(studioHex:value));self?.send()},for:.touchUpInside);palette.addArrangedSubview(button)
  }
  palette.heightAnchor.constraint(equalToConstant:26).isActive=true;addArrangedSubview(palette)
  for (name,slider) in [("色相",hue),("饱和度",saturation),("明暗",brightness),("透明度",opacitySlider)] {
   let row=UIStackView();row.spacing=6;let label=UILabel();label.text=name;label.font = .systemFont(ofSize:12);label.widthAnchor.constraint(equalToConstant:48).isActive=true;row.addArrangedSubview(label);slider.minimumValue=0;slider.maximumValue=1;slider.accessibilityLabel="文案"+name;slider.addTarget(self,action:#selector(sliding),for:.valueChanged);slider.addTarget(self,action:#selector(slideFinished),for:[.touchUpInside,.touchUpOutside,.touchCancel]);row.addArrangedSubview(slider);row.heightAnchor.constraint(equalToConstant:25).isActive=true;addArrangedSubview(row)
  }
  load(color)
 }
 required init(coder:NSCoder){fatalError()}
 var color:UIColor{UIColor(hue:CGFloat(hue.value),saturation:CGFloat(saturation.value),brightness:CGFloat(brightness.value),alpha:CGFloat(opacitySlider.value))}
 func load(_ color:UIColor){var h:CGFloat=0,s:CGFloat=0,b:CGFloat=0,a:CGFloat=0;color.getHue(&h,saturation:&s,brightness:&b,alpha:&a);hue.value=Float(h);saturation.value=Float(s);brightness.value=Float(b);opacitySlider.value=Float(a);refresh()}
 static func code(_ color:UIColor)->String{var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0;color.getRed(&r,green:&g,blue:&b,alpha:&a);return String(format:"#%02X%02X%02X%02X",Int((r*255).rounded()),Int((g*255).rounded()),Int((b*255).rounded()),Int((a*255).rounded()))}
 func refresh(){preview.backgroundColor=color;hex.text=Self.code(color);hex.textColor = .label}
 @objc func sliding(){refresh()}
 @objc func slideFinished(){send()}
 func send(){commit?(color)}
 @objc func hexChanged(){let value=(hex.text ?? "").trimmingCharacters(in:.whitespacesAndNewlines);guard value.range(of:"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$",options:.regularExpression) != nil else{hex.textColor = .systemRed;return};load(UIColor(studioHex:value));send()}
}
extension StudioController {
 func addTextColorPanel(_ node:StudioNode){
  guard let projectID=project?.id,let pageID=page?.id else{return}
  let panel=TextColorPanel(color:UIColor(studioHex:node.color));panel.isUserInteractionEnabled = !node.locked
  panel.commit={[weak self] color in
   guard let self=self,!self.running,self.project?.id==projectID,self.page?.id==pageID,let index=self.page?.nodes.firstIndex(where:{$0.id==node.id}),self.page?.nodes[index].locked==false else{return}
   let value=TextColorPanel.code(color)
   guard TextColorPanel.code(UIColor(studioHex:self.page!.nodes[index].color)) != value else{return}
   self.checkpoint();self.project!.pages[self.pageIndex].nodes[index].color=value;self.changed();self.setStatus("文案颜色已更新，可撤销")
  }
  propertyStack.addArrangedSubview(panel)
 }
}
enum ThumbnailContrast {
 static func colors(_ node:StudioNode)->(UIColor,UIColor){
  var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0
  UIColor(studioHex:node.color).getRed(&r,green:&g,blue:&b,alpha:&a)
  let light = !node.text.isEmpty && (r*0.2126+g*0.7152+b*0.0722)>0.65
  return light ? (UIColor(studioHex:"#454B56"),UIColor(studioHex:"#59616E")) : (UIColor(studioHex:"#F1F4F8"),UIColor(studioHex:"#E2E7EF"))
 }
 static func layout(_ view:UIView){view.setNeedsLayout();view.layoutIfNeeded();for child in view.subviews{layout(child)}}
}
