#!/usr/bin/env swift
// Generates the 1024×1024 app-icon source.
// Usage:  swift tools/make_icon.swift <out.png>
//
// The icon is generated at install time into a temp dir and thrown away
// afterwards — nothing image-shaped is kept in the repo.

import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-source.png"
let side: CGFloat = 1024

guard let ctx = CGContext(
    data: nil, width: Int(side), height: Int(side),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Cannot create CGContext") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

// ── Squircle background: deep night green ─────────────────────────────────
let squircle = NSBezierPath(
    roundedRect: NSRect(x: 32, y: 32, width: side - 64, height: side - 64),
    xRadius: 220, yRadius: 220
)
squircle.addClip()

guard let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.04, green: 0.16, blue: 0.12, alpha: 1),
        CGColor(red: 0.01, green: 0.06, blue: 0.05, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
) else { fatalError("gradient") }

ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: side / 2, y: side),
                       end:   CGPoint(x: side / 2, y: 0),
                       options: [])

// ── Soft green halo behind the glyph ──────────────────────────────────────
if let halo = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 0.28),
        CGColor(red: 0.30, green: 0.90, blue: 0.45, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
) {
    ctx.drawRadialGradient(halo,
                           startCenter: CGPoint(x: side / 2, y: side / 2), startRadius: 0,
                           endCenter:   CGPoint(x: side / 2, y: side / 2), endRadius: 430,
                           options: [])
}

// ── Battery glyph ─────────────────────────────────────────────────────────
let cfg = NSImage.SymbolConfiguration(pointSize: 500, weight: .semibold)
guard let symbol = NSImage(systemSymbolName: "bolt.batteryblock.fill",
                           accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
else { fatalError("SF Symbol unavailable") }

let tinted = NSImage(size: symbol.size, flipped: false) { rect in
    symbol.draw(in: rect)
    NSColor(red: 0.42, green: 0.93, blue: 0.52, alpha: 1).set()
    rect.fill(using: .sourceAtop)
    return true
}

let glyphRect = NSRect(
    x: (side - tinted.size.width) / 2,
    y: (side - tinted.size.height) / 2,
    width: tinted.size.width,
    height: tinted.size.height
)
tinted.draw(in: glyphRect)

NSGraphicsContext.restoreGraphicsState()

// ── Export ────────────────────────────────────────────────────────────────
guard
    let cgImage = ctx.makeImage(),
    let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
else { fatalError("PNG conversion failed") }

try! png.write(to: URL(fileURLWithPath: outPath))
print("   ✓ icon source → \(outPath)")
