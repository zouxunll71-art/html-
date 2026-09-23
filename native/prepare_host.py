"""Reuse every original editor operation in a separately built client target."""
import shutil, subprocess, os, re
from editor_sync import patch as patch_editor_sync
from clipping_editor import patch_order,patch_controller,patch_surface
import text_color_editor
from pathlib import Path
from environment import engine_root,build_env
client = Path(__file__).resolve().parents[1]
original = engine_root()
target = client/'NativeHost'
for folder in ('Studio','Shared'):
    shutil.copytree(original/folder,target/folder,dirs_exist_ok=True)
studio = target/'Studio'
(studio/'App.swift').write_text((client/'native/Host.swift').read_text())
(studio/'ClientLayout.swift').write_text((client/'native/ClientLayout.swift').read_text())
p=studio/'StudioController.swift'
s=p.read_text().replace(' let inspectorTabs=', ' var clientEmbedded=false\n var clientSyncChanged:((String)->Void)?\n var clientModeChanged:((Bool)->Void)?\n var clientShowInspector:(()->Void)?\n var clientProjectChanged:((String)->Void)?\n var clientLeftContainer:UIView?\n var clientRightContainer:UIView?\n let clientEditingScroll=UIScrollView()\n let clientToolsScroll=UIScrollView()\n let clientPhoneScroll=ClientCanvasScrollView()\n var clientZoom:CGFloat=0.8\n var clientFit=true\n let inspectorTabs=',1)
s=s.replace('running=mode.selectedSegmentIndex==1;', 'running=mode.selectedSegmentIndex==1;clientModeChanged?(running);',1)
s=s.replace('input:"p",modifierFlags:[]','input:"w",modifierFlags:.command').replace('按 P','按 Command+W')
s=s.replace('func loadProjects(){', 'func loadProjects(){if clientEmbedded{return};',1)
s=s.replace('func useProject(_ p:StudioProject){','func useProject(_ p:StudioProject){\n  clientProjectChanged?(p.id)',1)
s=s.replace('let encoded=Bridge.shared.token.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? "";web.load(URLRequest(url:URL(string:Bridge.shared.base+"/web?token="+encoded)!))','web.load(URLRequest(url:URL(string:"http://127.0.0.1:18777/studio/web")!))')
s=s.replace('n.id=UUID().uuidString;project!.pages[pageIndex].nodes.append(n)', 'n.id=UUID().uuidString;n.layerOrder=(page!.nodes.enumerated().map{$0.element.layerOrder ?? Double($0.offset)}.max() ?? -1)+1;project!.pages[pageIndex].nodes.append(n)',1)
p.write_text(text_color_editor.controller(patch_controller(patch_editor_sync(s))))
for name in ('EditorRebase.swift','EditorSync.swift','ClippingInspector.swift','ClippingGeometry.swift','TextColorEditor.swift'):
    shutil.copy2(client/'native'/name,studio/name)
p=studio/'SourceResources.swift';p.write_text(text_color_editor.source(p.read_text()))
p=studio/'LayerThumbnail.swift';p.write_text(text_color_editor.layer(p.read_text()))
p=studio/'LayerReordering.swift';p.write_text(patch_order(p.read_text()))
p=studio/'DeviceSurface.swift';p.write_text(patch_surface(p.read_text()))
p=studio/'WorkspaceDesign.swift';s=p.read_text().replace('func layoutWorkspaceDesign(){','func layoutWorkspaceDesign(){\n  if clientEmbedded {layoutClientWorkspace();return}',1);p.write_text(s)
p=studio/'WorkspaceDesign.swift';s=p.read_text().replace('syncStateLabel.textColor=UIColor(studioHex:text.contains', 'clientSyncChanged?(syncStateLabel.text ?? "同步中…");syncStateLabel.textColor=UIColor(studioHex:text.contains');p.write_text(s)
p=studio/'SourceResources.swift';s=p.read_text().replace('func showInspectorMode(){','func showInspectorMode(){clientShowInspector?();',1);p.write_text(s)
p=studio/'GroupSelection.swift';s=p.read_text().replace('func chooseLayer(_ id:String?){','func chooseLayer(_ id:String?){\n  if id != nil {clientShowInspector?()}',1);p.write_text(s)
# Use the client lossless framebuffer stream; the original bridge is unchanged.
p=studio/'IOSFrames.swift';s=p.read_text().replace('Bridge.shared.base+endpoint','(endpoint=="/ios-stream" ? "http://127.0.0.1:18777/api/ios-stream" : Bridge.shared.base+endpoint)');p.write_text(s)
# Align the live screen and mask to display pixels before one final downsample.
p=studio/'DeviceSurface.swift';s=p.read_text().replace('imageView.contentMode = .scaleToFill;', 'imageView.contentMode = .scaleToFill;imageView.layer.minificationFilter = .trilinear;')
s=s.replace('return CGRect(x:27*s,y:18*s,width:402*s,height:874*s)', 'let pixels=window?.screen.scale ?? traitCollection.displayScale;func snap(_ n:CGFloat)->CGFloat{(n*pixels).rounded()/pixels};return CGRect(x:snap(27*s),y:snap(18*s),width:snap(402*s),height:snap(874*s))')
p.write_text(s)
# Keep editor buttons compatible with their original configurations at native Mac scale.
for file in studio.glob('*.swift'):
    if file.name=='App.swift': continue
    source=file.read_text().replace('UIButton(type:.system)','ClientMobileControls.button()')
    source=re.sub(r'\.systemFont\(ofSize:(9|10|11)(?=[,)])', '.systemFont(ofSize:12', source)
    source=source.replace('label(title,11)', 'label(title,12)')
    file.write_text(source)
env=dict(build_env(),STUDIO_BUNDLE_ID='local.htmlnative.codex-native-client')
subprocess.run(['/usr/bin/python3',str(original/'scripts/make_project.py'),str(target),'HTMLCodexNative','Studio','Shared'],env=env,check=True)
project=target/'HTMLCodexNative.xcodeproj/project.pbxproj'
project.write_text(project.read_text().replace('TARGETED_DEVICE_FAMILY = "1,2";', 'TARGETED_DEVICE_FAMILY = "1,2,6";'))
# Preserve the mobile control appearance in preview renderers under the Mac idiom.
for name in ('NativeControlHost.swift','NativeSceneController.swift'):
    file=target/'Shared'/name
    source=file.read_text().replace('UIButton(type:.system)', 'ClientMobileControls.button()').replace('UISlider()', 'ClientMobileControls.slider()')
    file.write_text(source)
helper=target/'Shared/ClientMobileControls.swift'
helper.write_text("import UIKit\nenum ClientMobileControls {\n static func button()->UIButton {let b=UIButton(type:.system);b.preferredBehavioralStyle = .pad;return b}\n static func slider()->UISlider {let s=UISlider();s.preferredBehavioralStyle = .pad;return s}\n}\n")
# The project generator uses a folder group, so run once more after adding the helper.
subprocess.run(['/usr/bin/python3',str(original/'scripts/make_project.py'),str(target),'HTMLCodexNative','Studio','Shared'],env=env,check=True)
project.write_text(project.read_text().replace('TARGETED_DEVICE_FAMILY = "1,2";', 'TARGETED_DEVICE_FAMILY = "1,2,6";'))
print(target)
