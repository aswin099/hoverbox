// Renders Hoverbox's icons from vector drawing code, so macOS and Windows stay in sync.
// Usage: swift tools/render-icon.swift App/Assets.xcassets [Windows/src/Hoverbox.App/Assets]
//   macOS:   AppIcon (all sizes). The menu bar uses the system "shippingbox" symbol instead.
//   Windows: Hoverbox.ico (exe and windows), TrayIcon.ico and TrayIconPaused.ico (notification area)
// Design: deep ocean tile, an open cardboard box hovering above its shadow, a photo and a
// document rising out of it, one coral dot.
import AppKit

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Palette {
    var tile, front, side, inside, flap, photo, sun, hills, card, lines, dot, shadow: NSColor
}

let colorPalette = Palette(tile: rgb(0x143A5C), front: rgb(0xF4B66A), side: rgb(0xD98E48), inside: rgb(0x6E4120),
                           flap: rgb(0xE7A157), photo: rgb(0xCFEAFF), sun: rgb(0xFFC94A), hills: rgb(0x4E9FD8),
                           card: .white, lines: rgb(0x143A5C).withAlphaComponent(0.22), dot: rgb(0xFF6B57),
                           shadow: NSColor.black.withAlphaComponent(0.34))
/// Grey version for the paused Windows tray icon.
let pausedPalette = Palette(tile: NSColor(white: 0.45, alpha: 1), front: NSColor(white: 0.86, alpha: 1),
                            side: NSColor(white: 0.74, alpha: 1), inside: NSColor(white: 0.38, alpha: 1),
                            flap: NSColor(white: 0.8, alpha: 1), photo: NSColor(white: 0.93, alpha: 1),
                            sun: NSColor(white: 0.8, alpha: 1), hills: NSColor(white: 0.62, alpha: 1),
                            card: NSColor(white: 0.97, alpha: 1), lines: NSColor(white: 0, alpha: 0.2),
                            dot: NSColor(white: 0.7, alpha: 1), shadow: NSColor.black.withAlphaComponent(0.3))

/// Drawing options for the platform and size being rendered.
var palette = colorPalette
var useShadows = true      // macOS icons have soft shadows; Windows icons are flat.
var showDetail = true      // Text lines, the photo and the dot blur away below ~48 px, so small sizes omit them.
var tileRadius: CGFloat = 185

/// Pixels per drawing unit for the image being rendered. NSShadow sizes are in pixels and
/// don't follow the drawing scale, so shadows multiply by this to look the same at every size.
var pixelScale: CGFloat = 1

func makeShadow(alpha: CGFloat, offsetY: CGFloat, blur: CGFloat) -> NSShadow {
    let shadow = NSShadow()
    guard useShadows else { return shadow }
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowOffset = NSSize(width: 0, height: offsetY * pixelScale)
    shadow.shadowBlurRadius = blur * pixelScale
    return shadow
}

func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.line(to: NSPoint(x: point.0, y: point.1)) }
    path.close()
    path.lineJoinStyle = .round
    return path
}

/// Fills a polygon with slightly rounded corners by stroking it in the same colour.
func fillRounded(_ path: NSBezierPath, _ color: NSColor, radius: CGFloat = 14) {
    color.set()
    path.fill()
    path.lineWidth = radius
    path.stroke()
}

/// Draws the icon in a 1024×1024 coordinate space (y up), scaled to the context.
func drawIcon() {
    // macOS icon grid: 824×824 tile centered in the 1024 canvas, corner radius ~185.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)

    NSGraphicsContext.saveGraphicsState()
    makeShadow(alpha: 0.28, offsetY: -10, blur: 24).set()
    palette.tile.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()

    // The box, in a three-quarter view: front face, right side, open top. It floats
    // above its shadow; the gap between them is what makes it "hover".
    let frontLeft: CGFloat = 250, frontRight: CGFloat = 610, bottom: CGFloat = 318, rim: CGFloat = 548
    let depthX: CGFloat = 156, depthY: CGFloat = 72

    // Shadow on the "floor".
    palette.shadow.setFill()
    NSBezierPath(ovalIn: NSRect(x: 262, y: 196, width: 470, height: 58)).fill()

    // Back flap and left flap, folded open behind the contents.
    fillRounded(polygon([(frontLeft + depthX, rim + depthY), (frontRight + depthX, rim + depthY),
                         (frontRight + depthX - 30, rim + depthY + 118), (frontLeft + depthX + 26, rim + depthY + 118)]),
                palette.side)
    fillRounded(polygon([(frontLeft, rim), (frontLeft + depthX, rim + depthY),
                         (frontLeft + depthX - 150, rim + depthY + 70), (frontLeft - 128, rim + 52)]),
                palette.flap)

    // Inside of the box.
    let opening = polygon([(frontLeft, rim), (frontRight, rim), (frontRight + depthX, rim + depthY), (frontLeft + depthX, rim + depthY)])
    fillRounded(opening, palette.inside, radius: 10)

    // Contents, clipped so they appear to rise out of the opening.
    NSGraphicsContext.saveGraphicsState()
    polygon([(frontLeft, rim), (frontRight, rim), (frontRight + depthX, rim + depthY), (930, rim + depthY),
             (930, 930), (94, 930), (94, rim + depthY), (frontLeft + depthX, rim + depthY)]).addClip()
    drawPhoto(center: NSPoint(x: 452, y: 712), size: NSSize(width: 270, height: 300), angle: 11)
    drawCard(center: NSPoint(x: 596, y: 700), size: NSSize(width: 270, height: 330), angle: -8)
    NSGraphicsContext.restoreGraphicsState()

    // Right side, then the front, which hides the bottoms of the contents.
    fillRounded(polygon([(frontRight, bottom), (frontRight + depthX, bottom + depthY),
                         (frontRight + depthX, rim + depthY), (frontRight, rim)]), palette.side)
    NSGraphicsContext.saveGraphicsState()
    makeShadow(alpha: 0.18, offsetY: 6, blur: 14).set()
    // One layer, so the shadow falls once around the whole face rather than on fill and stroke separately.
    NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
    fillRounded(polygon([(frontLeft, bottom), (frontRight, bottom), (frontRight, rim), (frontLeft, rim)]), palette.front)
    NSGraphicsContext.current?.cgContext.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()

    if showDetail {
        // A strip of tape across the front, as on a shipping box.
        palette.flap.withAlphaComponent(0.9).setFill()
        NSBezierPath(rect: NSRect(x: (frontLeft + frontRight) / 2 - 34, y: rim - 92, width: 68, height: 92)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// A photo print: sky, sun and two hills.
func drawPhoto(center: NSPoint, size: NSSize, angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angle)
    transform.concat()
    let rect = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

    makeShadow(alpha: 0.22, offsetY: -6, blur: 16).set()
    palette.card.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
    NSShadow().set()

    let picture = rect.insetBy(dx: 22, dy: 22)
    let picturePath = NSBezierPath(roundedRect: picture, xRadius: 16, yRadius: 16)
    palette.photo.setFill()
    picturePath.fill()
    if showDetail {
        NSGraphicsContext.saveGraphicsState()
        picturePath.addClip()
        palette.sun.setFill()
        NSBezierPath(ovalIn: NSRect(x: picture.minX + 34, y: picture.maxY - 92, width: 52, height: 52)).fill()
        palette.hills.setFill()
        polygon([(picture.minX - 20, picture.minY), (picture.minX + 70, picture.minY + 130), (picture.minX + 170, picture.minY)]).fill()
        palette.hills.withAlphaComponent(0.7).setFill()
        polygon([(picture.minX + 90, picture.minY), (picture.minX + 180, picture.minY + 96), (picture.maxX + 30, picture.minY)]).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// A document with text lines and the coral dot.
func drawCard(center: NSPoint, size: NSSize, angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angle)
    transform.concat()
    let rect = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

    makeShadow(alpha: 0.22, offsetY: -6, blur: 16).set()
    palette.card.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
    NSShadow().set()

    if showDetail {
        palette.lines.setFill()
        let left = rect.minX + 40
        for (i, width) in [150.0, 186.0, 120.0].enumerated() {
            let y = rect.maxY - 112 - CGFloat(i) * 48
            NSBezierPath(roundedRect: NSRect(x: left, y: y, width: width, height: 20), xRadius: 10, yRadius: 10).fill()
        }
        palette.dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: rect.maxX - 76, y: rect.maxY - 76, width: 40, height: 40)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

/// Windows icons fill more of their square than macOS icons and have gentler corners.
func drawWindowsIcon() {
    let scale: CGFloat = 952 / 824  // macOS tile (824) grown to a 952 tile, 36 units from each edge.
    let t = NSAffineTransform()
    t.translateX(by: 512, yBy: 512)
    t.scale(by: scale)
    t.translateX(by: -512, yBy: -512)
    t.concat()
    drawIcon()
}

/// Writes a Windows .ico file with one PNG-compressed image per size (supported since Windows Vista).
func writeICO(_ entries: [(size: Int, png: Data)], to url: URL) throws {
    var data = Data()
    func le16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)]) }
    func le32(_ v: Int) { le16(v & 0xffff); le16((v >> 16) & 0xffff) }
    le16(0); le16(1); le16(entries.count)
    var offset = 6 + 16 * entries.count
    for entry in entries {
        data.append(UInt8(entry.size >= 256 ? 0 : entry.size))  // 0 means 256
        data.append(UInt8(entry.size >= 256 ? 0 : entry.size))
        data.append(0); data.append(0)  // no palette, reserved
        le16(1); le16(32)                // planes, bits per pixel
        le32(entry.png.count); le32(offset)
        offset += entry.png.count
    }
    for entry in entries { data.append(entry.png) }
    try data.write(to: url)
}

func png(pixels: Int, points: CGFloat, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    context.imageInterpolation = .high
    NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / points
    pixelScale = scale
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let catalog = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "App/Assets.xcassets")
let fm = FileManager.default
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset")
try? fm.createDirectory(at: appIcon, withIntermediateDirectories: true)

try #"{"info":{"author":"xcode","version":1}}"#.write(to: catalog.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        showDetail = pixels >= 48
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: pixels, points: 1024, draw: drawIcon).write(to: appIcon.appendingPathComponent(name))
        images.append(#"{"filename":"\#(name)","idiom":"mac","scale":"\#(scale)x","size":"\#(size)x\#(size)"}"#)
    }
}
showDetail = true
try #"{"images":[\#(images.joined(separator: ","))],"info":{"author":"xcode","version":1}}"#
    .write(to: appIcon.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

print("Wrote \(images.count) app icon sizes to \(catalog.path)")

// Previews for checking the design by eye (not used by the app).
if let previewDir = ProcessInfo.processInfo.environment["ICON_PREVIEW_DIR"] {
    let dir = URL(fileURLWithPath: previewDir)
    try png(pixels: 512, points: 1024, draw: drawIcon).write(to: dir.appendingPathComponent("icon-512.png"))
}

// Windows
if CommandLine.arguments.count > 2 {
    let windows = URL(fileURLWithPath: CommandLine.arguments[2])
    try? fm.createDirectory(at: windows, withIntermediateDirectories: true)
    useShadows = false
    tileRadius = 150

    func render(_ sizes: [Int], palette chosen: Palette) -> [(size: Int, png: Data)] {
        palette = chosen
        return sizes.map { size in
            showDetail = size >= 48
            return (size, png(pixels: size, points: 1024, draw: drawWindowsIcon))
        }
    }
    // App icon: every size Windows asks for across Explorer views and display scaling.
    try writeICO(render([16, 20, 24, 32, 40, 48, 64, 96, 128, 256], palette: colorPalette),
                 to: windows.appendingPathComponent("Hoverbox.ico"))
    // Notification area: 16 px at 100% scaling up to 32 px at 200%.
    try writeICO(render([16, 20, 24, 32, 40, 48], palette: colorPalette), to: windows.appendingPathComponent("TrayIcon.ico"))
    try writeICO(render([16, 20, 24, 32, 40, 48], palette: pausedPalette), to: windows.appendingPathComponent("TrayIconPaused.ico"))
    print("Wrote Hoverbox.ico, TrayIcon.ico and TrayIconPaused.ico to \(windows.path)")
}
