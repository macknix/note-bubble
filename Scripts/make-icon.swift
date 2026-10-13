#!/usr/bin/env swift
//
// Renders the app icon and packs it into Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift
//
// Drawn in code rather than shipped as a binary asset so it stays editable, stays
// in step with the app, and needs no image editor. The design is the app's name:
// three glass bubbles of different sizes on a night-sky plate, each lit from the
// top left with a curved reflection so they read as spheres, and tinted green /
// amber / red for the traffic-light ageing.
//
// Requires `iconutil` (Command Line Tools). No Xcode needed.

import AppKit
import Foundation

// MARK: - Palette
//
// Mirrors Aging.color: hue sweeps 0.33 (green) to 0.0 (red) across the week.

func agingColour(progress: Double, saturation: Double = 0.72, brightness: Double = 0.94) -> NSColor {
    NSColor(hue: 0.33 * (1 - progress), saturation: saturation, brightness: brightness, alpha: 1)
}

// MARK: - Drawing

/// Draws the icon at `size` × `size` points into the current graphics context.
func drawIcon(size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    // macOS icons leave a margin; content sits in the middle ~82%.
    let inset = size * 0.09
    let plate = rect.insetBy(dx: inset, dy: inset)
    let plateRadius = plate.width * 0.2237 // Apple's continuous-corner proportion

    // Backing plate: a deep night-sky blue, so glass bubbles have something to
    // catch the light against — the app's tiles float over your desktop the same way.
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)
    NSGradient(
        colors: [
            NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.36, alpha: 1),
            NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.15, alpha: 1)
        ]
    )?.draw(in: platePath, angle: -90)

    // Rim light along the edge, matching the bar's glass.
    platePath.lineWidth = max(size * 0.005, 0.5)
    NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
    platePath.stroke()

    // Three bubbles of different sizes, tinted by the traffic light they stand
    // for. Drawn back to front. The menu bar icon (`MenuBarIcon.swift`) uses the
    // same arrangement — keep the two in step.
    let unit = plate.width
    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: plate.minX + unit * x, y: plate.minY + unit * y)
    }
    drawBubble(centre: at(0.74, 0.70), radius: unit * 0.17, progress: 0.62, size: size) // ageing
    drawBubble(centre: at(0.76, 0.28), radius: unit * 0.11, progress: 1.0, size: size)  // overdue
    drawBubble(centre: at(0.40, 0.42), radius: unit * 0.27, progress: 0.0, size: size)  // fresh
}

/// One glass bubble: a tinted sphere lit from the top left, with a bright curved
/// reflection, a pin-point highlight, and a faint bounce of light opposite.
func drawBubble(centre: CGPoint, radius r: CGFloat, progress: Double, size: CGFloat) {
    let circle = NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))

    // Lift off the plate.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    shadow.set()
    agingColour(progress: progress, saturation: 0.85, brightness: 0.45).setFill()
    circle.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The sphere: bright and pale where the light hits, deep at the far edge.
    NSGradient(
        colors: [
            agingColour(progress: progress, saturation: 0.30, brightness: 1.0),
            agingColour(progress: progress, saturation: 0.72, brightness: 0.92),
            agingColour(progress: progress, saturation: 0.92, brightness: 0.52)
        ],
        atLocations: [0, 0.5, 1],
        colorSpace: .deviceRGB
    )?.draw(in: circle, relativeCenterPosition: NSPoint(x: -0.4, y: 0.42))

    // A soap film's edge: brighter at the rim, so it reads as a shell, not a ball.
    NSGraphicsContext.saveGraphicsState()
    circle.addClip()
    let rim = NSBezierPath(ovalIn: NSRect(x: centre.x - r, y: centre.y - r, width: 2 * r, height: 2 * r))
    rim.lineWidth = r * 0.12
    NSColor(calibratedWhite: 1, alpha: 0.30).setStroke()
    rim.stroke()
    NSGraphicsContext.restoreGraphicsState()

    func arc(from start: CGFloat, to end: CGFloat, at fraction: CGFloat, width: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: centre, radius: r * fraction, startAngle: start, endAngle: end)
        path.lineWidth = r * width
        path.lineCapStyle = .round
        NSColor(calibratedWhite: 1, alpha: alpha).setStroke()
        path.stroke()
    }

    // The reflection: a curved streak of window-light across the upper left…
    arc(from: 112, to: 162, at: 0.70, width: 0.13, alpha: 0.92)
    // …a pin-point glint just beyond it…
    let glint = r * 0.085
    let glintAngle = 96 * CGFloat.pi / 180
    let glintCentre = CGPoint(x: centre.x + cos(glintAngle) * r * 0.70, y: centre.y + sin(glintAngle) * r * 0.70)
    NSColor(calibratedWhite: 1, alpha: 0.95).setFill()
    NSBezierPath(ovalIn: NSRect(x: glintCentre.x - glint, y: glintCentre.y - glint, width: 2 * glint, height: 2 * glint)).fill()
    // …and light bouncing back off the far side.
    arc(from: -62, to: -18, at: 0.78, width: 0.07, alpha: 0.38)
}

// MARK: - Rasterising

func renderPNG(size: Int) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("could not create bitmap at \(size)px")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    drawIcon(size: CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode PNG at \(size)px")
    }
    return data
}

// MARK: - Main

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// The exact set `iconutil` expects.
let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

for variant in variants {
    let url = iconset.appendingPathComponent("\(variant.name).png")
    try renderPNG(size: variant.pixels).write(to: url)
}
print("rendered \(variants.count) sizes")

let icns = resources.appendingPathComponent("AppIcon.icns")
let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try convert.run()
convert.waitUntilExit()

guard convert.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}

// The .iconset is an intermediate; the .icns is what ships.
try? FileManager.default.removeItem(at: iconset)
print("wrote Resources/AppIcon.icns")
