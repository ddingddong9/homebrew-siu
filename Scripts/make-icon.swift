import AppKit
import CoreImage
import Vision

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift Scripts/make-icon.swift INPUT OUTPUT\n", stderr)
    exit(2)
}

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(url: source)
try handler.perform([request])
guard let observation = request.results?.first,
      let original = CIImage(contentsOf: source) else {
    fputs("Could not isolate the foreground person.\n", stderr)
    exit(1)
}

let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances,
                                                            from: handler)
let mask = CIImage(cvPixelBuffer: maskBuffer)
let transparent = CIImage(color: .clear).cropped(to: original.extent)
let cutout = original.applyingFilter("CIBlendWithMask", parameters: [
    kCIInputBackgroundImageKey: transparent,
    kCIInputMaskImageKey: mask
])
let context = CIContext()
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let cgImage = context.createCGImage(cutout, from: original.extent, format: .RGBA8,
                                          colorSpace: colorSpace),
      let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fputs("Could not render transparent PNG.\n", stderr)
    exit(1)
}
try png.write(to: destination, options: .atomic)
