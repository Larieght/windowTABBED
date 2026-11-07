import AppKit

/// Each tab is tinted with its app's color, taken from the app icon.
enum AppTint {
    /// Used when an icon has no clear color (grey or missing icons).
    static let fallback = NSColor(srgbRed: 0.29, green: 0.32, blue: 0.41, alpha: 1)

    private static var cache: [String: NSColor] = [:]

    static func color(for app: NSRunningApplication?) -> NSColor {
        guard let app else { return fallback }
        let key = app.bundleIdentifier ?? "pid-\(app.processIdentifier)"
        if let cached = cache[key] { return cached }
        let color = app.icon.flatMap(dominantColor(of:)) ?? fallback
        cache[key] = color
        return color
    }

    /// Average of the icon's colorful pixels, toned down so white text stays readable on it.
    static func dominantColor(of icon: NSImage) -> NSColor? {
        let size = 16
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, total: CGFloat = 0
        for x in 0..<size {
            for y in 0..<size {
                guard let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                // Weight by saturation so white backgrounds and grey outlines don't wash the color out.
                let weight = pixel.saturationComponent * pixel.alphaComponent
                red += pixel.redComponent * weight
                green += pixel.greenComponent * weight
                blue += pixel.blueComponent * weight
                total += weight
            }
        }
        guard total > 0.5 else { return nil }

        let average = NSColor(srgbRed: red / total, green: green / total, blue: blue / total, alpha: 1)
        return NSColor(
            hue: average.hueComponent,
            saturation: min(max(average.saturationComponent, 0.25), 0.5),
            brightness: 0.55,
            alpha: 1)
    }
}
