import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(systemSymbolName: args[1], accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 32, weight: .regular)) else { exit(1) }
let hex = String(args[2].dropFirst()); let value = UInt64(hex, radix: 16) ?? 0x17212B
let offset: UInt64 = hex.count == 8 ? 8 : 0
let color = NSColor(srgbRed: CGFloat((value >> (16 + offset)) & 255) / 255, green: CGFloat((value >> (8 + offset)) & 255) / 255, blue: CGFloat((value >> offset) & 255) / 255, alpha: hex.count == 8 ? CGFloat(value & 255) / 255 : 1)
let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
    source.draw(in: rect.insetBy(dx: 4, dy: 4)); color.setFill(); rect.fill(using: .sourceAtop); return true
}
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
print(png.base64EncodedString())
