import AppKit

/// 메뉴 막대 아이콘 옆 숫자
enum NumberMode: String, CaseIterable, Identifiable {
  case none, max, all
  var id: String { rawValue }
  var label: String {
    switch self { case .none: "없음"; case .max: "가장 높은 값"; case .all: "셋 다" }
  }
}

extension NSColor {
  static let humGreen = NSColor(srgbRed: 0x30 / 255.0, green: 0xd1 / 255.0, blue: 0x58 / 255.0, alpha: 1)   // #30d158
  static let humOrange = NSColor(srgbRed: 1.0, green: 0x9f / 255.0, blue: 0x0a / 255.0, alpha: 1)             // #ff9f0a
  static let humRed = NSColor(srgbRed: 1.0, green: 0x45 / 255.0, blue: 0x3a / 255.0, alpha: 1)                // #ff453a
}

/// 메뉴 막대용 칩 아이콘. 좌표는 44×44 기준을 22pt로 줄여 그림
enum ChipIcon {
  /// 「바쁜 정도」 0~100 — CPU·GPU 중 큰 값
  static func busyness(_ s: Snapshot) -> Double { min(max(s.cpu, s.gpu ?? 0), 100) }

  /// 바쁜 정도 → 색. 0~50 초록, 75 주황, 92 이상 빨강 — 사이는 섞음
  static func statusColor(_ v: Double) -> NSColor {
    let stops: [(Double, NSColor)] = [(0, .humGreen), (50, .humGreen), (75, .humOrange), (92, .humRed)]
    for (a, b) in zip(stops, stops.dropFirst()) where v <= b.0 {
      return hueBlend(a.1, b.1, max(0, (v - a.0) / (b.0 - a.0)))
    }
    return stops.last!.1
  }

  /// 색상환을 따라 섞음(RGB로 섞으면 초록과 주황 사이가 칙칙한 올리브색이 됨)
  private static func hueBlend(_ x: NSColor, _ y: NSColor, _ t: Double) -> NSColor {
    guard let x = x.usingColorSpace(.sRGB), let y = y.usingColorSpace(.sRGB) else { return y }
    let mix = { (p: CGFloat, q: CGFloat) in p + (q - p) * t }
    return NSColor(hue: mix(x.hueComponent, y.hueComponent), saturation: mix(x.saturationComponent, y.saturationComponent),
                   brightness: mix(x.brightnessComponent, y.brightnessComponent), alpha: 1)
  }

  /// 칩 아이콘. 테두리·핀(변마다 3개, 끝 둥글게)은 글자색, 안쪽 네모는 바쁜 정도 색
  /// (깜빡이게도 해 봤는데 정신없어서 색만 띄워 둠)
  static func chipImage(busy: Double) -> NSImage {
    let color = statusColor(busy)
    return NSImage(size: NSSize(width: 22, height: 22), flipped: true) { _ in
      guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
      let fg = NSColor.labelColor   // 그릴 때 밝음·어두움에 맞춰 정해짐
      ctx.scaleBy(x: 0.5, y: 0.5)
      ctx.setStrokeColor(fg.cgColor)
      ctx.setLineWidth(3.2)
      ctx.addPath(CGPath(roundedRect: CGRect(x: 8, y: 8, width: 28, height: 28), cornerWidth: 6, cornerHeight: 6, transform: nil))
      ctx.strokePath()
      for c in [15.0, 22, 29] {
        fill(ctx, CGRect(x: c - 1.5, y: 1.2, width: 3, height: 6.2), radius: 1.5, fg)
        fill(ctx, CGRect(x: c - 1.5, y: 36.6, width: 3, height: 6.2), radius: 1.5, fg)
        fill(ctx, CGRect(x: 1.2, y: c - 1.5, width: 6.2, height: 3), radius: 1.5, fg)
        fill(ctx, CGRect(x: 36.6, y: c - 1.5, width: 6.2, height: 3), radius: 1.5, fg)
      }
      fill(ctx, CGRect(x: 12.6, y: 12.6, width: 18.8, height: 18.8), radius: 3.6, color)
      return true
    }
  }

  private static func fill(_ ctx: CGContext, _ r: CGRect, radius: Double, _ color: NSColor) {
    ctx.setFillColor(color.cgColor)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
  }
}
