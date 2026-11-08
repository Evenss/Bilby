import AppKit

/// The peeking Bilby mark, with optical sizing for the menu bar.
enum BrandIcon {
    static let name = "Bilby"
    static let menuBarCanvas: CGFloat = 20
    static let menuBarInk: CGFloat = 17.5

    struct EarPose: Sendable {
        var left: CGFloat = 0
        var right: CGFloat = 0
        static let resting = EarPose()
    }

    static let wiggleDuration: Double = 0.52

    static func earPose(at progress: Double) -> EarPose {
        let keys: [(Double, EarPose)] = [
            (0, .resting), (0.20, EarPose(left: -10, right: 8)),
            (0.46, EarPose(left: 7, right: -6)),
            (0.70, EarPose(left: -3, right: 2.5)), (1, .resting)
        ]
        let t = min(1, max(0, progress))
        for index in 1..<keys.count where t <= keys[index].0 {
            let a = keys[index - 1], b = keys[index]
            let fraction = (t - a.0) / (b.0 - a.0)
            let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
            return EarPose(left: a.1.left + (b.1.left - a.1.left) * eased,
                           right: a.1.right + (b.1.right - a.1.right) * eased)
        }
        return .resting
    }

    static func menuBarImage(pose: EarPose = .resting) -> NSImage {
        let image = NSImage(size: NSSize(width: menuBarCanvas, height: menuBarCanvas), flipped: false) { rect in
            draw(in: rect.insetBy(dx: (menuBarCanvas - menuBarInk) / 2,
                                 dy: (menuBarCanvas - menuBarInk) / 2),
                 color: .black, opticalFit: true, pose: pose)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Shared by AppKit drawing and the editable SVG export.
    static let headData = "M17 85C15 85 16 78 19 71C22 65 25 63 24 60C31 51 43 46 54 46C67 45 78 55 85 66C90 74 92 81 91 85H87C86 85 87 81 85 79C84 77 83 77 81 76C81 69 77 64 73 64C67 63 63 70 59 80C58.7 81 58 81 57.5 80C53 71 47 64 41 64C34 64 29 70 29 76C25 77 23 81 23 85Z"
    static let leftEarData = "M25 63C16 58 7 49 5.5 39C3.2 30 6 25 13 25C27 24 42 34 47.5 47.5C49 51 49 54 47 57C41 60 33 63 25 63Z"
    static let rightEarData = "M60 48C57 35 65 20 77 13C86 7.5 92 13 94 23C98 38 89 51 79 60C75 63 69 61 65 57C62 53 61 50 60 48Z"
    static let leftEarCutout = "M17 34C12.5 33.5 14.5 43 22.5 50.5C27 54.5 32.5 57.3 35.3 55.8C40.3 53.3 33.5 42.5 26.2 37.8C22.5 35.5 19 34.2 17 34Z"
    static let rightEarCutout = "M73 56C68 53 66.2 47.1 68.2 39C70.5 29.5 77.5 22.4 84.2 21.8C87.7 21.5 88.4 29.2 86 37.2C83.7 45.1 78.4 52.8 73 56Z"
    private static let leftEarPivot = NSPoint(x: 39, y: 55)
    private static let rightEarPivot = NSPoint(x: 69, y: 53)

    static var svg: String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img" aria-label="Bilby">
          <defs>
            <clipPath id="bilby-ear-cutouts" clipPathUnits="userSpaceOnUse">
              <path clip-rule="evenodd" d="M0 0H100V100H0Z \(leftEarCutout) \(rightEarCutout)"/>
            </clipPath>
          </defs>
          <g fill="currentColor" clip-path="url(#bilby-ear-cutouts)">
            <path d="\(leftEarData)"/>
            <path d="\(rightEarData)"/>
            <path d="\(headData)"/>
          </g>
          <ellipse fill="currentColor" cx="44.3" cy="77.2" rx="4.1" ry="4.7"/>
          <ellipse fill="currentColor" cx="72" cy="77.2" rx="4" ry="4.7"/>
        </svg>
        """
    }

    static func draw(in rect: NSRect, color: NSColor, opticalFit: Bool = false, pose: EarPose = .resting) {
        let head = path(headData)
        let left = path(leftEarData)
        let right = path(rightEarData)
        // Fit every frame to the neutral outline so the face never shifts or
        // changes size while the ears move.
        let source = opticalFit ? head.bounds.union(left.bounds).union(right.bounds) : NSRect(x: 0, y: 0, width: 100, height: 100)
        let scale = min(rect.width / source.width, rect.height / source.height)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scaleX(by: scale, yBy: -scale)
        transform.translateX(by: -source.midX, yBy: -source.midY)
        transform.concat()
        turn(left, about: leftEarPivot, degrees: pose.left)
        turn(right, about: rightEarPivot, degrees: pose.right)
        let leftHole = path(leftEarCutout)
        let rightHole = path(rightEarCutout)
        turn(leftHole, about: leftEarPivot, degrees: pose.left)
        turn(rightHole, about: rightEarPivot, degrees: pose.right)
        // Clip holes out of the whole silhouette, including overlapping ear
        // roots. Transparent cutouts also preserve the app icon's white tile.
        let clip = NSBezierPath(rect: NSRect(x: -50, y: -50, width: 200, height: 200))
        clip.append(leftHole)
        clip.append(rightHole)
        clip.windingRule = .evenOdd
        clip.addClip()
        color.setFill()
        left.fill()
        right.fill()
        head.fill()
        eye(center: NSPoint(x: 44.3, y: 77.2), radius: NSSize(width: 4.1, height: 4.7), angle: 0).fill()
        eye(center: NSPoint(x: 72, y: 77.2), radius: NSSize(width: 4, height: 4.7), angle: 0).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func turn(_ shape: NSBezierPath, about pivot: NSPoint, degrees: CGFloat) {
        var transform = AffineTransform()
        transform.translate(x: pivot.x, y: pivot.y)
        transform.rotate(byDegrees: degrees)
        transform.translate(x: -pivot.x, y: -pivot.y)
        shape.transform(using: transform)
    }

    private static func eye(center: NSPoint, radius: NSSize, angle: CGFloat) -> NSBezierPath {
        let shape = NSBezierPath(ovalIn: NSRect(x: -radius.width, y: -radius.height,
                                              width: radius.width * 2, height: radius.height * 2))
        var transform = AffineTransform()
        transform.translate(x: center.x, y: center.y)
        transform.rotate(byDegrees: angle)
        shape.transform(using: transform)
        return shape
    }

    /// Our artwork uses just M, C, H and Z, not a general-purpose SVG importer.
    /// Sharing these coordinates keeps SVG, app icon and menu glyph identical.
    private static func path(_ data: String) -> NSBezierPath {
        let tokens = data.replacingOccurrences(of: "([MCHZ])", with: " $1 ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).map(String.init)
        var index = 0
        let shape = NSBezierPath()
        func value() -> CGFloat {
            defer { index += 1 }
            return CGFloat(Double(tokens[index])!)
        }
        while index < tokens.count {
            let command = tokens[index]
            index += 1
            switch command {
            case "M": shape.move(to: NSPoint(x: value(), y: value()))
            case "C":
                let a = NSPoint(x: value(), y: value())
                let b = NSPoint(x: value(), y: value())
                shape.curve(to: NSPoint(x: value(), y: value()), controlPoint1: a, controlPoint2: b)
            case "H": shape.line(to: NSPoint(x: value(), y: shape.currentPoint.y))
            case "Z": shape.close()
            default: preconditionFailure("Unsupported brand path command")
            }
        }
        return shape
    }
}
