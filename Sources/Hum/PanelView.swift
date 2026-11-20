import AppKit
import SwiftUI

/// 메뉴 막대 아이콘을 누르면 뜨는 창
struct PanelView: View {
  @ObservedObject var monitor: Monitor
  @ObservedObject var settings: Settings
  let openSettings: () -> Void
  let quit: () -> Void

  var body: some View {
    let s = monitor.snap
    let busy = ChipIcon.busyness(s)
    VStack(alignment: .leading, spacing: 10) {
      header(s, busy)
      HistoryChart(values: monitor.history, capacity: Monitor.historyLength, color: busyColor(busy))
        .frame(height: 46)
        .overlay(alignment: .topLeading) {
          Text("최근 \(historySpan)").font(.system(size: 10)).foregroundStyle(.tertiary).padding(4)
        }

      performance(s)
      storage(s)
      programs
      sleepBlockers
      footer
    }
    .padding(16)
    .frame(width: 340)
  }

  // 섹션마다 나눔 — 한 덩어리 body는 예전 컴파일러(GitHub Actions)에서 타입 검사가 너무 오래 걸림
  @ViewBuilder private func performance(_ s: Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle("성능", note: nil)
      VStack(spacing: 6) {
        Card {
          GaugeRow(symbol: "cpu", title: "CPU", value: pct(s.cpu), fraction: s.cpu / 100, color: busyColor(s.cpu),
                   details: ["사용자 \(pct(s.cpuUser)) · 시스템 \(pct(s.cpuSystem)) · 대기 \(pct(max(0, 100 - s.cpu)))"])
        }
        Card {
          GaugeRow(symbol: "memorychip", title: "메모리", value: pct(s.mem), fraction: s.mem / 100,
                   color: Color(nsColor: pressureColor(s.pressure)),
                   details: ["\(bytes(s.memUsedBytes)) / \(bytes(s.memTotalBytes)) · 압박 \(s.pressure.label) · 스왑 \(bytes(s.swapUsedBytes))",
                             "앱 \(bytes(s.memAppBytes)) · 고정 \(bytes(s.memWiredBytes)) · 압축 \(bytes(s.memCompressedBytes))"])
        }
        Card {
          GaugeRow(symbol: "square.3.layers.3d", title: "GPU", value: s.gpu.map(pct) ?? "–", fraction: (s.gpu ?? 0) / 100,
                   color: busyColor(s.gpu ?? 0), details: [s.gpu == nil ? "읽을 수 없어요" : "그래픽·머신러닝 작업"])
        }
      }

    }
  }

  @ViewBuilder private func storage(_ s: Snapshot) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle("저장 공간 · 연결", note: nil)
      VStack(spacing: 6) {
        if let free = s.diskFreeBytes, let total = s.diskTotalBytes, total > 0 {
          let used = Double(total - free) / Double(total)
          Card {
            GaugeRow(symbol: "internaldrive", title: "저장 공간", value: "\(pct(used * 100)) 사용", fraction: used,
                     color: used >= 0.9 ? Color(nsColor: .humRed) : used >= 0.8 ? Color(nsColor: .humOrange) : .blue,
                     details: ["\(diskBytes(total - free)) 사용 · \(diskBytes(free)) 남음 · 전체 \(diskBytes(total))"])
          }
        }
        if let b = s.battery {
          Card {
            GaugeRow(symbol: batterySymbol(b), title: "배터리", value: "\(b.percent)%", fraction: Double(b.percent) / 100,
                     color: b.percent <= 20 && !b.onAC ? Color(nsColor: .humRed) : Color(nsColor: .humGreen),
                     details: [batteryText(b)])
          }
        }
        Card { NetworkRow(link: s.link, down: rate(s.netIn), up: rate(s.netOut)) }
        Card {
          let hot = s.thermal == .nominal ? nil : Color(nsColor: s.thermal == .fair ? .humOrange : .humRed)
          GaugeRow(symbol: "thermometer.medium", title: "발열", value: s.thermal.label,
                   color: hot ?? Color(nsColor: .humGreen), valueColor: hot,
                   details: [s.thermal == .nominal ? "괜찮아요" : "맥이 열을 줄이려고 성능을 낮출 수 있어요"])
        }
      }

    }
  }

  @ViewBuilder private var programs: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle("많이 쓰는 프로그램", note: "내 계정 프로그램 · CPU 순")
      ListCard {
        if !monitor.detailsReady {
          Placeholder("살펴보는 중…")
        } else if monitor.topApps.isEmpty {
          Placeholder("읽을 수 있는 프로그램이 없어요")
        } else {
          ForEach(Array(monitor.topApps.enumerated()), id: \.element.id) { i, a in
            if i > 0 { Divider().padding(.leading, 34) }
            AppRow(app: a)
          }
        }
      }

    }
  }

  @ViewBuilder private var sleepBlockers: some View {
    VStack(alignment: .leading, spacing: 10) {
      SectionTitle("잠자기를 막는 프로그램", note: nil)
      ListCard {
        if monitor.blockers.isEmpty {
          Placeholder("없어요 — 맥이 알아서 잠들 수 있어요")
        } else {
          ForEach(Array(monitor.blockers.enumerated()), id: \.element.id) { i, b in
            if i > 0 { Divider().padding(.leading, 34) }
            BlockerRow(blocker: b)
          }
        }
      }

    }
  }

  @ViewBuilder private var footer: some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
      HStack {
        Button(action: openSettings) { Label("설정", systemImage: "gearshape") }
        Spacer()
        Button(action: quit) { Label("Hum 끝내기", systemImage: "power") }
      }
      .buttonStyle(.borderless)
      .font(.system(size: 12))
    }
  }

  private func header(_ s: Snapshot, _ busy: Double) -> some View {
    HStack(spacing: 12) {
      Image(nsImage: ChipIcon.chipImage(busy: busy))
        .resizable()
        .frame(width: 40, height: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(mood(busy)).font(.system(size: 15, weight: .semibold))
        Text(s.thermal == .nominal ? "CPU·GPU 중 더 바쁜 쪽 기준" : "발열 \(s.thermal.label) — 성능을 낮출 수 있어요")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Text("\(Int(busy.rounded()))%")
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(busyColor(busy))
        .contentTransition(.numericText())
        .animation(.easeOut(duration: 0.3), value: Int(busy.rounded()))
    }
  }

  private var historySpan: String {
    let sec = Int(Double(Monitor.historyLength) * settings.interval)
    return sec >= 60 ? "\(sec / 60)분" : "\(sec)초"
  }

  private func mood(_ v: Double) -> String {
    switch v {
    case ..<50: "여유로워요"
    case ..<75: "조금 바빠요"
    case ..<92: "바빠요"
    default: "아주 바빠요"
    }
  }
}

// MARK: - 조각들

private func busyColor(_ v: Double) -> Color { Color(nsColor: ChipIcon.statusColor(v)) }
private func pressureColor(_ p: Pressure) -> NSColor {
  switch p { case .normal: .humGreen; case .warn: .humOrange; case .critical: .humRed }
}
private func pct(_ v: Double) -> String { "\(Int(v.rounded()))%" }
private func bytes(_ b: UInt64) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .memory)
}
/// 저장 공간은 자릿수를 줄여 한 줄에 들어가게(100 GB 이상이면 소수점 없이)
private func diskBytes(_ b: Int64) -> String {
  let gb = Double(b) / 1e9
  if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
  return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
}
private func batterySymbol(_ b: Battery) -> String {
  if b.charging { return "battery.100percent.bolt" }
  switch b.percent { case ..<13: return "battery.0percent"; case ..<38: return "battery.25percent"
  case ..<63: return "battery.50percent"; case ..<88: return "battery.75percent"; default: return "battery.100percent" }
}
private func batteryText(_ b: Battery) -> String {
  let time = b.minutesLeft.map { m in m >= 60 ? "\(m / 60)시간 \(m % 60)분" : "\(m)분" }
  if b.charging { return "충전 중" + (time.map { " · 다 차기까지 \($0)" } ?? "") }
  if b.onAC { return "전원 연결됨" }
  return "배터리 사용 중" + (time.map { " · \($0) 남음" } ?? "")
}
private func rate(_ bps: Double) -> String {
  ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s"
}

/// 항목 하나씩 담는 카드 — 바탕을 살짝 띄우고 얇은 테두리로 서로 구분
private struct Card<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 10) { content }
      .padding(.horizontal, 12).padding(.vertical, 10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
  }
}

/// 목록(프로그램 등)을 담는 카드 — 줄 사이는 구분선
private struct ListCard<Content: View>: View {
  @ViewBuilder let content: Content
  var body: some View {
    VStack(spacing: 0) { content }
      .padding(4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
  }
}

/// 항목 아이콘 — 항목 색을 옅게 깐 둥근 네모
private struct Badge: View {
  let symbol: String
  let color: Color
  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(color)
      .frame(width: 26, height: 26)
      .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
  }
}

/// 아이콘 · 제목 · 오른쪽 값 · (막대) · 설명 줄
private struct GaugeRow: View {
  let symbol: String
  let title: String
  let value: String
  var fraction: Double? = nil
  var color: Color = .accentColor
  var valueColor: Color? = nil
  var details: [String] = []

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Badge(symbol: symbol, color: color)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(title).font(.system(size: 13, weight: .semibold))
          Spacer()
          Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            .foregroundStyle(valueColor ?? .primary)
        }
        if let fraction {
          // 애니메이션은 막대 길이에만 — 바깥에 걸면 창 높이가 바뀔 때 막대 위치까지 미끄러져 글자 위로 지나감
          Capsule().fill(Color.primary.opacity(0.08))
            .frame(height: 6)
            .overlay(alignment: .leading) {
              GeometryReader { g in
                Capsule().fill(color)
                  .animation(.easeOut(duration: 0.4)) {
                    $0.frame(width: max(5, g.size.width * min(max(fraction, 0), 1)))
                  }
              }
            }
        }
        ForEach(details, id: \.self) {
          Text($0).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
        }
      }
    }
  }
}

/// 네트워크: 연결 종류 · 내부 IP(누르면 복사) · 받기/보내기 속도
private struct NetworkRow: View {
  let link: NetLink?
  let down: String
  let up: String
  @State private var copied = false

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Badge(symbol: link?.kind.localizedCaseInsensitiveContains("wi") == true ? "wifi" : "network", color: .blue)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(link.map { "네트워크 · \($0.kind)" } ?? "네트워크").font(.system(size: 13, weight: .semibold)).lineLimit(1)
          Spacer()
          if let ip = link?.ip {
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(ip, forType: .string)
              copied = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
              Text(copied ? "복사했어요" : ip).font(.system(size: 12, weight: .semibold)).monospacedDigit()
            }
            .buttonStyle(.borderless)
            .help("내부 IP — 누르면 복사")
          } else {
            Text(link == nil ? "연결 안 됨" : "IP 없음").font(.system(size: 12)).foregroundStyle(.secondary)
          }
        }
        HStack(spacing: 14) {
          Label(down, systemImage: "arrow.down").foregroundStyle(.secondary)
          Label(up, systemImage: "arrow.up").foregroundStyle(.secondary)
        }
        .font(.system(size: 11)).monospacedDigit()
        .labelStyle(TightLabel())
      }
    }
  }
}

private struct TightLabel: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
  }
}

private struct SectionTitle: View {
  let title: String
  let note: String?
  init(_ title: String, note: String?) { self.title = title; self.note = note }
  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(.system(size: 12, weight: .semibold))
      Spacer()
      if let note { Text(note).font(.system(size: 10)).foregroundStyle(.tertiary) }
    }
    .padding(.top, 6)
  }
}

private struct Placeholder: View {
  let text: String
  init(_ text: String) { self.text = text }
  var body: some View {
    Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6).padding(.horizontal, 8)
  }
}

private struct AppRow: View {
  let app: AppUsage
  @State private var hover = false

  var body: some View {
    HStack(spacing: 8) {
      appIcon(app.icon)
      Text(app.name).font(.system(size: 12)).lineLimit(1)
      Spacer()
      if hover, let running = app.app {
        Button("종료") { running.terminate() }
          .buttonStyle(.borderless).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(nsColor: .humRed))
      } else {
        Text(bytesShort(app.memory)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        Text(pct(app.cpu)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
          .foregroundStyle(busyColor(min(app.cpu, 100))).frame(width: 44, alignment: .trailing)
      }
    }
    .padding(.vertical, 4).padding(.horizontal, 8)
    .background(hover ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
    .onHover { hover = $0 }
    .help(app.app == nil ? app.name : "\(app.name) — 누르면 종료할 수 있어요")
  }

  private func bytesShort(_ b: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .memory) }
}

private struct BlockerRow: View {
  let blocker: SleepBlocker
  var body: some View {
    HStack(spacing: 8) {
      appIcon(blocker.icon)
      VStack(alignment: .leading, spacing: 1) {
        Text(blocker.name).font(.system(size: 12)).lineLimit(1)
        if !blocker.reasons.isEmpty {
          Text(blocker.reasons.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer()
      Text(blocker.keepsDisplay ? "화면 켜 둠" : "잠자기 막음")
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }
    .padding(.vertical, 4).padding(.horizontal, 8)
  }
}

@ViewBuilder private func appIcon(_ img: NSImage?) -> some View {
  if let img {
    Image(nsImage: img).resizable().frame(width: 18, height: 18)
  } else {
    Image(systemName: "gearshape.2").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 18, height: 18)
  }
}

/// 최근 바쁜 정도 그래프(오른쪽이 지금)
private struct HistoryChart: View {
  let values: [Double]
  let capacity: Int
  let color: Color

  // 식을 잘게 나눔 — 한 덩어리로 쓰면 예전 컴파일러(GitHub Actions)가 시간 안에 타입을 못 정함
  var body: some View {
    GeometryReader { (g: GeometryProxy) in
      chart(size: g.size)
    }
  }

  private func points(in size: CGSize) -> [CGPoint] {
    let w: Double = size.width
    let h: Double = size.height
    let step: Double = w / Double(max(capacity - 1, 1))
    var out: [CGPoint] = []
    out.reserveCapacity(values.count)
    for (i, v) in values.enumerated() {
      let back: Double = Double(values.count - 1 - i)
      let level: Double = min(max(v, 0), 100) / 100
      out.append(CGPoint(x: w - back * step, y: h - 3 - (h - 6) * level))
    }
    return out
  }

  private func area(_ pts: [CGPoint], height h: Double) -> Path {
    var p = Path()
    guard let first = pts.first, let last = pts.last else { return p }
    p.move(to: CGPoint(x: first.x, y: h))
    for pt in pts { p.addLine(to: pt) }
    p.addLine(to: CGPoint(x: last.x, y: h))
    p.closeSubpath()
    return p
  }

  private func line(_ pts: [CGPoint]) -> Path {
    var p = Path()
    p.addLines(pts)
    return p
  }

  @ViewBuilder private func chart(size: CGSize) -> some View {
    let pts: [CGPoint] = points(in: size)
    let fade = LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    let stroke = StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
    ZStack {
      RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04))
      if pts.count > 1 {
        area(pts, height: size.height).fill(fade)
        line(pts).stroke(color, style: stroke)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
