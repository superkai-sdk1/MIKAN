#!/usr/bin/env swift
// Builds the MIKAN brand assets from the studio logo (docs/brand/mikan-logo.pdf):
//  - Logo.imageset/MikanLogo.pdf — the wordmark cropped to its outline, kept vector (used as a template image);
//  - AppIcon.appiconset/AppIcon{,-Dark,-Tinted}.png — opaque 1024×1024 icons for the light, dark and tinted home screen.
// Usage: swift ios/Scripts/generate_icon.swift <logo.pdf> <Assets.xcassets>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconSide = 1024
/// Share of the icon width taken by the wordmark.
let logoWidthRatio: CGFloat = 0.74
/// Transparent margin kept around the cropped wordmark, relative to its height.
let cropPaddingRatio: CGFloat = 0.03

let args = CommandLine.arguments
guard args.count == 3,
      let document = CGPDFDocument(URL(fileURLWithPath: args[1]) as CFURL),
      let page = document.page(at: 1) else {
    fatalError("usage: generate_icon.swift <logo.pdf> <Assets.xcassets>")
}
let assets = URL(fileURLWithPath: args[2])
let mediaBox = page.getBoxRect(.mediaBox)

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws the (black) logo onto a white grayscale bitmap: `transform` maps PDF units to pixels. Ink = dark pixels.
func grayCanvas(width: Int, height: Int, transform: (CGContext) -> Void) -> (context: CGContext, pixels: UnsafeMutablePointer<UInt8>) {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        fatalError("Cannot create grayscale context")
    }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    transform(context)
    context.drawPDFPage(page)
    return (context, context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height))
}

/// Bounds of the ink in PDF units, measured on a 4× raster of the page.
func inkBounds() -> CGRect {
    let scale: CGFloat = 4
    let width = Int(mediaBox.width * scale), height = Int(mediaBox.height * scale)
    let (context, pixels) = grayCanvas(width: width, height: height) { ctx in
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
    }
    var minX = width, minRow = height, maxX = -1, maxRow = -1
    for row in 0..<height {
        for x in 0..<width where pixels[row * context.bytesPerRow + x] < 255 {
            minX = min(minX, x); maxX = max(maxX, x); minRow = min(minRow, row); maxRow = max(maxRow, row)
        }
    }
    guard maxX >= 0 else { fatalError("The logo page is empty") }
    // Bitmap rows run top-down; PDF y runs bottom-up.
    let ink = CGRect(
        x: mediaBox.minX + CGFloat(minX) / scale,
        y: mediaBox.maxY - CGFloat(maxRow + 1) / scale,
        width: CGFloat(maxX - minX + 1) / scale,
        height: CGFloat(maxRow - minRow + 1) / scale
    )
    let pad = ink.height * cropPaddingRatio
    return ink.insetBy(dx: -pad, dy: -pad)
}

func writeCroppedPDF(_ bounds: CGRect, to url: URL) {
    var box = CGRect(origin: .zero, size: bounds.size)
    guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { fatalError("Cannot create \(url.path)") }
    context.beginPDFPage(nil)
    context.translateBy(x: -bounds.minX, y: -bounds.minY)
    context.drawPDFPage(page)
    context.endPDFPage()
    context.closePDF()
}

/// Opaque icon: `ink`-colored wordmark centered on a `background` square.
func writeIcon(background: CGColor, ink: CGColor, logo bounds: CGRect, to url: URL) {
    let side = CGFloat(iconSide)
    let scale = side * logoWidthRatio / bounds.width
    let origin = CGPoint(x: (side - bounds.width * scale) / 2, y: (side - bounds.height * scale) / 2)
    let (maskContext, maskPixels) = grayCanvas(width: iconSide, height: iconSide) { ctx in
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    }
    // clip(to:mask:) paints where the gray mask is light, so invert the black-ink canvas (decode arrays are ignored there).
    let inverted = Data(UnsafeBufferPointer(start: maskPixels, count: maskContext.bytesPerRow * iconSide).map { 255 - $0 })
    guard let provider = CGDataProvider(data: inverted as CFData),
          let mask = CGImage(width: iconSide, height: iconSide, bitsPerComponent: 8, bitsPerPixel: 8,
                             bytesPerRow: maskContext.bytesPerRow, space: CGColorSpaceCreateDeviceGray(),
                             bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                             provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
          let context = CGContext(data: nil, width: iconSide, height: iconSide, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Cannot render \(url.lastPathComponent)")
    }
    let full = CGRect(x: 0, y: 0, width: side, height: side)
    context.setFillColor(background)
    context.fill(full)
    context.clip(to: full, mask: mask)
    context.setFillColor(ink)
    context.fill(full)
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]
let bounds = inkBounds()
let fm = FileManager.default

let logoSet = assets.appendingPathComponent("Logo.imageset")
try fm.createDirectory(at: logoSet, withIntermediateDirectories: true)
writeCroppedPDF(bounds, to: logoSet.appendingPathComponent("MikanLogo.pdf"))
try writeJSON([
    "images": [["filename": "MikanLogo.pdf", "idiom": "universal"]],
    "info": info,
    "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"],
], to: logoSet.appendingPathComponent("Contents.json"))

let iconSet = assets.appendingPathComponent("AppIcon.appiconset")
try fm.createDirectory(at: iconSet, withIntermediateDirectories: true)
let black = rgb(0x0B0B0B), white = rgb(0xFFFFFF)
let variants: [(file: String, background: CGColor, ink: CGColor, appearance: String?)] = [
    ("AppIcon.png", white, black, nil),
    ("AppIcon-Dark.png", black, white, "dark"),
    ("AppIcon-Tinted.png", black, white, "tinted"),
]
var images: [[String: Any]] = []
for variant in variants {
    writeIcon(background: variant.background, ink: variant.ink, logo: bounds, to: iconSet.appendingPathComponent(variant.file))
    var entry: [String: Any] = ["filename": variant.file, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let appearance = variant.appearance {
        entry["appearances"] = [["appearance": "luminosity", "value": appearance]]
    }
    images.append(entry)
}
try writeJSON(["images": images, "info": info], to: iconSet.appendingPathComponent("Contents.json"))
print("Logo bounds (pt): \(bounds.integral); wrote Logo.imageset and \(variants.count) app icons")
