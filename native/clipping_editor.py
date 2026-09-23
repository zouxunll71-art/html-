"""Maintained generated-client integration for visible clipping and safe ordering."""
def replace(source,old,new):
 if old not in source:raise RuntimeError('Clipping integration anchor missing: '+old[:80])
 return source.replace(old,new,1)
def patch_order(s):
 start=s.index('  let destinationParent=')
 end=s.index('  project!.pages[pageIndex].nodes=',start)
 return s[:start]+'''  // Sorting never changes structural ownership. Reparenting is explicit.
  checkpoint();let moved=rows.remove(at:source);rows.insert(moved,at:destination)
'''+s[end:]
def patch_controller(s):
 return replace(s,'   add(button("查看内部图层 / 缩略图",','   addClippingInspector(n)\n   add(button("查看内部图层 / 缩略图",')
def patch_surface(s):
 s=replace(s,' let guides=CAShapeLayer()',' let cropGuides=CAShapeLayer()\n let guides=CAShapeLayer()')
 s=replace(s,'  guides.strokeColor=', '  cropGuides.fillColor=UIColor.clear.cgColor;cropGuides.strokeColor=UIColor.systemOrange.cgColor;cropGuides.lineWidth=2;cropGuides.lineDashPattern=[6,4];overlay.layer.addSublayer(cropGuides)\n  guides.strokeColor=')
 s=replace(s,'  if operate {selection.isHidden=', '  cropGuides.path=nil\n  if operate {selection.isHidden=')
 s=replace(s,'  let clip=clippingRect(for:n,map:map)', '''  let cropPath=UIBezierPath()
  var ancestor=n.parent,seen=Set<String>()
  while let id=ancestor,seen.insert(id).inserted,let parent=map[id]{
   if parent.clipsContent {
    let transform=parent.selectionTransform(in:map)
    let r=parent.frame
    let points=[CGPoint(x:r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.maxX,y:r.maxY),CGPoint(x:r.minX,y:r.maxY)].map{$0.applying(transform)}
    for (i,p) in points.enumerated(){let q=CGPoint(x:p.x/logicalSize.width*screenRect.width,y:p.y/logicalSize.height*screenRect.height);if i==0{cropPath.move(to:q)}else{cropPath.addLine(to:q)}}
    cropPath.close()
   }
   ancestor=parent.parent
  }
  cropGuides.frame=overlay.bounds;cropGuides.path=cropPath.cgPath
  let clip=clippingRect(for:n,map:map)''')
 return s
