#!/usr/bin/env swift
// Generates AppIcon.iconset/ with all required macOS icon sizes,
// then you run: iconutil -c icns AppIcon.iconset
import Foundation
import CoreGraphics
import ImageIO

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let configs: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func makeIcon(size: Int, filename: String) {
    let s  = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        print("Failed context for \(filename)"); return
    }

    // --- Clip to rounded-rect so the background has macOS-style corners ---
    let corner  = s * 0.22
    let bgPath  = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                         cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // --- Diagonal dark-blue → dark-purple gradient background ---
    let c1 = CGColor(colorSpace: cs, components: [0.08, 0.12, 0.45, 1.0])!
    let c2 = CGColor(colorSpace: cs, components: [0.22, 0.08, 0.55, 1.0])!
    if let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray,
                             locations: [0.0, 1.0] as [CGFloat]) {
        // top-left → bottom-right (CGContext origin is bottom-left)
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: 0, y: s),
                               end:   CGPoint(x: s, y: 0),
                               options: [])
    }

    // --- Two "space" panels ---
    let panelW  = s * 0.27
    let panelH  = s * 0.37
    let panelY  = (s - panelH) / 2.0
    let gap     = s * 0.055
    let arrowW  = s * 0.12
    let totalW  = panelW * 2 + gap * 2 + arrowW
    let leftX   = (s - totalW) / 2.0
    let rightX  = leftX + panelW + gap + arrowW + gap
    let pr      = max(1.0, s * 0.03)

    // Left panel — dim (current space)
    let lp = CGPath(roundedRect: CGRect(x: leftX, y: panelY, width: panelW, height: panelH),
                    cornerWidth: pr, cornerHeight: pr, transform: nil)
    ctx.setFillColor(CGColor(colorSpace: cs, components:   [1, 1, 1, 0.18])!)
    ctx.addPath(lp); ctx.fillPath()
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [1, 1, 1, 0.45])!)
    ctx.setLineWidth(max(1.0, s * 0.012))
    ctx.addPath(lp); ctx.strokePath()

    // Right panel — bright (destination space)
    let rp = CGPath(roundedRect: CGRect(x: rightX, y: panelY, width: panelW, height: panelH),
                    cornerWidth: pr, cornerHeight: pr, transform: nil)
    ctx.setFillColor(CGColor(colorSpace: cs, components:   [1, 1, 1, 0.50])!)
    ctx.addPath(rp); ctx.fillPath()
    ctx.setStrokeColor(CGColor(colorSpace: cs, components: [0.40, 0.85, 1.0, 1.0])!)
    ctx.setLineWidth(max(1.0, s * 0.018))
    ctx.addPath(rp); ctx.strokePath()

    // --- Arrow pointing right ---
    let ax1 = leftX  + panelW + gap * 0.25
    let ax2 = rightX - gap * 0.25
    let cy  = s / 2.0
    let hw  = s * 0.075   // arrow head depth (along X)
    let hh  = s * 0.065   // arrow head half-height
    let sh  = s * 0.022   // shaft half-height

    let ap = CGMutablePath()
    ap.move    (to: .init(x: ax1,      y: cy - sh))
    ap.addLine (to: .init(x: ax2 - hw, y: cy - sh))
    ap.addLine (to: .init(x: ax2 - hw, y: cy - hh))
    ap.addLine (to: .init(x: ax2,      y: cy))
    ap.addLine (to: .init(x: ax2 - hw, y: cy + hh))
    ap.addLine (to: .init(x: ax2 - hw, y: cy + sh))
    ap.addLine (to: .init(x: ax1,      y: cy + sh))
    ap.closeSubpath()
    ctx.setFillColor(CGColor(colorSpace: cs, components: [0.38, 0.82, 1.0, 1.0])!)
    ctx.addPath(ap); ctx.fillPath()

    // --- Save as PNG ---
    guard let cgImage = ctx.makeImage() else { print("Failed image for \(filename)"); return }
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(filename)")
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        print("Failed dest for \(filename)"); return
    }
    CGImageDestinationAddImage(dest, cgImage, nil)
    if CGImageDestinationFinalize(dest) {
        print("  \(url.lastPathComponent)")
    } else {
        print("Failed to save \(filename)")
    }
}

print("Generating icon sizes...")
for (size, filename) in configs {
    makeIcon(size: size, filename: filename)
}
print("Done.")
