import AppKit
import Foundation

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write(Data("usage: metadata-overlay INPUT OUTPUT LABEL\n".utf8))
    exit(2)
}

let input = CommandLine.arguments[1]
let output = CommandLine.arguments[2]
let label = CommandLine.arguments[3]

guard let source = NSImage(contentsOfFile: input) else {
    FileHandle.standardError.write(Data("unable to open input image\n".utf8))
    exit(3)
}

let canvasSize = NSSize(width: 1072, height: 1448)
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
source.draw(
    in: NSRect(origin: .zero, size: canvasSize),
    from: NSRect(origin: .zero, size: source.size),
    operation: .copy,
    fraction: 1.0
)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .right
paragraph.lineBreakMode = .byTruncatingHead
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.8)
shadow.shadowOffset = NSSize(width: 0, height: -1)
shadow.shadowBlurRadius = 2
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 22, weight: .medium),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
    .shadow: shadow,
]

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
