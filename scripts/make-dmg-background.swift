#!/usr/bin/env swift
//
// Draws the backdrop of the disk image window: a title, an arrow, and a line
// saying the one thing people get wrong.
//
//   swift scripts/make-dmg-background.swift
//
// Run it when the design changes, then re-run scripts/make-dmg-layout.sh, which
// is what turns these into the window Finder actually opens. Committed as
// pixels because a .dmg cannot run code — but drawn here rather than exported
// from a design tool, for the same reason Mochi is: the source of a picture in
// this repository is the code that makes it.
import AppKit

let W: CGFloat = 660, H: CGFloat = 400

// The site's dark palette (docs/site.css), because a disk image background does
// not follow the system appearance and this is the app's own colouring.
let ink    = NSColor(srgbRed: 0.953, green: 0.957, blue: 0.965, alpha: 1)  // #f3f4f6
let dim    = NSColor(srgbRed: 0.631, green: 0.651, blue: 0.690, alpha: 1)  // #a1a6b0
let accent = NSColor(srgbRed: 0.541, green: 0.706, blue: 1.000, alpha: 1)  // #8ab4ff
let top    = NSColor(srgbRed: 0.078, green: 0.082, blue: 0.102, alpha: 1)  // #14151a
let bottom = NSColor(srgbRed: 0.055, green: 0.059, blue: 0.071, alpha: 1)  // #0e0f12

/// Where Finder is told to put the two icons (see make-dmg-layout.sh). Measured
/// from the top left, which is also how this image is drawn, so the arrow
/// between them only lines up as long as the two files agree.
let appIcon  = CGPoint(x: 165, y: 205)
let appsIcon = CGPoint(x: 495, y: 205)

func text(_ s: String, _ font: NSFont, _ colour: NSColor, centredAt y: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
    let size = s.size(withAttributes: attrs)
    s.draw(at: NSPoint(x: (W - size.width) / 2, y: H - y - size.height / 2), withAttributes: attrs)
}

func render(scale: CGFloat, to path: String) {
    let pw = Int(W * scale), ph = Int(H * scale)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                     isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else {
        FileHandle.standardError.write(Data("could not make a bitmap\n".utf8)); exit(1)
    }
    rep.size = NSSize(width: W, height: H)   // points, so drawing below is in points
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

    NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: 0, y: 0, width: W, height: H),
                                                    angle: -90)

    text("Notchy", .systemFont(ofSize: 30, weight: .semibold), ink, centredAt: 62)
    text("Drag it into Applications", .systemFont(ofSize: 14, weight: .regular), dim, centredAt: 98)

    // The arrow, in the gap between the two 128-point icons.
    let y = H - appIcon.y
    let x0 = appIcon.x + 88, x1 = appsIcon.x - 88
    ctx.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: x0, y: y))
    ctx.addLine(to: CGPoint(x: x1 - 12, y: y))
    ctx.strokePath()
    ctx.setFillColor(accent.withAlphaComponent(0.85).cgColor)
    ctx.move(to: CGPoint(x: x1, y: y))
    ctx.addLine(to: CGPoint(x: x1 - 16, y: y + 9))
    ctx.addLine(to: CGPoint(x: x1 - 16, y: y - 9))
    ctx.closePath()
    ctx.fillPath()

    // The mistake this window exists to prevent, said where it is made.
    text("Then open it from Applications — not from this window.",
         .systemFont(ofSize: 12, weight: .regular), dim.withAlphaComponent(0.85), centredAt: 348)

    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    do { try png.write(to: URL(fileURLWithPath: path)) }
    catch { FileHandle.standardError.write(Data("could not write \(path): \(error)\n".utf8)); exit(1) }
    print("  \(path)  \(pw)×\(ph)")
}

let dir = FileManager.default.currentDirectoryPath + "/design/dmg"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
print("")
render(scale: 1, to: dir + "/background.png")
render(scale: 2, to: dir + "/background@2x.png")
print("")
