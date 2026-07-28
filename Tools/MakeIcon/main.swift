// MakeIcon - build-time tool that renders Awake.icns from the mug SF Symbol.
//
// Keeping the icon generated rather than committed as a binary blob means the
// app icon and the menu bar glyph can never drift apart: both come from
// "mug.fill". Not shipped inside the bundle.
//
// Usage: MakeIcon <output.iconset directory>

import Cocoa

let outputDirectory = CommandLine.arguments.count >= 2
    ? CommandLine.arguments[1]
    : "./Awake.iconset"

try? FileManager.default.createDirectory(atPath: outputDirectory,
                                         withIntermediateDirectories: true)

/// Recolours a template symbol on its own transparent canvas.
///
/// Tinting in place over the artwork would flood the whole rectangle, because
/// sourceAtop keys off destination alpha and the background is opaque
/// everywhere.
func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
    let output = NSImage(size: image.size)
    output.lockFocus()
    let rect = NSRect(origin: .zero, size: image.size)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
    color.set()
    rect.fill(using: .sourceAtop)
    output.unlockFocus()
    return output
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current?.cgContext else { return image }
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // Inset so the shape does not touch the canvas edge, as system icons do.
    let inset = size * 0.09
    let rect = NSRect(x: inset, y: inset,
                      width: size - inset * 2,
                      height: size - inset * 2)
    let radius = rect.width * 0.2237

    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()

    // Ceramic to espresso, so a white mug reads cleanly at every size.
    NSGradient(colors: [
        NSColor(srgbRed: 0.98, green: 0.85, blue: 0.66, alpha: 1),
        NSColor(srgbRed: 0.85, green: 0.51, blue: 0.28, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.28, blue: 0.16, alpha: 1),
    ])?.draw(in: rect, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: rect.width * 0.52,
                                                    weight: .medium)
    if let symbol = NSImage(systemSymbolName: "mug.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let glyph = tinted(symbol, with: .white)
        let glyphRect = NSRect(x: rect.midX - glyph.size.width / 2,
                               y: rect.midY - glyph.size.height / 2,
                               width: glyph.size.width,
                               height: glyph.size.height)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.shadowBlurRadius = size * 0.03
        shadow.set()

        glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    return image
}

func write(_ image: NSImage, to path: String, pixels: Int) {
    guard let tiff = image.tiffRepresentation,
          let source = NSBitmapImageRep(data: tiff),
          let target = NSBitmapImageRep(
              bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return }

    target.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = target.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// The exact set iconutil expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    write(drawIcon(size: CGFloat(variant.pixels)),
          to: "\(outputDirectory)/\(variant.name).png",
          pixels: variant.pixels)
}

print("MakeIcon: wrote \(variants.count) sizes to \(outputDirectory)")
