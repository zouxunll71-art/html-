import UIKit
struct StudioTextSpan:Codable,Equatable {var start:Int;var end:Int;var fontSize:CGFloat?;var fontWeight:CGFloat?;var color:String?;var underline:Bool?;var italic:Bool?}
struct StudioAsset: Codable { var id:String; var name:String; var kind:String; var file:String; var source:String; var sha256:String }
struct StudioProject: Codable {var compileRevision:String?; var importMode:String?;var referenceAssets:[String:String]?;var pageRoles:[String:String]?; var schemaVersion=1; var id:String; var name:String; var sourcePath:String; var package:String; var assets:[StudioAsset]; var pages:[StudioPage]; var pageCandidates:[String]; var updated:Double;var selectionColor:String?;var sharedNavigation:[String:StudioNode]? }
struct StudioPage: Codable { var id=UUID().uuidString; var name:String; var route:String; var width:CGFloat=393; var height:CGFloat=852; var background="#FFFFFF"; var nodes:[StudioNode]=[];var templateRoutes:[String]?;var paintOrderVersion:Int? }
struct StudioGradient:Codable,Equatable {var colors:[String];var locations:[CGFloat]?;var start:[CGFloat]?;var end:[CGFloat]?}
struct StudioShadow:Codable,Equatable {var color:String?;var x:CGFloat?;var y:CGFloat?;var blur:CGFloat?}
struct StudioNode: Codable,Equatable {
 var symbol:String?;var textKey:String?;var placeholderKey:String?;var selected:Bool?
 var parent:String?;var gradient:StudioGradient?;var shadow:StudioShadow?;var contentWidth:CGFloat?;var contentHeight:CGFloat?;var scrollX:CGFloat?;var scrollY:CGFloat?;var clip:Bool?;var scale:CGFloat?
 var fontFamily:String?;var italic:Bool?;var lineHeight:CGFloat?;var letterSpacing:CGFloat?
 var textSpans:[StudioTextSpan]?
 var sharedKey:String?;var groupID="";var id=UUID().uuidString; var name="Layer"; var type="image"; var text=""; var asset=""
 var x:CGFloat=24;var y:CGFloat=100;var width:CGFloat=160;var height:CGFloat=120
 var rotation:CGFloat=0;var opacity:CGFloat=1;var fontSize:CGFloat=16;var fontName="";var fontWeight:CGFloat=400
 var strokeColor="#00000000";var strokeWidth:CGFloat=0;var color="#17212B";var fill="#00000000";var fit="fit";var alignment="left";var anchor="topLeft"
 var isOn=false;var value:CGFloat=0.5;var placeholder="";var options:[String]=[];var locked=false;var hidden=false;var cornerRadius:CGFloat=0;var capPixels:CGFloat=0;var capPoints:CGFloat=13
 var frame:CGRect { get { CGRect(x:x,y:y,width:width,height:height) } set { x=newValue.minX;y=newValue.minY;width=newValue.width;height=newValue.height } }
 enum CodingKeys:String,CodingKey { case symbol,textKey,placeholderKey,selected,parent,gradient,shadow,contentWidth,contentHeight,scrollX,scrollY,clip,scale,fontFamily,italic,lineHeight,letterSpacing,textSpans,sharedKey,groupID,isOn,value,placeholder,options,strokeColor,strokeWidth,id,name,type,text,asset,x,y,width,height,rotation,opacity,fontSize,fontName,fontWeight,color,fill,fit,alignment,anchor,locked,hidden,cornerRadius,capPixels,capPoints }
 init() {}
 init(from decoder:Decoder)throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  symbol=try c.decodeIfPresent(String.self,forKey:.symbol);textKey=try c.decodeIfPresent(String.self,forKey:.textKey);placeholderKey=try c.decodeIfPresent(String.self,forKey:.placeholderKey);selected=try c.decodeIfPresent(Bool.self,forKey:.selected)
  parent=try c.decodeIfPresent(String.self,forKey:.parent);gradient=try c.decodeIfPresent(StudioGradient.self,forKey:.gradient);shadow=try c.decodeIfPresent(StudioShadow.self,forKey:.shadow)
  contentWidth=try c.decodeIfPresent(CGFloat.self,forKey:.contentWidth);contentHeight=try c.decodeIfPresent(CGFloat.self,forKey:.contentHeight);scrollX=try c.decodeIfPresent(CGFloat.self,forKey:.scrollX);scrollY=try c.decodeIfPresent(CGFloat.self,forKey:.scrollY);clip=try c.decodeIfPresent(Bool.self,forKey:.clip);scale=try c.decodeIfPresent(CGFloat.self,forKey:.scale)
  fontFamily=try c.decodeIfPresent(String.self,forKey:.fontFamily);italic=try c.decodeIfPresent(Bool.self,forKey:.italic);lineHeight=try c.decodeIfPresent(CGFloat.self,forKey:.lineHeight);letterSpacing=try c.decodeIfPresent(CGFloat.self,forKey:.letterSpacing)
  textSpans=try c.decodeIfPresent([StudioTextSpan].self,forKey:.textSpans)
  sharedKey=try c.decodeIfPresent(String.self,forKey:.sharedKey)
  groupID=try c.decodeIfPresent(String.self,forKey:.groupID) ?? ""
  id=try c.decodeIfPresent(String.self,forKey:.id) ?? UUID().uuidString
  for k in [CodingKeys.placeholder,.strokeColor,.name,.type,.text,.asset,.fontName,.color,.fill,.fit,.alignment,.anchor] { if let v=try c.decodeIfPresent(String.self,forKey:k) { switch k {case .placeholder:placeholder=v;case .strokeColor:strokeColor=v;case .name:name=v;case .type:type=v;case .text:text=v;case .asset:asset=v;case .fontName:fontName=v;case .color:color=v;case .fill:fill=v;case .fit:fit=v;case .alignment:alignment=v;case .anchor:anchor=v;default:break} } }
  for k in [CodingKeys.value,.strokeWidth,.x,.y,.width,.height,.rotation,.opacity,.fontSize,.fontWeight,.cornerRadius,.capPixels,.capPoints] { if let v=try c.decodeIfPresent(CGFloat.self,forKey:k) { switch k {case .value:value=v;case .strokeWidth:strokeWidth=v;case .x:x=v;case .y:y=v;case .width:width=v;case .height:height=v;case .rotation:rotation=v;case .opacity:opacity=v;case .fontSize:fontSize=v;case .fontWeight:fontWeight=v;case .cornerRadius:cornerRadius=v;case .capPixels:capPixels=v;case .capPoints:capPoints=v;default:break} } }
  isOn=try c.decodeIfPresent(Bool.self,forKey:.isOn) ?? false;options=try c.decodeIfPresent([String].self,forKey:.options) ?? []
  locked=try c.decodeIfPresent(Bool.self,forKey:.locked) ?? false;hidden=try c.decodeIfPresent(Bool.self,forKey:.hidden) ?? false
 }
}
struct AndroidSnapshot:Codable {var route:String;var width:CGFloat;var height:CGFloat;var pixelWidth:CGFloat?;var pixelHeight:CGFloat?;var nodes:[StudioNode];var quality:String;var package:String;var assets:[StudioAsset]?;var unresolved:[String]?;var coverageWarnings:[String]?;var templateRoutes:[String]?;var paintOrderVersion:Int?}
extension UIColor {
 convenience init(studioHex:String) {
  let raw=studioHex.replacingOccurrences(of:"#",with:"");let v=UInt64(raw,radix:16) ?? 0
  if raw.count==8 {self.init(red:CGFloat((v>>24)&255)/255,green:CGFloat((v>>16)&255)/255,blue:CGFloat((v>>8)&255)/255,alpha:CGFloat(v&255)/255)}
  else {self.init(red:CGFloat((v>>16)&255)/255,green:CGFloat((v>>8)&255)/255,blue:CGFloat(v&255)/255,alpha:1)}
 }
}
extension StudioNode {
 var visualBounds:CGRect {
  let center=CGPoint(x:x+width/2,y:y+height/2)
  let rect=CGRect(x:-width/2,y:-height/2,width:width,height:height).applying(CGAffineTransform(rotationAngle:rotation * .pi/180))
  return rect.offsetBy(dx:center.x,dy:center.y)
 }
}
