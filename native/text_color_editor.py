from clipping_editor import replace
def controller(s):
 s=replace(s,'   if n.hasEditableText {','   if n.hasEditableText {\n    addTextColorPanel(n)')
 s=replace(s,'addField("组件颜色","color",n.color)','addField(n.hasEditableText ? "文案颜色 #RRGGBBAA" : "组件颜色","color",n.color)')
 return s.replace('addField("颜色 #RRGGBB","color",n.color)','addField("文案颜色 #RRGGBBAA","color",n.color)')
def source(s):
 s=replace(s,'   UIColor(studioHex:"#F1F4F8").setFill();context.fill(CGRect(x:0,y:0,width:72,height:60));UIColor(studioHex:"#E2E7EF").setFill()', '   let colors=ThumbnailContrast.colors(n);colors.0.setFill();context.fill(CGRect(x:0,y:0,width:72,height:60));colors.1.setFill()')
 s=replace(s,'   let scale=min(64/v.bounds.width', '   ThumbnailContrast.layout(v)\n   let scale=min(64/v.bounds.width')
 return s
def layer(s):
 s=replace(s,'   UIColor(studioHex:"#F2F4F7").setFill();context.fill(bounds)','   let colors=ThumbnailContrast.colors(n);colors.0.setFill();context.fill(bounds)')
 s=replace(s,'UIColor(studioHex:"#E3E7ED").setFill();for y','colors.1.setFill();for y')
 s=replace(s,'n.type=="text" || n.type=="button"','n.type=="text" || n.type=="button" || n.type=="nativeButton"')
 s=replace(s,'label.layer.render(in:cg)','ThumbnailContrast.layout(label);label.layer.render(in:cg)')
 return s
