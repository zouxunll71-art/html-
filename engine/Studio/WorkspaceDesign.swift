import UIKit
extension StudioController {
 func configureWorkspaceDesign(){
  view.backgroundColor=UIColor(studioHex:"#F3F6FA");sidebar.backgroundColor=UIColor(studioHex:"#F8FAFC");workspace.backgroundColor=UIColor(studioHex:"#EEF2F7");footer.textColor=UIColor(studioHex:"#435468")
  titleLabel.text="HTML 原生工作台";titleLabel.font = .systemFont(ofSize:18,weight:.semibold)
  projectButton.contentHorizontalAlignment = .left;projectButton.titleLabel?.font = .systemFont(ofSize:13,weight:.medium)
  segments.setTitle("页面",forSegmentAt:0);segments.setTitle("图片库",forSegmentAt:1);segments.setTitle("控件",forSegmentAt:2)
  catalog.rowHeight=58;layers.rowHeight=64;(sidebar.viewWithTag(99) as? UILabel)?.text="iOS 页面图层";search.placeholder="搜索页面或素材"
  mode.setTitle("选取与编辑",forSegmentAt:0);mode.setTitle("运行预览",forSegmentAt:1)
  for b in buttons{b.configuration?.cornerStyle = .medium;b.configuration?.titleTextAttributesTransformer=UIConfigurationTextAttributesTransformer{var a=$0;a.font = .systemFont(ofSize:13,weight:.medium);return a}}
  buttons[6].setTitle("导出 iOS 工程",for:.normal);buttons[6].configuration?.baseBackgroundColor=UIColor(studioHex:"#235BDE");buttons[6].configuration?.baseForegroundColor = .white
  buttons[4].isHidden=true
  helpButton.setTitle("使用指南",for:.normal);helpButton.titleLabel?.font = .systemFont(ofSize:13);helpButton.addAction(UIAction{[weak self]_ in self?.showWorkspaceHelp()},for:.touchUpInside);toolbar.addSubview(helpButton)
  moreProject.setTitle("更多 ▾",for:.normal);moreProject.titleLabel?.font = .systemFont(ofSize:13);moreProject.showsMenuAsPrimaryAction=true;moreProject.menu=UIMenu(children:[UIAction(title:"资源压缩",image:UIImage(systemName:"arrow.down.right.and.arrow.up.left")){[weak self]_ in self?.showAssetCompression()},UIAction(title:"转换检查",image:UIImage(systemName:"checkmark.shield")){[weak self]_ in self?.showConversionAudit()},UIAction(title:"布局版本记录",image:UIImage(systemName:"clock.arrow.circlepath")){[weak self]_ in self?.versions()},UIAction(title:"源码与同步详情",image:UIImage(systemName:"doc.text.magnifyingglass")){[weak self]_ in self?.showSyncDetails()},UIAction(title:"编辑启动页",image:UIImage(systemName:"play.rectangle")){[weak self]_ in self?.toggleSplashEditor()}]);toolbar.addSubview(moreProject)
  editingTools.arrangedSubviews.forEach{editingTools.removeArrangedSubview($0);$0.removeFromSuperview()};editingTools.axis = .horizontal;editingTools.spacing=6;editingTools.distribution = .fillEqually;toolButtons.removeAll()
  for b in [buttons[2],buttons[3]]{b.configuration?.image=nil;editingTools.addArrangedSubview(b)}
  for(key,title,icon)in [("select","选择","cursorarrow"),("clickMulti","多选","checkmark.circle"),("multi","框选","square.dashed")]{let b=button(title,{[weak self]in self?.setTool(key)});b.configuration?.image=UIImage(systemName:icon);b.configuration?.imagePlacement = .leading;b.configuration?.imagePadding=4;b.configuration?.preferredSymbolConfigurationForImage=UIImage.SymbolConfiguration(pointSize:13);b.configuration?.contentInsets=NSDirectionalEdgeInsets(top:5,leading:5,bottom:5,trailing:5);editingTools.addArrangedSubview(b);toolButtons[key]=b}
  moreTools.configuration = .bordered();moreTools.setTitle("调整 / 组合 ▾",for:.normal);moreTools.showsMenuAsPrimaryAction=true
  moreTools.menu=UIMenu(children:[UIAction(title:"拖动调整大小",image:UIImage(systemName:"arrow.up.left.and.arrow.down.right")){[weak self]_ in self?.setTool("resize")},UIAction(title:"拖动旋转",image:UIImage(systemName:"rotate.right")){[weak self]_ in self?.setTool("rotate")},UIAction(title:"组合所选图层",image:UIImage(systemName:"square.on.square")){[weak self]_ in self?.groupSelection()},UIAction(title:"取消组合"){[weak self]_ in self?.ungroupSelection()},UIAction(title:"更改选框颜色",image:UIImage(systemName:"paintpalette")){[weak self]_ in self?.pickSelectionColor()}]);editingTools.addArrangedSubview(moreTools);refreshSnapMenu()
  leftTools.arrangedSubviews.forEach{leftTools.removeArrangedSubview($0);$0.removeFromSuperview()};leftTools.addArrangedSubview(button("＋ 添加文字",{[weak self]in self?.addText()}));leftTools.addArrangedSubview(button("＋ 添加色块",{[weak self]in self?.addShape()}))
  leftTools.addArrangedSubview(button("内部图层",{[weak self]in self?.openIOSLayers()}))
  leftTitle.text="iOS 成品 · 真实模拟器";rightTitle.text="HTML 原型 · 点击取资源"
  sourcePageButton.setTitle("查看整页资源",for:.normal);sourcePageButton.titleLabel?.font = .systemFont(ofSize:13,weight:.semibold);sourcePageButton.addAction(UIAction{[weak self]_ in guard let self=self else{return};self.inspectorTabs.selectedSegmentIndex=1;self.showInspectorMode();self.loadSourceLayers(focus:self.activePage)},for:.touchUpInside);workspace.addSubview(sourcePageButton)
  syncStateLabel.font = .systemFont(ofSize:12,weight:.medium);syncStateLabel.textColor=UIColor(studioHex:"#38664F");syncStateLabel.textAlignment = .right;workspace.addSubview(syncStateLabel);syncStateLabel.isUserInteractionEnabled=true;syncStateLabel.accessibilityTraits = .button;syncStateLabel.addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(showSyncDetails)))
  repairSyncButton.setTitle("检查并修复同步",for:.normal);repairSyncButton.titleLabel?.font = .systemFont(ofSize:12,weight:.semibold);repairSyncButton.addAction(UIAction{[weak self]_ in self?.repairSynchronization()},for:.touchUpInside);workspace.addSubview(repairSyncButton)
  runIOSButton.setTitle("运行 / 重启 iOS",for:.normal);runIOSButton.titleLabel?.font = .systemFont(ofSize:12,weight:.semibold);runIOSButton.addAction(UIAction{[weak self]_ in self?.runIOS()},for:.touchUpInside);workspace.addSubview(runIOSButton)
  closeWebButton.setTitle("关闭网页",for:.normal);closeWebButton.titleLabel?.font = .systemFont(ofSize:12,weight:.semibold);closeWebButton.isHidden=true;closeWebButton.addAction(UIAction{[weak self]_ in guard let self=self,let id=self.project?.id else{return};Bridge.shared.json("/close-native-browser",["id":id]){[weak self]result in if case .failure(let error)=result{self?.error(error)}}},for:.touchUpInside);workspace.addSubview(closeWebButton)
  refreshButton.isHidden=true;splashButton.isHidden=true;androidBack.setTitle("‹ 返回上一页",for:.normal);androidBack.titleLabel?.font = .systemFont(ofSize:13)
  hint.text="选右侧找素材，拖到左侧补齐；选左侧改外观。方向键微调 1 pt，Shift + 方向键 10 pt。";hint.textColor=UIColor(studioHex:"#526273")
  updateHistoryButtons();setTool("select")
 }
 func layoutWorkspaceDesign(){
  let w=view.bounds.width,h=view.bounds.height,sw:CGFloat=w<1320 ? 192:220,iw:CGFloat=w<1320 ? 288:312
  toolbar.frame=CGRect(x:0,y:24,width:w,height:64);titleLabel.frame=CGRect(x:18,y:5,width:205,height:25);projectButton.frame=CGRect(x:18,y:31,width:205,height:28)
  var x=w-18
  for (b,width) in [(buttons[6],CGFloat(132)),(moreProject,66),(buttons[5],86),(helpButton,78),(buttons[1],90),(buttons[0],86)]{x-=width;b.frame=CGRect(x:x,y:17,width:width,height:34);x-=8}
  sidebar.frame=CGRect(x:0,y:89,width:sw,height:h-120);workspace.frame=CGRect(x:sw+1,y:89,width:w-sw-iw-2,height:h-120);inspectorTabs.frame=CGRect(x:w-iw+12,y:103,width:iw-24,height:32);inspector.frame=CGRect(x:w-iw,y:147,width:iw,height:h-178);sourceBrowser.frame=inspector.frame;iosBrowser.frame=inspector.frame
  footer.frame=CGRect(x:18,y:h-28,width:w-36,height:26)
  segments.frame=CGRect(x:12,y:13,width:sw-24,height:32);search.frame=CGRect(x:3,y:52,width:sw-6,height:44)
  let ch=max(130,(sidebar.bounds.height-165)*0.45);catalog.frame=CGRect(x:6,y:104,width:sw-12,height:ch);sidebar.viewWithTag(98)?.frame=CGRect(x:12,y:112+ch,width:sw-24,height:34);sidebar.viewWithTag(99)?.frame=CGRect(x:16,y:165+ch,width:sw-32,height:22);layers.frame=CGRect(x:6,y:195+ch,width:sw-12,height:max(40,sidebar.bounds.height-200-ch))
  let cw=workspace.bounds.width,hh=workspace.bounds.height
  let extra:CGFloat=cw<790 ? 38:0
  mode.frame=CGRect(x:14,y:12,width:216,height:34);copyButton.frame=CGRect(x:240,y:12,width:106,height:34)
  repairSyncButton.frame=CGRect(x:extra>0 ? 14:cw-284,y:12+extra,width:140,height:34);runIOSButton.frame=CGRect(x:extra>0 ? 164:cw-140,y:12+extra,width:126,height:34)
  syncStateLabel.frame=CGRect(x:350,y:12,width:max(0,cw-350-(extra>0 ? 14:296)),height:34)
  editingTools.frame=CGRect(x:14,y:56+extra,width:cw-28,height:34)
  let scale=max(0.1,min((hh-218-extra)/910,(cw-38)/912)),phoneH=910*scale,phoneW=456*scale,gap:CGFloat=14,start=(cw-phoneW*2-gap)/2
  leftTitle.frame=CGRect(x:start,y:100+extra,width:phoneW,height:24);rightTitle.frame=CGRect(x:start+phoneW+gap,y:100+extra,width:phoneW,height:24);syncLabel.isHidden=true
  closeWebButton.frame=CGRect(x:start+phoneW-80,y:100+extra,width:80,height:24);if !closeWebButton.isHidden{leftTitle.frame.size.width=max(0,phoneW-82)}
  left.frame=CGRect(x:start,y:132+extra,width:phoneW,height:phoneH);right.frame=CGRect(x:start+phoneW+gap,y:132+extra,width:phoneW,height:phoneH);web.frame=right.bounds
  leftTools.frame=CGRect(x:left.frame.minX,y:left.frame.maxY+8,width:phoneW,height:34);androidBack.frame=CGRect(x:right.frame.minX,y:right.frame.maxY+8,width:phoneW*0.46,height:34);sourcePageButton.frame=CGRect(x:right.frame.minX+phoneW*0.46,y:right.frame.maxY+8,width:phoneW*0.54,height:34)
  simulatorTools.frame=leftTools.frame
  hint.frame=CGRect(x:14,y:hh-30,width:cw-28,height:25);hint.numberOfLines=1
  extractionProgress.frame=CGRect(x:max(12,(cw-480)/2),y:96+extra,width:min(480,cw-24),height:76)
  propertyStack.frame=CGRect(x:18,y:16,width:iw-36,height:propertyStack.systemLayoutSizeFitting(CGSize(width:iw-36,height:UIView.layoutFittingCompressedSize.height),withHorizontalFittingPriority:.required,verticalFittingPriority:.fittingSizeLevel).height);inspector.contentSize=CGSize(width:iw,height:propertyStack.frame.maxY+30)
 }
 func showWorkspaceHelp(){showMessage("从这里开始","1. 准备项目\n点击「HTML 模板」新建项目，再把内置指令交给 Codex。已有项目可点击「导入项目」。\n\n2. 找到缺少的资源\n在「选取与编辑」模式点右侧手机。右栏会显示内部图层缩略图，点「查看内部」继续深入；「上一级」返回。也可以搜索本页文字或图片。\n\n3. 补入 iOS\n拖动右栏缩略图到左侧手机，或点击「添加这一层到 iOS」。组合背景与内部内容分开选择。添加后可以撤销。复制的图层保留 HTML 动作、绑定和本地化来源；按钮逻辑在源代码的 actions 中统一维护。\n\n4. 调整外观\n「内部图层」展开父子关系，右键重命名、隐藏或锁定。拖动自动吸附边缘和中心，可在「调整 / 组合」关闭。方向键微调 1 pt，Shift + 方向键 10 pt。\n选左侧图层，在右栏改大小和位置。选「多选」可以逐个点选；「框选」可一次圈选。拖右下角调整大小，「调整 / 组合」提供旋转和组合。\n\n5. 检查与导出\n「更多 → 转换检查」检查页面、资源和覆盖冲突，点问题可定位图层。\n按 P 切换编辑 / 运行（输入文字时不触发）。切到「运行预览」操作两边手机；「两端联动」控制页面与状态同步。完成后点「导出 iOS 工程」，文件保存在桌面「App名-htmlios」文件夹。\n\n6. 崩溃后恢复\n点击「运行 / 重启 iOS」，系统保存布局、构建并安装运行端、启动专用模拟器，最后检查同步。进度会持续显示，不会抹掉模拟器数据。")}
 func showSyncStatus(_ text:String){syncStateLabel.text=text.contains("失败") ? "同步有问题" : text.contains("冲突") ? "iOS 修改优先" : text.hasPrefix("已同步") ? "● 已同步" : "同步中…";syncStateLabel.textColor=UIColor(studioHex:text.contains("失败") || text.contains("冲突") ? "#9E3B2C":"#38664F");if Date()>statusHoldUntil{footer.text="  "+text}}
}
