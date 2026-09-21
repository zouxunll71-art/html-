import UIKit
struct NativeEntry {
 let type:String,title:String,detail:String,symbol:String,size:CGSize
 func node()->StudioNode{var n=StudioNode();n.type=type;n.name=title;n.width=size.width;n.height=size.height;n.color="#147DF5";n.fontSize=16
  switch type{case "nativeCheckbox":n.isOn=false;n.text="";case "nativeSwitch":n.isOn=true;case "nativeButton":n.text="按钮";case "nativeTextField":n.placeholder="请输入内容";case "nativeTextView":n.text="编辑多行文字";case "nativeSegment":n.options=["第一项","第二项"];n.value=0;case "nativeSpinner":n.isOn=true;default:break};return n
 }
 static let all:[NativeEntry]=[
  .init(type:"nativeCheckbox",title:"勾选按钮",detail:"UIButton · 系统勾选符号",symbol:"checkmark.square",size:CGSize(width:32,height:32)),
  .init(type:"nativeSwitch",title:"开关",detail:"UISwitch",symbol:"switch.2",size:CGSize(width:51,height:31)),
  .init(type:"nativeButton",title:"按钮",detail:"UIButton",symbol:"button.horizontal",size:CGSize(width:160,height:44)),
  .init(type:"nativeTextField",title:"输入框",detail:"UITextField",symbol:"character.cursor.ibeam",size:CGSize(width:220,height:40)),
  .init(type:"nativeTextView",title:"多行文本",detail:"UITextView",symbol:"text.alignleft",size:CGSize(width:220,height:120)),
  .init(type:"nativeSlider",title:"滑块",detail:"UISlider",symbol:"slider.horizontal.3",size:CGSize(width:220,height:32)),
  .init(type:"nativeProgress",title:"进度条",detail:"UIProgressView",symbol:"chart.bar.fill",size:CGSize(width:220,height:4)),
  .init(type:"nativeSegment",title:"分段选择",detail:"UISegmentedControl",symbol:"rectangle.split.2x1",size:CGSize(width:220,height:32)),
  .init(type:"nativeStepper",title:"步进器",detail:"UIStepper",symbol:"plusminus",size:CGSize(width:94,height:32)),
  .init(type:"nativeSpinner",title:"加载指示器",detail:"UIActivityIndicatorView",symbol:"progress.indicator",size:CGSize(width:24,height:24))
 ]
}
