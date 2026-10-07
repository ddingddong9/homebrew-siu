import AppKit
import CoreImage
import ImageIO
import Vision

// Original pixels only. Crop away other players before Vision instance selection.
guard CommandLine.arguments.count == 4 else { fatalError("Usage: extract-messi.swift idle|shot|tackle|phantom INPUT OUTPUT") }
let kind = CommandLine.arguments[1]
let input = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(input as CFURL,nil) else { fatalError("Missing source") }
let range: ClosedRange<Int>
switch kind { case "idle": range = 0...0; case "shot": range = 0...22; case "tackle": range = 8...27; case "phantom": range = 0...6; default: fatalError("Unknown clip") }
let context = CIContext()
var frames: [NSImage] = []
for index in range {
    guard let original = CGImageSourceCreateImageAtIndex(source,index,nil) else { fatalError("Missing frame") }
    let w = CGFloat(original.width), h = CGFloat(original.height)
    let rect: CGRect
    switch kind {
    case "idle": rect = CGRect(x:45,y:10,width:320,height:650)
    case "shot":
        let center = 0.75 - Double(index)/22*0.09
        rect = CGRect(x:w*(center-0.24),y:h*0.06,width:w*0.40,height:h*0.90)
    case "phantom":
        let center = 0.29 + Double(index)/18*0.25
        rect = CGRect(x:w*(center-0.17),y:0,width:w*0.34,height:h*0.99)
    default: rect = CGRect(x:0,y:0,width:w,height:h)
    }
    guard let crop = original.cropping(to:rect.integral.intersection(CGRect(x:0,y:0,width:w,height:h))) else { fatalError("Bad crop") }
    let ci = CIImage(cgImage:crop)
    let enlarged = ci.transformed(by:CGAffineTransform(scaleX:2,y:2))
    let handler = VNImageRequestHandler(cgImage:context.createCGImage(enlarged,from:enlarged.extent)!)
    guard #available(macOS 14,*) else { fatalError("Extraction requires macOS 14") }
    let request = VNGenerateForegroundInstanceMaskRequest()
    try handler.perform([request])
    guard let result = request.results?.first else { fatalError("No mask") }
    // Prefer the instance whose central torso contains blue kit pixels. For the
    // Argentina portrait use the center instance, excluding the red player.
    let labels = result.instanceMask
    CVPixelBufferLockBaseAddress(labels,.readOnly)
    let bytes = CVPixelBufferGetBaseAddress(labels)!.assumingMemoryBound(to:UInt8.self)
    let lw = CVPixelBufferGetWidth(labels), lh = CVPixelBufferGetHeight(labels), stride = CVPixelBufferGetBytesPerRow(labels)
    let rgb = CGContext(data:nil,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    rgb.draw(crop,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
    let pixels = rgb.data!.assumingMemoryBound(to:UInt8.self)
    var votes: [Int:Int] = [:]
    for y in 0..<crop.height { for x in 0..<crop.width {
        let i = (y*crop.width+x)*4
        let blue = Int(pixels[i+2]), green = Int(pixels[i+1]), red = Int(pixels[i])
        let central = Double(x)/Double(crop.width) > 0.2 && Double(x)/Double(crop.width) < 0.8
        if central && (kind == "idle" || (blue > green*6/5 && blue > red)) {
            let label = Int(bytes[y*lh/crop.height*stride+x*lw/crop.width])
            if label > 0 { votes[label,default:0] += 1 }
        }
    } }
    CVPixelBufferUnlockBaseAddress(labels,.readOnly)
    guard let chosen = votes.max(by:{$0.value < $1.value})?.key else { fatalError("No target instance at \(index)") }
    let buffer = try result.generateScaledMaskForImage(forInstances:IndexSet(integer:chosen),from:handler)
    let raw = CIImage(cvPixelBuffer:buffer)
    let mask = raw.transformed(by:CGAffineTransform(scaleX:ci.extent.width/raw.extent.width,y:ci.extent.height/raw.extent.height))
    let cutout = ci.applyingFilter("CIBlendWithMask",parameters:[kCIInputBackgroundImageKey:CIImage(color:.clear).cropped(to:ci.extent),kCIInputMaskImageKey:mask])
    let cg = context.createCGImage(cutout,from:ci.extent)!
    // Remove disconnected ball / opponent fragments, retaining the largest body.
    let cleaned = CGContext(data:nil,width:crop.width,height:crop.height,bitsPerComponent:8,bytesPerRow:crop.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    cleaned.draw(cg,in:CGRect(x:0,y:0,width:crop.width,height:crop.height))
    let rgba = cleaned.data!.assumingMemoryBound(to:UInt8.self)
    // The football is simulated separately; erase only its known source region
    // in contact frames, without inventing pixels hidden behind it.
    if kind == "phantom" || (kind == "shot" && (11...15).contains(index)) {
        let ballX = kind == "phantom" ? 271-Double(index)*3.5 : 210+Double(index)*6.1
        let ballY = kind == "phantom" ? 207-Double(index)*3.3 : 219
        let radius = kind == "phantom" ? 12.5 : 14.0
        for y in 0..<crop.height { for x in 0..<crop.width {
            if hypot(Double(x)+rect.integral.minX-ballX,Double(y)+rect.integral.minY-ballY) <= radius {
                for c in 0..<4 { rgba[(y*crop.width+x)*4+c] = 0 }
            }
        } }
    }
    var visited = Set<Int>(), best: [Int] = []
    for start in 0..<(crop.width*crop.height) where !visited.contains(start) && rgba[start*4+3] > 30 {
        var component = [start]; visited.insert(start); var cursor = 0
        while cursor < component.count {
            let p = component[cursor]; cursor += 1
            for dy in -1...1 { for dx in -1...1 {
                let x = p%crop.width+dx, y = p/crop.width+dy
                guard x >= 0,x < crop.width,y >= 0,y < crop.height else { continue }
                let n = y*crop.width+x
                if rgba[n*4+3] > 30 && visited.insert(n).inserted { component.append(n) }
            } }
        }
        if component.count > best.count { best = component }
    }
    let retained = Set(best)
    for p in 0..<(crop.width*crop.height) where !retained.contains(p) { for c in 0..<4 { rgba[p*4+c] = 0 } }
    let finalCG = cleaned.makeImage()!
    let bitmap = NSBitmapImageRep(cgImage:finalCG)
    var minX = crop.width, minY = crop.height, maxX = 0, maxY = 0
    for y in 0..<crop.height { for x in 0..<crop.width {
        if bitmap.colorAt(x:x,y:y)!.alphaComponent > 0.2 {
            minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
        }
    } }
    guard maxX > minX, maxY > minY else { fatalError("Empty frame") }
    let body = NSImage(cgImage:finalCG,size:NSSize(width:crop.width,height:crop.height))
    let canvas = NSImage(size:NSSize(width:256,height:256)); canvas.lockFocus()
    // Fixed source scale per clip prevents sliding body from expanding in size.
    let scale: CGFloat = kind == "idle" ? 0.34 : kind == "tackle" ? 0.50 : kind == "shot" ? 0.78 : 0.95
    let sourceRect = NSRect(x:minX,y:crop.height-1-maxY,width:maxX-minX+1,height:maxY-minY+1)
    body.draw(in:NSRect(x:128-sourceRect.width*scale/2,y:8,width:sourceRect.width*scale,height:sourceRect.height*scale),from:sourceRect,operation:.sourceOver,fraction:1)
    canvas.unlockFocus()
    let name = String(format:"messi-%@-%02d.png",kind,index-range.lowerBound+1)
    try NSBitmapImageRep(data:canvas.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name))
    frames.append(canvas)
}
let sheet = NSImage(size:NSSize(width:1024,height:256)); sheet.lockFocus()
NSColor.darkGray.setFill(); NSRect(x:0,y:0,width:1024,height:256).fill()
for tile in 0..<4 { frames[tile*(frames.count-1)/3].draw(in:NSRect(x:tile*256,y:0,width:256,height:256)) }
sheet.unlockFocus()
try NSBitmapImageRep(data:sheet.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/messi-\(kind)-cutouts.png"))
print("\(kind): \(frames.count) original-pixel transparent frames")
