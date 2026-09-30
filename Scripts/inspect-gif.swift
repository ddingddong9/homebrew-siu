import AppKit
import ImageIO

guard (3...4).contains(CommandLine.arguments.count),
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil) else {
    fatalError("Usage: swift Scripts/inspect-gif.swift INPUT.gif OUTPUT.png")
}
let count = CGImageSourceGetCount(source)
if CommandLine.arguments.count == 4, let index = Int(CommandLine.arguments[3]),
   let frame = CGImageSourceCreateImageAtIndex(source, index, nil) {
    try NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    exit(0)
}
let sheet = NSImage(size: NSSize(width: 1000, height: 720))
sheet.lockFocus()
NSColor.darkGray.setFill()
NSRect(x: 0, y: 0, width: 1000, height: 720).fill()
for tile in 0..<20 {
    let index = min(count - 1, tile * (count - 1) / 19)
    guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
    let x = CGFloat(tile % 5) * 200, y = CGFloat(3 - tile / 5) * 180
    let image = NSImage(cgImage: frame, size: .zero)
    image.draw(in: NSRect(x: x, y: y + 24, width: 200, height: 145))
    NSString(string: "frame \(index)").draw(at: NSPoint(x: x + 8, y: y + 4), withAttributes: [.foregroundColor: NSColor.white])
}
sheet.unlockFocus()
let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
