import AppKit
import CoreImage
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift Scripts/extract-kick.swift INPUT_DIR OUTPUT_DIR\n", stderr)
    exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("kick-") && $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
let context = CIContext()

for file in files {
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "siu.extract", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot load \(file.path)"])
    }

    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])
    guard let observation = request.results?.first else {
        throw NSError(domain: "siu.extract", code: 2, userInfo: [NSLocalizedDescriptionKey: "No person mask for \(file.path)"])
    }

    let sourceImage = CIImage(cgImage: image)
    let rawMask = CIImage(cvPixelBuffer: observation.pixelBuffer)
    let mask = rawMask.transformed(by: CGAffineTransform(
        scaleX: sourceImage.extent.width / rawMask.extent.width,
        y: sourceImage.extent.height / rawMask.extent.height
    ))
    let cutout = sourceImage.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: sourceImage.extent),
        kCIInputMaskImageKey: mask
    ])
    guard let result = context.createCGImage(cutout, from: sourceImage.extent),
          let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent(file.lastPathComponent) as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "siu.extract", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot render \(file.path)"])
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "siu.extract", code: 4, userInfo: [NSLocalizedDescriptionKey: "Cannot write \(file.path)"])
    }
    print(file.lastPathComponent)
}
