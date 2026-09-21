import UIKit
import CoreText
final class NativeTypography {
 func font(_ n:StudioNode)->UIFont {
  let weight=UIFont.Weight(rawValue:(n.fontWeight-400)/500)
  let familyName=n.fontFamily=="serif" ? "TimesNewRomanPSMT" : n.fontFamily=="monospace" ? "Menlo-Regular" : n.fontFamily=="cursive" ? "SnellRoundhand" : ""
  let f=UIFont(name:n.fontName.isEmpty ? familyName : n.fontName,size:n.fontSize) ?? .systemFont(ofSize:n.fontSize,weight:weight)
  let d=f.fontDescriptor.addingAttributes([UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String):[NSNumber(value:0x77676874):NSNumber(value:Double(n.fontWeight))]])
  var traits=d.symbolicTraits
  if n.italic==true{traits.insert(.traitItalic)}
  if n.fontWeight>=600{traits.insert(.traitBold)}
  return UIFont(descriptor:d.withSymbolicTraits(traits) ?? d,size:n.fontSize)
 }
}
