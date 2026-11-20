// 앱 아이콘(어두운 바탕 + 메뉴 막대와 같은 칩: 둥근 테두리 · 변마다 핀 3개 · 초록 안쪽)을 그려 packaging/AppIcon.icns 를 만듦
//   swiftc -o /tmp/make-icon packaging/make-icon.swift -framework AppKit && /tmp/make-icon packaging
import AppKit

let rgb = { (r: CGFloat, g: CGFloat, b: CGFloat) in NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

/// 1024 기준 좌표로 그림
func draw(size px: Int) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let ctx = NSGraphicsContext.current!.cgContext
  ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

  // 바탕(macOS 아이콘 격자: 824 네모, 둥근 정도 185)
  let base = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
  NSGraphicsContext.saveGraphicsState()
  let sh = NSShadow(); sh.shadowColor = .black.withAlphaComponent(0.3); sh.shadowBlurRadius = 20; sh.shadowOffset = NSSize(width: 0, height: -8); sh.set()
  rgb(30, 33, 39).setFill(); base.fill()
  NSGraphicsContext.restoreGraphicsState()
  NSGradient(starting: rgb(46, 50, 58), ending: rgb(18, 20, 24))!.draw(in: base, angle: -90)

  // 칩 — 메뉴 막대 아이콘(44 단위)을 12배로
  let k: CGFloat = 12, ox: CGFloat = 512 - 22 * k, oy: CGFloat = 512 - 22 * k
  func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: ox + x * k, y: oy + y * k, width: w * k, height: h * k) }
  let fg = rgb(236, 238, 242)
  // 안쪽 초록 네모 + 은은한 빛
  let green = rgb(48, 209, 88)
  NSGraphicsContext.saveGraphicsState()
  let glow = NSShadow(); glow.shadowColor = green.withAlphaComponent(0.55); glow.shadowBlurRadius = 70; glow.set()
  let inner = NSBezierPath(roundedRect: r(12.6, 12.6, 18.8, 18.8), xRadius: 3.6 * k, yRadius: 3.6 * k)
  green.setFill(); inner.fill()
  NSGraphicsContext.restoreGraphicsState()
  NSGradient(starting: rgb(88, 230, 120), ending: rgb(36, 186, 74))!.draw(in: inner, angle: -90)
  // 테두리
  let body = NSBezierPath(roundedRect: r(8, 8, 28, 28), xRadius: 6 * k, yRadius: 6 * k)
  body.lineWidth = 3.2 * k
  fg.setStroke(); body.stroke()
  // 핀: 변마다 3개
  fg.setFill()
  for c: CGFloat in [15, 22, 29] {
    for rect in [r(c - 1.5, 1.2, 3, 6.2), r(c - 1.5, 36.6, 3, 6.2), r(1.2, c - 1.5, 6.2, 3), r(36.6, c - 1.5, 6.2, 3)] {
      NSBezierPath(roundedRect: rect, xRadius: 1.5 * k, yRadius: 1.5 * k).fill()
    }
  }
  _ = ctx
  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! draw(size: base * scale).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent(name))
  }
}
try! draw(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent("AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", URL(fileURLWithPath: out).appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
print("만듦: \(out)/AppIcon.icns")
