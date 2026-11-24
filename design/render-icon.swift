// Renders the Finder icon of an app bundle to a PNG, optionally in dark appearance.
// Usage: swift design/render-icon.swift <App.app> <out.png> [size] [light|dark]
// Preview: swift design/render-icon.swift "dist/Herdr Core Bar.app" design/icon-preview.png 1024
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <App.app> <out.png> [size] [light|dark]\n".utf8))
    exit(2)
}
// Icon Services silently returns a generic icon for relative paths.
let appPath = URL(fileURLWithPath: args[1]).standardizedFileURL.path
let size = args.count > 3 ? Int(args[3]) ?? 1024 : 1024
let appearance = NSAppearance(named: args.count > 4 && args[4] == "dark" ? .darkAqua : .aqua)!

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

appearance.performAsCurrentDrawingAppearance {
    let icon = NSWorkspace.shared.icon(forFile: appPath)
    icon.size = NSSize(width: size, height: size)
    rep.size = icon.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
}

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: args[2]))
