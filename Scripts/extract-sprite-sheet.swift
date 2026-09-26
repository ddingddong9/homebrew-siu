import AppKit
import CoreImage
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift Scripts/extract-sprite-sheet.swift INPUT_SHEET OUTPUT_DIR PREFIX\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let prefix = CommandLine.arguments[3]
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot load sprite sheet")
}

let renderer = CIContext()
let cellWidth = sheet.width / 4
// Sliding poses are much wider than standing poses and cross equal-sized cells.
let customRanges: [Range<Int>]?
switch prefix {
case "tackle": customRanges = [0..<450, 450..<995, 995..<1625, 1625..<sheet.width]
case "tackle-front": customRanges = [0..<525, 525..<1040, 1040..<1580, 1580..<sheet.width]
case "tackle-back": customRanges = [0..<480, 480..<940, 940..<1615, 1615..<sheet.width]
default: customRanges = nil
}
for index in 0..<4 {
    let xRange = customRanges?[index] ??
        (index * cellWidth)..<(index == 3 ? sheet.width : (index + 1) * cellWidth)
    let crop = CGRect(x: xRange.lowerBound, y: 0,
                      width: xRange.count,
                      height: sheet.height)
    guard let cell = sheet.cropping(to: crop) else { fatalError("Cannot crop cell \(index)") }
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    try VNImageRequestHandler(cgImage: cell).perform([request])
    guard let observation = request.results?.first else { fatalError("No person mask for cell \(index)") }
    let picture = CIImage(cgImage: cell)
    let rawMask = CIImage(cvPixelBuffer: observation.pixelBuffer)
    let mask = rawMask.transformed(by: CGAffineTransform(
        scaleX: picture.extent.width / rawMask.extent.width,
        y: picture.extent.height / rawMask.extent.height
    ))
    let cutout = picture.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: picture.extent),
        kCIInputMaskImageKey: mask
    ])
    guard let rendered = renderer.createCGImage(cutout, from: picture.extent) else {
        fatalError("Cannot render cell \(index)")
    }
    let filename = "\(prefix)-\(String(format: "%02d", index + 1)).png"
    let destinationURL = outputURL.appendingPathComponent(filename)
    guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot write \(filename)")
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot finish \(filename)") }
    print(destinationURL.path)
}
