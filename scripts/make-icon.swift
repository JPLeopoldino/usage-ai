// Writes the app icon as an Icon Composer bundle (Resources/AppIcon.icon): a gauge glyph drawn
// here as SVG, over a system-generated gradient. macOS 26+ adds the Liquid Glass effects, and
// Xcode generates flat images for older macOS at build time.
// The glyph is drawn from scratch on purpose: SF Symbols may not be used in app icons.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icon
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icon")

let center = (x: 512.0, y: 584.0)

func point(_ radius: Double, _ degrees: Double) -> String {
    let angle = degrees * .pi / 180
    return String(format: "%.2f %.2f", center.x + radius * cos(angle), center.y - radius * sin(angle))
}

// An arc from the lower left, over the top, to the lower right, with round ends.
let radius = 268.0, thickness = 68.0, start = 210.0, end = -30.0
let outer = radius + thickness / 2, inner = radius - thickness / 2, cap = thickness / 2
let arc = "M\(point(outer, start)) A\(outer) \(outer) 0 1 1 \(point(outer, end)) "
    + "A\(cap) \(cap) 0 0 1 \(point(inner, end)) "
    + "A\(inner) \(inner) 0 1 0 \(point(inner, start)) "
    + "A\(cap) \(cap) 0 0 1 \(point(outer, start)) Z"

// A tapered needle pointing up and to the left, with a round hub.
let needleAngle = 132.0, length = 200.0, base = 40.0, tip = 12.0, hub = 56.0
let perpendicular = needleAngle + 90
func offset(_ from: (Double, Double), _ distance: Double, _ degrees: Double) -> String {
    let angle = degrees * .pi / 180
    return String(format: "%.2f %.2f", from.0 + distance * cos(angle), from.1 - distance * sin(angle))
}
let tipCenter = (center.x + length * cos(needleAngle * .pi / 180), center.y - length * sin(needleAngle * .pi / 180))
let needle = "M\(offset((center.x, center.y), base, perpendicular)) "
    + "L\(offset(tipCenter, tip, perpendicular)) "
    + "A\(tip) \(tip) 0 0 1 \(offset(tipCenter, tip, perpendicular + 180)) "
    + "L\(offset((center.x, center.y), base, perpendicular + 180)) Z"
let hubPath = "M\(center.x - hub) \(center.y) a\(hub) \(hub) 0 1 0 \(2 * hub) 0 a\(hub) \(hub) 0 1 0 \(-2 * hub) 0 Z"

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">\
<path fill="#FFFFFF" d="\(arc)"/><path fill="#FFFFFF" d="\(needle)"/><path fill="#FFFFFF" d="\(hubPath)"/></svg>

"""

let manifest = """
{
  "fill" : {
    "automatic-gradient" : "display-p3:0.22000,0.30000,0.86000,1.00000"
  },
  "groups" : [
    {
      "layers" : [
        {
          "image-name" : "gauge.svg",
          "name" : "gauge"
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : 0.5
      },
      "translucency" : {
        "enabled" : true,
        "value" : 0.4
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""

let assets = output.appendingPathComponent("Assets")
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try svg.write(to: assets.appendingPathComponent("gauge.svg"), atomically: true, encoding: .utf8)
try manifest.write(to: output.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("Wrote \(output.path)")
