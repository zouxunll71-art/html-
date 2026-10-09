import UIKit
import CoreText
final class NativeTypography {
 private let cache:NSCache<NSString,UIFont> = {let cache=NSCache<NSString,UIFont>();cache.countLimit=256;return cache}()
 func invalidate(){cache.removeAllObjects()}
 func font(_ n:StudioNode)->UIFont {
  let key="\(n.fontName)|\(n.fontFamily ?? "")|\(n.fontSize)|\(n.fontWeight)|\(n.italic == true)" as NSString
  if let cached=cache.object(forKey:key){return cached}
  let weight=UIFont.Weight(rawValue:(n.fontWeight-400)/500)
  let familyName=n.fontFamily=="serif" ? "TimesNewRomanPSMT" : n.fontFamily=="monospace" ? "Menlo-Regular" : n.fontFamily=="cursive" ? "SnellRoundhand" : ""
  let f=UIFont(name:n.fontName.isEmpty ? familyName : n.fontName,size:n.fontSize) ?? .systemFont(ofSize:n.fontSize,weight:weight)
  let d=f.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):[NSNumber(value:0x77676874):NSNumber(value:Double(n.fontWeight))]])
  var traits=d.symbolicTraits
  if n.italic==true{traits.insert(.traitItalic)}
  if n.fontWeight>=600{traits.insert(.traitBold)}
  let font=UIFont(descriptor:d.withSymbolicTraits(traits) ?? d,size:n.fontSize);cache.setObject(font,forKey:key);return font
 }
}
