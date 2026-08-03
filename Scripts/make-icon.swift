#!/usr/bin/env swift
//
// Renders the app icon and packs it into Resources/AppIcon.icns.
//
//   swift Scripts/make-icon.swift
//
// Drawn in code rather than shipped as a binary asset so it stays editable, stays
// in step with the tiles it depicts, and needs no image editor. The design is the
// app's own subject matter: three rounded-square notes on a dark plate, tinted
// green / amber / red to show the traffic-light ageing at a glance.
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

    // Backing plate: a deep slate so the coloured notes read at 16pt.
    let platePath = NSBezierPath(roundedRect: plate, xRadius: plateRadius, yRadius: plateRadius)
    NSGradient(
        colors: [
            NSColor(calibratedWhite: 0.20, alpha: 1),
            NSColor(calibratedWhite: 0.09, alpha: 1)
        ]
    )?.draw(in: platePath, angle: -90)

    // Rim light along the top edge, matching the tiles' glass treatment.
    platePath.lineWidth = max(size * 0.005, 0.5)
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    platePath.stroke()

    // Three notes, largest first — the same left-to-right ageing the grid shows.
    struct Note {
        let frame: CGRect
        let progress: Double
    }

    let unit = plate.width
    let notes = [
        // Big fresh note, upper left.
        Note(
            frame: CGRect(
                x: plate.minX + unit * 0.13,
                y: plate.minY + unit * 0.40,
                width: unit * 0.44,
                height: unit * 0.44
            ),
            progress: 0.0
        ),
        // Ageing note, right.
        Note(
            frame: CGRect(
                x: plate.minX + unit * 0.61,
                y: plate.minY + unit * 0.47,
                width: unit * 0.30,
                height: unit * 0.30
            ),
            progress: 0.52
        ),
        // Overdue note, lower middle.
        Note(
            frame: CGRect(
                x: plate.minX + unit * 0.28,
                y: plate.minY + unit * 0.13,
                width: unit * 0.36,
                height: unit * 0.36
            ),
            progress: 1.0
        )
    ]

    for note in notes {
        let radius = note.frame.width * TileCornerRatio
        let path = NSBezierPath(roundedRect: note.frame, xRadius: radius, yRadius: radius)

        // Drop shadow so the notes lift off the plate.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = size * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
        shadow.set()

        NSGradient(
            colors: [
                agingColour(progress: note.progress),
                agingColour(progress: note.progress, saturation: 0.88, brightness: 0.66)
            ]
        )?.draw(in: path, angle: -55)
        NSGraphicsContext.restoreGraphicsState()

        // Specular highlight across the top of each note.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let gloss = NSRect(
            x: note.frame.minX,
            y: note.frame.midY,
            width: note.frame.width,
            height: note.frame.height / 2
        )
        NSGradient(
            colors: [
                NSColor.white.withAlphaComponent(0.34),
                NSColor.white.withAlphaComponent(0.0)
            ]
        )?.draw(in: gloss, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // Rim.
        path.lineWidth = max(size * 0.004, 0.4)
        NSColor.white.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }
}

/// Kept in step with `TileStyle.cornerRatio` in the app.
let TileCornerRatio: CGFloat = 0.26

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
