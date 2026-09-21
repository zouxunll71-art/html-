import UIKit

extension StudioController {
 func layoutClientWorkspace() {
  let w=view.bounds.width,h=view.bounds.height
  let sw=max(220,clientLeftContainer?.bounds.width ?? 220),sh=clientLeftContainer?.bounds.height ?? h
  let iw=max(280,clientRightContainer?.bounds.width ?? 320),ih=clientRightContainer?.bounds.height ?? h
  // All project and editing actions live in the collapsible left tools pane.
  clientToolsScroll.frame=CGRect(x:0,y:0,width:sw,height:sh)
  toolbar.frame=CGRect(x:0,y:0,width:sw,height:260)
  titleLabel.frame=CGRect(x:14,y:14,width:sw-28,height:24);titleLabel.font = .systemFont(ofSize:16,weight:.semibold)
  projectButton.frame=CGRect(x:14,y:42,width:sw-28,height:30)
  helpButton.isHidden=false;buttons[0].isHidden=false;buttons[1].isHidden=false
  let half=(sw-34)/2
  for (i,button) in [buttons[0],buttons[1],buttons[5],moreProject,helpButton].enumerated(){
   button.frame=CGRect(x:14+CGFloat(i%2)*(half+6),y:84+CGFloat(i/2)*42,width:half,height:34)
  }
  buttons[6].frame=CGRect(x:14,y:214,width:sw-28,height:36)
  mode.frame=CGRect(x:14,y:272,width:sw-28,height:32)
  copyButton.frame=CGRect(x:14,y:316,width:half,height:32)
  syncStateLabel.frame=CGRect(x:20+half,y:316,width:half,height:32)
  repairSyncButton.frame=CGRect(x:14,y:358,width:sw-28,height:34)
  runIOSButton.frame=CGRect(x:14,y:400,width:sw-28,height:34)
  editingTools.frame=CGRect(x:14,y:452,width:sw-28,height:234)
  clientToolsScroll.contentSize=CGSize(width:sw,height:706)
  sidebar.frame=CGRect(x:0,y:0,width:sw,height:sh)
  segments.frame=CGRect(x:10,y:14,width:sw-20,height:32);search.frame=CGRect(x:3,y:53,width:sw-6,height:42)
  let ch=max(130,(sh-200)*0.48)
  catalog.frame=CGRect(x:6,y:101,width:sw-12,height:ch);sidebar.viewWithTag(98)?.frame=CGRect(x:12,y:110+ch,width:sw-24,height:32)
  sidebar.viewWithTag(99)?.frame=CGRect(x:15,y:157+ch,width:sw-30,height:22);layers.frame=CGRect(x:6,y:184+ch,width:sw-12,height:max(40,sh-190-ch))
  inspectorTabs.frame=CGRect(x:10,y:14,width:iw-20,height:32)
  inspector.frame=CGRect(x:0,y:55,width:iw,height:max(100,ih-55));sourceBrowser.frame=inspector.frame;iosBrowser.frame=inspector.frame
  propertyStack.frame=CGRect(x:16,y:16,width:iw-32,height:propertyStack.systemLayoutSizeFitting(CGSize(width:iw-32,height:UIView.layoutFittingCompressedSize.height),withHorizontalFittingPriority:.required,verticalFittingPriority:.fittingSizeLevel).height)
  inspector.contentSize=CGSize(width:iw,height:propertyStack.frame.maxY+24)
  workspace.frame=CGRect(x:0,y:0,width:w,height:max(100,h-24));footer.frame=CGRect(x:12,y:h-24,width:w-24,height:23)
  let cw=workspace.bounds.width,hh=workspace.bounds.height
  clientPhoneScroll.frame=CGRect(x:0,y:8,width:cw,height:max(100,hh-36))
  // Fit the entire devices, labels and bottom controls inside the viewport.
  let fittedScale=max(0.01,min((clientPhoneScroll.bounds.height-64)/910,(cw-44)/912))
  let scale=clientFit ? fittedScale:clientZoom
  let pixels=view.window?.screen.scale ?? traitCollection.displayScale
  func snap(_ n:CGFloat)->CGFloat{floor(n*pixels)/pixels}
  let pw=snap(456*scale),ph=snap(910*scale),gap:CGFloat=16,contentW=max(cw,pw*2+gap+28),start=snap((contentW-pw*2-gap)/2)
  clientPhoneScroll.contentSize=CGSize(width:contentW,height:ph+64)
  clientPhoneScroll.isScrollEnabled = !clientFit
  clientPhoneScroll.showsVerticalScrollIndicator = !clientFit
  clientPhoneScroll.showsHorizontalScrollIndicator = !clientFit
  if clientFit {clientPhoneScroll.setContentOffset(.zero,animated:false)}
  leftTitle.frame=CGRect(x:start,y:0,width:pw,height:22);rightTitle.frame=CGRect(x:start+pw+gap,y:0,width:pw,height:22)
  leftTitle.font = .systemFont(ofSize:12,weight:.medium);rightTitle.font = .systemFont(ofSize:12,weight:.medium)
  closeWebButton.frame=CGRect(x:start+pw-80,y:0,width:80,height:22);if !closeWebButton.isHidden{leftTitle.frame.size.width=max(0,pw-82)}
  left.frame=CGRect(x:start,y:26,width:pw,height:ph);right.frame=CGRect(x:start+pw+gap,y:26,width:pw,height:ph);web.frame=right.bounds
  leftTools.frame=CGRect(x:start,y:left.frame.maxY+5,width:pw,height:30);simulatorTools.frame=leftTools.frame
  androidBack.frame=CGRect(x:right.frame.minX,y:right.frame.maxY+5,width:pw*0.4,height:30);sourcePageButton.frame=CGRect(x:right.frame.minX+pw*0.4,y:right.frame.maxY+5,width:pw*0.6,height:30)
  hint.frame=CGRect(x:12,y:hh-25,width:cw-24,height:22);hint.font = .systemFont(ofSize:10);hint.numberOfLines=1
  extractionProgress.frame=CGRect(x:max(12,(cw-420)/2),y:36,width:min(420,cw-24),height:70);syncLabel.isHidden=true
 }
}
