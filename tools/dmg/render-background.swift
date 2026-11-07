// Renders the background of the Hoverbox install window (the .dmg), at 1x and 2x.
// Usage: swift tools/dmg/render-background.swift <output folder> [--signed]
// --signed leaves out the "Open Anyway" footer, which notarized builds don't need.
// Writes background.png and background@2x.png. Icon positions live in settings.py;
// keep the arrow between them if either changes.
import AppKit

let size = NSSize(width: 660, height: 400)

let skyTop = NSColor(srgbRed: 0xEA / 255, green: 0xF6 / 255, blue: 0xFF / 255, alpha: 1)
let sky100 = NSColor(srgbRed: 0xCF / 255, green: 0xEA / 255, blue: 0xFF / 255, alpha: 1)
let ocean900 = NSColor(srgbRed: 0x14 / 255, green: 0x3A / 255, blue: 0x5C / 255, alpha: 1)
let coral400 = NSColor(srgbRed: 0xFF / 255, green: 0x6B / 255, blue: 0x57 / 255, alpha: 1)
let muted = ocean900.withAlphaComponent(0.7)
let rule = ocean900.withAlphaComponent(0.25)

let arguments = CommandLine.arguments.dropFirst()
let signed = arguments.contains("--signed")

/// Converts a y measured from the top (as Finder and settings.py do) to AppKit's y-up.
func top(_ y: CGFloat) -> CGFloat { size.height - y }

func text(_ string: String, at point: NSPoint, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .kern: kern]
    let line = NSAttributedString(string: string, attributes: attributes)
    // `point` is the top-left of the text box.
    line.draw(at: NSPoint(x: point.x, y: top(point.y) - line.size().height))
}

func draw() {
    // Sky, lighter at the top.
    NSGradient(starting: skyTop, ending: sky100)!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Header: name, a rule with the coral accent dot, and the tagline.
    text("Hoverbox", at: NSPoint(x: 44, y: 34), font: .systemFont(ofSize: 34, weight: .bold), color: ocean900, kern: -0.5)
    rule.setFill()
    NSRect(x: 44, y: top(92), width: 572, height: 1).fill()
    coral400.setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: top(92) - 4, width: 9, height: 9)).fill()
    text("A box that hovers, holding what you drag", at: NSPoint(x: 44, y: 106),
         font: .systemFont(ofSize: 13, weight: .regular), color: muted)

    // Dotted arrow from the app (x 170) to Applications (x 490), both centered at y 212.
    let y = top(212)
    ocean900.setStroke()
    ocean900.setFill()
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 264, y: y))
    line.line(to: NSPoint(x: 380, y: y))
    line.lineWidth = 3
    line.lineCapStyle = .round
    line.setLineDash([2, 9], count: 2, phase: 0)
    line.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 398, y: y))
    head.line(to: NSPoint(x: 378, y: y + 10))
    head.line(to: NSPoint(x: 378, y: y - 10))
    head.close()
    head.fill()
    let hint = NSAttributedString(string: "Drag to install", attributes: [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: muted,
    ])
    hint.draw(at: NSPoint(x: 330 - hint.size().width / 2, y: y - 22 - hint.size().height))

    // Footer: the first-open step people get stuck on when the build isn't notarized.
    guard !signed else { return }
    rule.setFill()
    NSRect(x: 44, y: top(336), width: 572, height: 1).fill()
    text("First open: if macOS blocks Hoverbox, go to System Settings › Privacy & Security › Open Anyway.",
         at: NSPoint(x: 44, y: 350), font: .systemFont(ofSize: 11, weight: .regular), color: ocean900.withAlphaComponent(0.65))
}

func png(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let output = URL(fileURLWithPath: arguments.first { !$0.hasPrefix("--") } ?? ".")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try png(scale: 1).write(to: output.appendingPathComponent("background.png"))
try png(scale: 2).write(to: output.appendingPathComponent("background@2x.png"))
print("Wrote background.png and background@2x.png to \(output.path)")
