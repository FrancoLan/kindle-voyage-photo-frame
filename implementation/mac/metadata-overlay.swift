import AppKit
import CoreImage
import Foundation
import ImageIO
import Vision

private let shadowLiftAnchors: [(Int, Int)] = [
    (0, 0), (8, 20), (24, 37), (48, 66), (80, 103),
    (128, 151), (180, 193), (220, 226), (255, 255),
]

private func shadowLiftValue(_ input: Int) -> Int {
    for index in 1..<shadowLiftAnchors.count {
        let (x1, y1) = shadowLiftAnchors[index]
        if input <= x1 {
            let (x0, y0) = shadowLiftAnchors[index - 1]
            return Int((Double(y0) + Double(y1 - y0) * Double(input - x0) / Double(x1 - x0)).rounded())
        }
    }
    return 255
}

private func percentile(_ histogram: [Int], _ fraction: Double) -> Int {
    let target = max(1, Int((Double(histogram.reduce(0, +)) * fraction).rounded(.up)))
    var accumulated = 0
    for (value, count) in histogram.enumerated() {
        accumulated += count
        if accumulated >= target { return value }
    }
    return 255
}

private func shouldLiftShadows(median: Int, p95: Int) -> Bool {
    median < 40 && p95 >= 80
}

private func shadowLiftedImage(_ image: CGImage) -> (CGImage, Int, Int, Int, Bool) {
    let width = image.width
    let height = image.height
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var pixels = [UInt8](repeating: 0, count: width * height)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let baseAddress = bytes.baseAddress,
              let context = CGContext(
                  data: baseAddress,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return false }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard rendered else { return (image, 0, 0, 255, false) }

    var histogram = [Int](repeating: 0, count: 256)
    for pixel in pixels { histogram[Int(pixel)] += 1 }
    let p5 = percentile(histogram, 0.05)
    let median = percentile(histogram, 0.50)
    let p95 = percentile(histogram, 0.95)
    let shouldLift = shouldLiftShadows(median: median, p95: p95)
    guard shouldLift else { return (image, median, p5, p95, false) }

    let adjusted = pixels.map { UInt8(shadowLiftValue(Int($0))) }
    guard let provider = CGDataProvider(data: Data(adjusted) as CFData),
          let output = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 8,
              bytesPerRow: width,
              space: colorSpace,
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent
          ) else { return (image, median, p5, p95, false) }
    return (output, median, p5, p95, true)
}

if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--tone-tests" {
    precondition(shadowLiftValue(0) == 0 && shadowLiftValue(255) == 255, "tone curve must preserve black and white")
    precondition(shadowLiftValue(8) == 20 && shadowLiftValue(48) == 66, "tone curve must match the approved preview")
    precondition(shouldLiftShadows(median: 8, p95: 145), "dark photos should be lifted")
    precondition(!shouldLiftShadows(median: 50, p95: 170), "high-contrast reference should remain unchanged")
    precondition(!shouldLiftShadows(median: 8, p95: 60), "near-black frames should remain unchanged")
    print("Shadow tone-mapping tests passed.")
    exit(0)
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--orientation" {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { exit(3) }
    print((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
    exit(0)
}

guard CommandLine.arguments.count == 4 || CommandLine.arguments.count == 5 else {
    FileHandle.standardError.write(Data("usage: metadata-overlay INPUT OUTPUT LABEL [auto|fit]\n".utf8))
    exit(2)
}

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let label = CommandLine.arguments[3]
let renderMode = CommandLine.arguments.count == 5 ? CommandLine.arguments[4] : "auto"
guard renderMode == "auto" || renderMode == "fit" else {
    FileHandle.standardError.write(Data("render mode must be auto or fit\n".utf8))
    exit(2)
}

guard
    let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
    let rawSourceCG = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    FileHandle.standardError.write(Data("unable to open input image\n".utf8))
    exit(3)
}

let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
let maximumDimension = max(
    (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? rawSourceCG.width,
    (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? rawSourceCG.height
)
let thumbnailOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
]
guard let decodedCG = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
    FileHandle.standardError.write(Data("unable to normalize image orientation\n".utf8))
    exit(3)
}
let toneResult = shadowLiftedImage(decodedCG)
let sourceCG = toneResult.0
if ProcessInfo.processInfo.environment["PHOTOFRAME_DEBUG_TONE"] == "1" {
    FileHandle.standardError.write(Data("tone histogram p5=\(toneResult.2) p50=\(toneResult.1) p95=\(toneResult.3) shadowLift=\(toneResult.4)\n".utf8))
}
if ProcessInfo.processInfo.environment["PHOTOFRAME_DEBUG_ORIENTATION"] == "1" {
    let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    FileHandle.standardError.write(Data("orientation=\(orientation) raw=\(rawSourceCG.width)x\(rawSourceCG.height) display=\(sourceCG.width)x\(sourceCG.height)\n".utf8))
}

let canvasSize = NSSize(width: 1072, height: 1448)
let sourceSize = NSSize(width: sourceCG.width, height: sourceCG.height)
let source = NSImage(cgImage: sourceCG, size: sourceSize)

let edgeColorSpace = CGColorSpaceCreateDeviceRGB()

func averageEdgeColor(_ rect: CGRect) -> NSColor {
    let sampleRect = rect.intersection(CGRect(origin: .zero, size: sourceSize)).integral
    guard !sampleRect.isNull,
          sampleRect.width >= 1,
          sampleRect.height >= 1,
          let sample = sourceCG.cropping(to: sampleRect)
    else { return .black }

    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { bytes in
        guard let address = bytes.baseAddress,
              let sampleContext = CGContext(
                  data: address,
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bytesPerRow: 4,
                  space: edgeColorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        sampleContext.interpolationQuality = .high
        sampleContext.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }
    // Slightly darken the sampled edge so very pale photos never recreate the
    // previous stark white letterbox and metadata stays readable on E Ink.
    let shade: CGFloat = 0.82
    return NSColor(
        deviceRed: CGFloat(pixel[0]) / 255 * shade,
        green: CGFloat(pixel[1]) / 255 * shade,
        blue: CGFloat(pixel[2]) / 255 * shade,
        alpha: 1
    )
}

let verticalStrip = max(1, sourceSize.height * 0.04)
let horizontalStrip = max(1, sourceSize.width * 0.04)
// CGImage crop coordinates start at the image's visual top edge.
let topEdgeColor = averageEdgeColor(CGRect(x: 0, y: 0, width: sourceSize.width, height: verticalStrip))
let bottomEdgeColor = averageEdgeColor(CGRect(x: 0, y: sourceSize.height - verticalStrip, width: sourceSize.width, height: verticalStrip))
let leftEdgeColor = averageEdgeColor(CGRect(x: 0, y: 0, width: horizontalStrip, height: sourceSize.height))
let rightEdgeColor = averageEdgeColor(CGRect(x: sourceSize.width - horizontalStrip, y: 0, width: horizontalStrip, height: sourceSize.height))

let faceRequest = VNDetectFaceRectanglesRequest()
try? VNImageRequestHandler(cgImage: sourceCG, options: [:]).perform([faceRequest])
var detectedFaceRects = (faceRequest.results ?? []).map { face -> NSRect in
    let box = face.boundingBox
    return NSRect(
        x: box.minX * sourceSize.width,
        y: box.minY * sourceSize.height,
        width: box.width * sourceSize.width,
        height: box.height * sourceSize.height
    )
}
if detectedFaceRects.isEmpty,
   let detector = CIDetector(
       ofType: CIDetectorTypeFace,
       context: nil,
       options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
   ) {
    detectedFaceRects = detector.features(in: CIImage(cgImage: sourceCG)).compactMap {
        ($0 as? CIFaceFeature)?.bounds
    }
}
if ProcessInfo.processInfo.environment["PHOTOFRAME_DEBUG_FACES"] == "1" {
    FileHandle.standardError.write(Data("detected faces: \(detectedFaceRects.count)\n".utf8))
}

let fullSourceRect = NSRect(origin: .zero, size: sourceSize)
let targetAspect = canvasSize.width / canvasSize.height
let sourceAspect = sourceSize.width / sourceSize.height
var cropRect = fullSourceRect
if sourceAspect > targetAspect {
    cropRect.size.width = sourceSize.height * targetAspect
    cropRect.origin.x = (sourceSize.width - cropRect.width) / 2
} else {
    cropRect.size.height = sourceSize.width / targetAspect
    cropRect.origin.y = (sourceSize.height - cropRect.height) / 2
}

// Keep faces inside the portrait crop when that is geometrically possible. If a
// group is spread too widely, preserve the whole photograph instead of cutting
// people in half.
var faceBounds: NSRect?
for rect in detectedFaceRects {
    let padded = rect.insetBy(dx: -rect.width * 0.45, dy: -rect.height * 0.65)
        .intersection(fullSourceRect)
    faceBounds = faceBounds.map { $0.union(padded) } ?? padded
}

var useAspectFit = false
if let bounds = faceBounds {
    if bounds.width <= cropRect.width && bounds.height <= cropRect.height {
        cropRect.origin.x = min(
            max(bounds.midX - cropRect.width / 2, 0),
            sourceSize.width - cropRect.width
        )
        cropRect.origin.y = min(
            max(bounds.midY - cropRect.height / 2, 0),
            sourceSize.height - cropRect.height
        )
    } else {
        useAspectFit = true
    }
}
if renderMode == "fit" {
    useAspectFit = true
}
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("unable to create output bitmap\n".utf8))
    exit(4)
}
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("unable to create graphics context\n".utf8))
    exit(4)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.black.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()

var imageDestination = NSRect(origin: .zero, size: canvasSize)
if useAspectFit {
    let scale = min(canvasSize.width / sourceSize.width, canvasSize.height / sourceSize.height)
    imageDestination.size = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    imageDestination.origin = NSPoint(
        x: (canvasSize.width - imageDestination.width) / 2,
        y: (canvasSize.height - imageDestination.height) / 2
    )
    if imageDestination.minY > 0 {
        bottomEdgeColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: canvasSize.width, height: imageDestination.minY)).fill()
    }
    if imageDestination.maxY < canvasSize.height {
        topEdgeColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: imageDestination.maxY, width: canvasSize.width, height: canvasSize.height - imageDestination.maxY)).fill()
    }
    if imageDestination.minX > 0 {
        leftEdgeColor.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: imageDestination.minY, width: imageDestination.minX, height: imageDestination.height)).fill()
    }
    if imageDestination.maxX < canvasSize.width {
        rightEdgeColor.setFill()
        NSBezierPath(rect: NSRect(x: imageDestination.maxX, y: imageDestination.minY, width: canvasSize.width - imageDestination.maxX, height: imageDestination.height)).fill()
    }
    source.draw(in: imageDestination, from: fullSourceRect, operation: .copy, fraction: 1.0)
} else {
    source.draw(
        in: NSRect(origin: .zero, size: canvasSize),
        from: cropRect,
        operation: .copy,
        fraction: 1.0
    )
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .right
paragraph.lineBreakMode = .byWordWrapping
var attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .medium),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.shadowBlurRadius = 2
attributes[.shadow] = shadow

let attributed = NSAttributedString(string: label, attributes: attributes)
let maximumTextWidth: CGFloat = 920
let measured = attributed.boundingRect(
    with: NSSize(width: maximumTextWidth, height: 80),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
).integral
let horizontalPadding: CGFloat = 16
let verticalPadding: CGFloat = 10
let boxWidth = min(maximumTextWidth + horizontalPadding * 2, measured.width + horizontalPadding * 2)
let boxHeight = max(46, measured.height + verticalPadding * 2)
let box = NSRect(x: canvasSize.width - boxWidth - 20, y: 18, width: boxWidth, height: boxHeight)
NSColor.black.withAlphaComponent(0.68).setFill()
NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
let textRect = box.insetBy(dx: horizontalPadding, dy: verticalPadding)
attributed.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write(Data("unable to encode output image\n".utf8))
    exit(4)
}

do {
    try png.write(to: URL(fileURLWithPath: output), options: .atomic)
} catch {
    FileHandle.standardError.write(Data("unable to write output image: \(error)\n".utf8))
    exit(5)
}
