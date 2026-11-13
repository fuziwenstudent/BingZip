#!/usr/bin/env swift
// Generates the BingZip app icon (icns) using CoreGraphics.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

// Background rounded rect with blue gradient
let rect = CGRect(x: 48, y: 48, width: 928, height: 928)
let path = CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [
    CGColor(red: 0.16, green: 0.47, blue: 0.98, alpha: 1.0),
    CGColor(red: 0.03, green: 0.16, blue: 0.56, alpha: 1.0)
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: 512, y: 976),
                       end: CGPoint(x: 512, y: 48), options: [])

// White "B"
let nsctx = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let font = NSFont.systemFont(ofSize: 540, weight: .heavy)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white
]
let str = NSAttributedString(string: "B", attributes: attrs)
let strSize = str.size()
str.draw(at: NSPoint(x: (1024 - strSize.width) / 2, y: (1024 - strSize.height) / 2 + 10))

// Zipper line: a dashed white line across the lower part
NSColor.white.withAlphaComponent(0.9).setStroke()
let zipper = NSBezierPath()
zipper.move(to: NSPoint(x: 330, y: 250))
zipper.line(to: NSPoint(x: 694, y: 250))
zipper.lineWidth = 26
zipper.lineCapStyle = .round
zipper.setLineDash([34, 26], count: 2, phase: 0)
zipper.stroke()

// Small teeth
let teeth = NSBezierPath()
teeth.lineWidth = 12
teeth.lineCapStyle = .round
for i in 0..<7 {
    let x = 340.0 + CGFloat(i) * 56
    teeth.move(to: NSPoint(x: x, y: 226))
    teeth.line(to: NSPoint(x: x, y: 274))
}
teeth.stroke()
NSGraphicsContext.restoreGraphicsState()

guard let image = ctx.makeImage() else { fatalError("no image") }
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/bingzip_icon.png")
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print(out.path)