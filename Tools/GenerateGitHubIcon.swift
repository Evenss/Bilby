import AppKit

// Convert the upstream SVG to a PDF vector resource for SwiftUI's template
// rendering. Keep the source paths intact; resolve currentColor to black.
guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: GenerateGitHubIcon.swift input.svg output.pdf")
}
let source = URL(filePath: CommandLine.arguments[1])
let destination = URL(filePath: CommandLine.arguments[2])
let svg = try String(contentsOf: source, encoding: .utf8)
    .replacingOccurrences(of: "currentColor", with: "#000000")
guard let image = NSImage(data: Data(svg.utf8)) else {
    fatalError("Unable to decode the GitHub SVG")
}
let data = NSMutableData()
var bounds = CGRect(origin: .zero, size: image.size)
guard let consumer = CGDataConsumer(data: data),
      let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
    fatalError("Unable to create the PDF context")
}
context.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
image.draw(in: bounds)
NSGraphicsContext.restoreGraphicsState()
context.endPDFPage()
context.closePDF()
try (data as Data).write(to: destination)
