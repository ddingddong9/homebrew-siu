import AppKit
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift Scripts/trim-sprite.swift INPUT.png OUTPUT.png\n", stderr)
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let targetURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read image") }
let bitmap = NSBitmapImageRep(cgImage: image)
var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.12 {
        minX = min(minX, x); minY = min(minY, y)
        maxX = max(maxX, x); maxY = max(maxY, y)
    }
}
guard minX <= maxX, minY <= maxY else { fatalError("No visible pixels") }
let padding = 6
let x = max(0, minX - padding), y = max(0, minY - padding)
let rect = CGRect(x: x, y: y,
                  width: min(bitmap.pixelsWide, maxX + padding + 1) - x,
                  height: min(bitmap.pixelsHigh, maxY + padding + 1) - y)
guard let cropped = image.cropping(to: rect),
      let destination = CGImageDestinationCreateWithURL(targetURL as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Cannot crop image")
}
CGImageDestinationAddImage(destination, cropped, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save image") }
print("\(targetURL.lastPathComponent): \(cropped.width)x\(cropped.height)")
