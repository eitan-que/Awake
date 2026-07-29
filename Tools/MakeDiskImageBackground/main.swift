// MakeDiskImageBackground - build-time tool that renders the backdrop for the
// installer window in Awake.dmg: a caption and an arrow pointing from where the
// app icon sits to the Applications folder beside it.
//
// Generated rather than committed for the same reason the icon is: the arrow
// has to land between two icon positions that the Makefile chooses, so the
// drawing and the layout come from one set of numbers instead of a picture that
// has to be re-made by hand whenever the window moves.
//
// Usage: MakeDiskImageBackground <output.png> [<output@2x.png>]

import Cocoa

// The window is 600x400 with the icons centred on y=170 from the top, matching
// the AppleScript in the Makefile's `dmg` target.
let width: CGFloat = 600
let height: CGFloat = 400
let iconCentreY: CGFloat = height - 170
let appCentreX: CGFloat = 160
let applicationsCentreX: CGFloat = 440

/// Light on purpose, which is not a style choice. Finder draws icon labels in
/// its light-appearance colour -- near black -- whenever an icon view has a
/// background picture, in dark mode too, and nothing in the scripting interface
/// changes that. A dark backdrop leaves the file names barely legible, which is
/// why practically every app's disk image is pale.
///
/// Warm off-white to match the ceramic in the icon.
let backdropTop = NSColor(srgbRed: 0.99, green: 0.97, blue: 0.94, alpha: 1)
let backdropBottom = NSColor(srgbRed: 0.95, green: 0.91, blue: 0.85, alpha: 1)
let accent = NSColor(srgbRed: 0.72, green: 0.40, blue: 0.18, alpha: 1)
let inkStrong = NSColor(srgbRed: 0.22, green: 0.15, blue: 0.10, alpha: 1)
let inkSoft = NSColor(srgbRed: 0.45, green: 0.36, blue: 0.29, alpha: 1)

func drawBackground(scale: CGFloat) -> NSBitmapImageRep? {
    let pixelsWide = Int(width * scale)
    let pixelsHigh = Int(height * scale)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.cgContext.setShouldAntialias(true)

    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(colors: [backdropTop, backdropBottom])?.draw(in: canvas, angle: -90)

    drawArrow()
    drawCaption()

    return rep
}

/// Runs between the two icons rather than under them, so neither the app nor
/// the Applications alias sits on top of it at any icon size.
func drawArrow() {
    let clearance: CGFloat = 78
    let start = NSPoint(x: appCentreX + clearance, y: iconCentreY)
    let end = NSPoint(x: applicationsCentreX - clearance, y: iconCentreY)
    let head: CGFloat = 18

    accent.set()

    let shaft = NSBezierPath()
    shaft.move(to: start)
    shaft.line(to: NSPoint(x: end.x - head, y: end.y))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    shaft.stroke()

    let arrowhead = NSBezierPath()
    arrowhead.move(to: end)
    arrowhead.line(to: NSPoint(x: end.x - head, y: end.y + head * 0.62))
    arrowhead.line(to: NSPoint(x: end.x - head, y: end.y - head * 0.62))
    arrowhead.close()
    arrowhead.fill()
}

func drawCaption() {
    let title = "Drag Awake into Applications"
    let subtitle = "then open it from there, not from here"

    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: inkStrong,
    ]
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: inkSoft,
    ]

    centre(title, attributes: titleAttributes, y: 78)
    centre(subtitle, attributes: subtitleAttributes, y: 54)
}

func centre(_ text: String, attributes: [NSAttributedString.Key: Any], y: CGFloat) {
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: NSPoint(x: (width - size.width) / 2, y: y))
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let outputs = Array(CommandLine.arguments.dropFirst())
guard !outputs.isEmpty else {
    FileHandle.standardError.write(Data("usage: MakeDiskImageBackground <out.png> [<out@2x.png>]\n".utf8))
    exit(1)
}

// Retina Finder windows pick the @2x file up by name, so both are written.
for (index, path) in outputs.enumerated() {
    guard let rep = drawBackground(scale: index == 0 ? 1 : 2) else { exit(1) }
    write(rep, to: path)
}

print("MakeDiskImageBackground: wrote \(outputs.count) file(s)")
