import AppKit
import CoreImage
import ImageIO
import Vision

// Deterministic extraction of user-provided GIFs. No generated poses.
// Crops are tuned to these three clips and exclude other players/TV graphics.
guard CommandLine.arguments.count == 5 else {
    fatalError("Usage: swift Scripts/extract-special-moves.swift celebration|stepover|backheel INPUT.gif OUTPUT_DIR PREVIEW_DIR")
}
let name = CommandLine.arguments[1]
let input = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
let preview = URL(fileURLWithPath: CommandLine.arguments[4], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { fatalError("Cannot read GIF") }
let range: ClosedRange<Int>
let anchors: [(Int, CGRect)]
switch name {
case "celebration":
    range = 4...22
    anchors = [(4, CGRect(x: 55, y: 0, width: 100, height: 142))]
case "stepover":
    range = 0...42
    anchors = [(0, CGRect(x: 145, y: 45, width: 160, height: 245)),
               (18, CGRect(x: 145, y: 45, width: 165, height: 245)),
               (30, CGRect(x: 135, y: 35, width: 165, height: 255)),
               (42, CGRect(x: 105, y: 35, width: 165, height: 255))]
case "backheel":
    range = 13...21
    anchors = [(13, CGRect(x: 180, y: 42, width: 130, height: 145)),
               (19, CGRect(x: 205, y: 30, width: 145, height: 165)),
               (23, CGRect(x: 160, y: 28, width: 150, height: 175)),
               (24, CGRect(x: 200, y: 28, width: 150, height: 175)),
               (27, CGRect(x: 185, y: 35, width: 145, height: 170))]
default: fatalError("Unknown animation")
}
func crop(at index: Int) -> CGRect {
    guard let next = anchors.firstIndex(where: { $0.0 > index }) else { return anchors.last!.1 }
    if next == 0 { return anchors[0].1 }
    let a = anchors[next - 1], b = anchors[next]
    let t = CGFloat(index - a.0) / CGFloat(b.0 - a.0)
    return CGRect(x: a.1.minX + (b.1.minX - a.1.minX) * t,
                  y: a.1.minY + (b.1.minY - a.1.minY) * t,
                  width: a.1.width + (b.1.width - a.1.width) * t,
                  height: a.1.height + (b.1.height - a.1.height) * t).integral
}
let context = CIContext()
var extracted: [NSImage] = []
var delays: [Double] = []
for index in range {
    autoreleasepool {
        guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
            fatalError("Cannot decode frame \(index)")
        }
        let full = CIImage(cgImage: image)
        let enlarged = full.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        guard let enlargedCG = context.createCGImage(enlarged, from: enlarged.extent) else { fatalError("Cannot upscale") }
        let handler = VNImageRequestHandler(cgImage: enlargedCG)
        let maskBuffer: CVPixelBuffer
        var pose: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]?
        do {
            if #available(macOS 14.0, *) {
                let request = VNGenerateForegroundInstanceMaskRequest()
                try handler.perform([request])
                guard let observation = request.results?.first else { fatalError("No instance mask") }
                // Select the instance containing the red shirt, not all foreground people.
                let labels = observation.instanceMask
                CVPixelBufferLockBaseAddress(labels, .readOnly)
                let labelData = CVPixelBufferGetBaseAddress(labels)!.assumingMemoryBound(to: UInt8.self)
                let labelWidth = CVPixelBufferGetWidth(labels), labelHeight = CVPixelBufferGetHeight(labels)
                let labelStride = CVPixelBufferGetBytesPerRow(labels)
                let pixels = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                       bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                pixels.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let rgba = pixels.data!.assumingMemoryBound(to: UInt8.self)
                let target = crop(at: index).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
                var votes: [Int: Int] = [:]
                for y in Int(target.minY)..<Int(target.maxY) {
                    for x in Int(target.minX)..<Int(target.maxX) {
                        let p = (y * image.width + x) * 4
                        let r = Int(rgba[p]), g = Int(rgba[p+1]), b = Int(rgba[p+2])
                        if r > 80, r > g * 3 / 2, r > b * 4 / 3 {
                            let label = Int(labelData[(y * labelHeight / image.height) * labelStride + x * labelWidth / image.width])
                            if label > 0 { votes[label, default: 0] += 1 }
                        }
                    }
                }
                CVPixelBufferUnlockBaseAddress(labels, .readOnly)
                let chosen = votes.max { $0.value < $1.value }?.key
                maskBuffer = try observation.generateScaledMaskForImage(forInstances: chosen.map { IndexSet(integer: $0) } ?? observation.allInstances, from: handler)
                if name != "celebration" {
                    let bodyRequest = VNDetectHumanBodyPoseRequest()
                    try handler.perform([bodyRequest])
                    let targetCenter = CGPoint(x: target.midX / CGFloat(image.width), y: 1 - target.midY / CGFloat(image.height))
                    pose = bodyRequest.results?.compactMap { try? $0.recognizedPoints(.all) }.min { a, b in
                        func distance(_ p: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Double {
                            guard let root = p[.root], root.confidence > 0.2 else { return .infinity }
                            return hypot(root.location.x - targetCenter.x, root.location.y - targetCenter.y)
                        }
                        return distance(a) < distance(b)
                    }
                }
            } else {
                let request = VNGeneratePersonSegmentationRequest()
                request.qualityLevel = .accurate
                request.outputPixelFormat = kCVPixelFormatType_OneComponent8
                try handler.perform([request])
                guard let buffer = request.results?.first?.pixelBuffer else { fatalError("No person mask") }
                maskBuffer = buffer
            }
        } catch { fatalError("Segmentation failed: \(error)") }
        let foreground = full
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)
        let mask = rawMask.transformed(by: CGAffineTransform(scaleX: foreground.extent.width / rawMask.extent.width,
                                                            y: foreground.extent.height / rawMask.extent.height))
        let cutout = foreground.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: foreground.extent),
            kCIInputMaskImageKey: mask
        ])
        let rect = crop(at: index).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let ciRect = CGRect(x: rect.minX, y: CGFloat(image.height) - rect.maxY, width: rect.width, height: rect.height)
        guard let result = context.createCGImage(cutout, from: ciRect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!) else { fatalError("Cannot render") }
        // Explicit RGB context avoids indexed GIF color-space ambiguity.
        let rgb = CGContext(data: nil, width: result.width, height: result.height, bitsPerComponent: 8,
                            bytesPerRow: result.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rgb.draw(result, in: CGRect(x: 0, y: 0, width: result.width, height: result.height))
        // Remove the blue defender when the source players overlap. Keep red kit,
        // socks, white shorts and skin; no green-screen replacement is applied.
        let rgba = rgb.data!.assumingMemoryBound(to: UInt8.self)
        // Skeleton-guided isolation removes connected opponent fragments where kits overlap.
        if let pose {
            func location(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let p = pose[joint], p.confidence > 0.15 else { return nil }
                return CGPoint(x: p.location.x * CGFloat(image.width) - rect.minX,
                               y: (1 - p.location.y) * CGFloat(image.height) - rect.minY)
            }
            let torsoPairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, CGFloat)] = [
                (.neck, .root, 23), (.leftShoulder, .leftHip, 15), (.rightShoulder, .rightHip, 15),
                (.leftShoulder, .rightShoulder, 12), (.leftHip, .rightHip, 13), (.neck, .nose, 13),
                (.leftShoulder, .leftElbow, 9), (.leftElbow, .leftWrist, 8),
                (.rightShoulder, .rightElbow, 9), (.rightElbow, .rightWrist, 8),
                (.leftHip, .leftKnee, 12), (.leftKnee, .leftAnkle, 10),
                (.rightHip, .rightKnee, 12), (.rightKnee, .rightAnkle, 10)
            ]
            let segments = torsoPairs.compactMap { a, b, radius -> (CGPoint, CGPoint, CGFloat)? in
                guard let start = location(a), let end = location(b) else { return nil }
                return (start, end, radius)
            }
            var headZone: (CGPoint, CGFloat)?
            // Back-facing dark hair can be missed by the foreground model. Restore
            // the small head region from the original pixels, never synthesize it.
            if let neck = location(.neck), let root = location(.root) {
                let head = location(.nose) ?? CGPoint(x: neck.x + (neck.x-root.x)*0.28, y: neck.y + (neck.y-root.y)*0.28)
                let radius: CGFloat = name == "stepover" ? 9 : 8
                headZone = (head, radius)
                let sourceRGB = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width*4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                sourceRGB.draw(image, in: CGRect(x: 0,y: 0,width:image.width,height:image.height))
                let sourceBytes = sourceRGB.data!.assumingMemoryBound(to: UInt8.self)
                for y in 0..<result.height { for x in 0..<result.width {
                    if pow((CGFloat(x)-head.x)/radius,2) + pow((CGFloat(y)-head.y)/(radius*1.25),2) < 1 {
                        let sx = x+Int(rect.minX), sy = y+Int(rect.minY)
                        let p = (y*result.width+x)*4, original = (sy*image.width+sx)*4
                        for channel in 0..<4 { rgba[p+channel] = sourceBytes[original+channel] }
                    }
                } }
            }
            if segments.count >= 8 {
                for y in 0..<result.height { for x in 0..<result.width {
                    let p = CGPoint(x: x, y: y)
                    let insideHead = headZone.map { head, radius in
                        pow((p.x-head.x)/radius,2) + pow((p.y-head.y)/(radius*1.25),2) < 1
                    } ?? false
                    let inside = insideHead || segments.contains { a, b, radius in
                        let dx = b.x-a.x, dy = b.y-a.y
                        let t = min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy) / max(1,dx*dx+dy*dy)))
                        return hypot(p.x-(a.x+t*dx), p.y-(a.y+t*dy)) <= radius
                    }
                    if !inside { let i = (y*result.width+x)*4; rgba[i]=0; rgba[i+1]=0; rgba[i+2]=0; rgba[i+3]=0 }
                } }
            }
        }
        if name == "backheel" {
            for pixel in 0..<(result.width * result.height) {
                let p = pixel * 4
                if Int(rgba[p+2]) > Int(rgba[p]) * 5 / 4 && Int(rgba[p+2]) > Int(rgba[p+1]) * 108 / 100 {
                    rgba[p] = 0; rgba[p+1] = 0; rgba[p+2] = 0; rgba[p+3] = 0
                }
            }
        }
        // Discard detached opponents / ball fragments, retaining the largest connected body.
        let width = result.width, height = result.height
        var visited = [Bool](repeating: false, count: width * height)
        var best: [Int] = []
        for start in 0..<(width * height) where !visited[start] && rgba[start * 4 + 3] > 30 {
            var component = [start]; visited[start] = true
            var cursor = 0
            while cursor < component.count {
                let p = component[cursor]; cursor += 1
                let x = p % width, y = p / width
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let n = ny * width + nx
                    if !visited[n] && rgba[n * 4 + 3] > 30 { visited[n] = true; component.append(n) }
                } }
            }
            if component.count > best.count { best = component }
        }
        let retained = Set(best)
        for p in 0..<(width * height) where !retained.contains(p) {
            rgba[p*4] = 0; rgba[p*4+1] = 0; rgba[p*4+2] = 0; rgba[p*4+3] = 0
        }
        let bitmap = NSBitmapImageRep(cgImage: rgb.makeImage()!)
        // Common fixed canvas preserves the original jumping / footwork trajectory.
        let canvas = NSImage(size: NSSize(width: 192, height: 256))
        canvas.lockFocus()
        let frame = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        frame.addRepresentation(bitmap)
        let scale: CGFloat = name == "celebration" ? 1.45 : (name == "stepover" ? 0.92 : 1.35)
        let drawWidth = frame.size.width * scale, drawHeight = frame.size.height * scale
        var drawX = (192 - drawWidth) / 2, drawY: CGFloat = 8
        if name != "celebration", !best.isEmpty {
            let minX = best.map { $0 % width }.min()!, maxX = best.map { $0 % width }.max()!
            let maxY = best.map { $0 / width }.max()!
            drawX = 96 - CGFloat(minX + maxX) / 2 * scale
            drawY -= CGFloat(height - 1 - maxY) * scale
        }
        frame.draw(in: NSRect(x: drawX, y: drawY, width: drawWidth, height: drawHeight))
        canvas.unlockFocus()
        let final = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
        let filename = String(format: "%@-%02d.png", name, index - range.lowerBound + 1)
        do { try final.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename)) }
        catch { fatalError("Cannot save: \(error)") }
        extracted.append(canvas)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any]
        let gif = properties?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        delays.append(gif?[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? 0.1)
        print("\(name) \(index) → \(filename)")
    }
}
let metadata: [String: Any] = ["name": name, "sourceFrames": Array(range), "sourceDelays": delays,
                              "width": 192, "height": 256]
try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]).write(to: preview.appendingPathComponent("\(name)-extraction.json"))
let sheet = NSImage(size: NSSize(width: 960, height: 768))
sheet.lockFocus()
NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.17, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 960, height: 768).fill()
for tile in 0..<15 {
    let index = tile * (extracted.count - 1) / 14
    let x = CGFloat(tile % 5) * 192, y = CGFloat(2 - tile / 5) * 256
    extracted[index].draw(in: NSRect(x: x, y: y + 20, width: 172, height: 229))
    NSString(string: "\(name) \(index + 1)").draw(at: NSPoint(x: x + 6, y: y + 2), withAttributes: [.foregroundColor: NSColor.white])
}
sheet.unlockFocus()
try NSBitmapImageRep(data: sheet.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: preview.appendingPathComponent("\(name)-cutout-sheet.png"))
// GIF previews use binary alpha; the game keeps the smoother RGBA PNG frames.
let playback: Double = name == "celebration" ? 2.1 : (name == "stepover" ? 1.0 : 0.65)
guard let animation = CGImageDestinationCreateWithURL(preview.appendingPathComponent("\(name).gif") as CFURL,
                                                     "com.compuserve.gif" as CFString, extracted.count, nil) else { fatalError("Cannot create GIF") }
CGImageDestinationSetProperties(animation, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in extracted {
    let image = NSBitmapImageRep(data: frame.tiffRepresentation!)!.cgImage!
    CGImageDestinationAddImage(animation, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: playback / Double(extracted.count)]] as CFDictionary)
}
guard CGImageDestinationFinalize(animation) else { fatalError("Cannot write GIF") }
