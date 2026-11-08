import AppKit

/// Compile together with Sources/BarTidy/BrandIcon.swift to keep the artwork
/// consistent while the menu glyph receives its own optical fit.
@main enum GenerateIcon {
    static func main() throws {
        let output = URL(filePath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
                let transform = NSAffineTransform()
                transform.scale(by: CGFloat(pixels) / 1024)
                transform.concat()
                let tile = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205)
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
                shadow.shadowBlurRadius = CGFloat(pixels) * 18 / 1024
                shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 5 / 1024)
                shadow.set()
                NSColor.white.setFill()
                tile.fill()
                NSGraphicsContext.restoreGraphicsState()
                NSGradient(starting: .white,
                           ending: NSColor(white: 0.945, alpha: 1))!
                    .draw(in: tile, angle: -80)
                NSColor.white.withAlphaComponent(0.8).setStroke()
                tile.lineWidth = 2
                tile.stroke()
                BrandIcon.draw(in: NSRect(x: 122, y: 104, width: 780, height: 780),
                               color: NSColor(white: 0.12, alpha: 1))
                NSGraphicsContext.restoreGraphicsState()
                let suffix = scale == 2 ? "@2x" : ""
                try bitmap.representation(using: .png, properties: [:])!
                    .write(to: output.appending(path: "icon_\(size)x\(size)\(suffix).png"))
            }
        }
        // Native-size transparent exports are also useful for visual QA.
        for pixels in [20, 40, 80, 512] {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
            if pixels < 512 {
                let inset = CGFloat(pixels) * (BrandIcon.menuBarCanvas - BrandIcon.menuBarInk) / (2 * BrandIcon.menuBarCanvas)
                BrandIcon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels).insetBy(dx: inset, dy: inset), color: .black, opticalFit: true)
            } else {
                BrandIcon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), color: .black)
            }
            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!
                .write(to: output.deletingLastPathComponent().appending(path: "bilby-mark-\(pixels).png"))
            if pixels == 40 {
                var bounds = NSRect.null
                for y in 0..<pixels {
                    for x in 0..<pixels where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                        bounds = bounds.union(NSRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                print("Menu glyph ink at 2x: \(Int(bounds.width)) × \(Int(bounds.height)) px")
            }
        }
        try BrandIcon.svg.write(to: output.deletingLastPathComponent().appending(path: "bilby-mark.svg"), atomically: true, encoding: .utf8)
        try validateMotion(output: output.deletingLastPathComponent())
    }

    private static func glyph(pixels: Int, pose: BrandIcon.EarPose) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
        let inset = CGFloat(pixels) * (BrandIcon.menuBarCanvas - BrandIcon.menuBarInk) / (2 * BrandIcon.menuBarCanvas)
        BrandIcon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels).insetBy(dx: inset, dy: inset),
                       color: .black, opticalFit: true, pose: pose)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func validateMotion(output: URL) throws {
        let frames = (0...31).map { glyph(pixels: 40, pose: BrandIcon.earPose(at: Double($0) / 31)) }
        func alpha(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) -> CGFloat {
            image.colorAt(x: x, y: y)!.alphaComponent
        }
        var changed = false
        for (index, frame) in frames.enumerated() {
            for p in 0..<40 {
                guard alpha(frame, 0, p) < 0.02, alpha(frame, 39, p) < 0.02,
                      alpha(frame, p, 0) < 0.02, alpha(frame, p, 39) < 0.02 else {
                    throw NSError(domain: "BrandMotion", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Animation frame \(index) touches the canvas edge"])
                }
            }
            for y in 0..<40 {
                for x in 0..<40 {
                    let difference = abs(alpha(frame, x, y) - alpha(frames[0], x, y))
                    changed = changed || difference > 0.05
                    if y >= 28, difference > 0.001 {
                        throw NSError(domain: "BrandMotion", code: 2,
                                      userInfo: [NSLocalizedDescriptionKey: "The lower face moves in animation frame \(index)"])
                    }
                }
            }
        }
        guard changed,
              frames[0].representation(using: .png, properties: [:]) == frames[31].representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BrandMotion", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Animation must move and return exactly to the resting image"])
        }

        let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 400,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)!
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 400).fill()
        let samples: [Double] = [0, 0.20, 0.46, 0.70, 1]
        for (index, t) in samples.enumerated() {
            let x = CGFloat(index) * 200
            let pose = BrandIcon.earPose(at: t)
            BrandIcon.draw(in: NSRect(x: x + 24, y: 170, width: 152, height: 152), color: .black, pose: pose)
            BrandIcon.draw(in: NSRect(x: x + 82.5, y: 130, width: 35, height: 35), color: .black, opticalFit: true, pose: pose)
            NSColor(white: 0.14, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: x + 24, y: 50, width: 152, height: 56), xRadius: 10, yRadius: 10).fill()
            BrandIcon.draw(in: NSRect(x: x + 82.5, y: 60.5, width: 35, height: 35), color: .white, opticalFit: true, pose: pose)
            let text = String(format: "%.2f s", t * BrandIcon.wiggleDuration)
            text.draw(at: NSPoint(x: x + 70, y: 18), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(white: 0.4, alpha: 1)
            ])
        }
        NSGraphicsContext.restoreGraphicsState()
        try sheet.representation(using: .png, properties: [:])!.write(to: output.appending(path: "bilby-motion.png"))
        print("32 motion frames passed: no clipping, stationary face, exact return to rest")
    }
}
