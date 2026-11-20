import AppKit
import Combine
import SwiftUI

/// 메뉴 막대 칩 아이콘 + 누르면 뜨는 창 + 설정창
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let monitor = Monitor()
  private let settings = Settings.shared
  private let popover = NSPopover()
  private var settingsWindow: NSWindow?
  private var timer: Timer?
  private var chipBucket = -1
  private var bag: Set<AnyCancellable> = []
  private var outsideClick: Any?   // 창이 열린 동안 바깥 클릭 감시

  func applicationDidFinishLaunching(_ note: Notification) {
    if let button = item.button {
      button.imagePosition = .imageLeading
      button.target = self
      button.action = #selector(clicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    let panel = NSHostingController(rootView: PanelView(
      monitor: monitor, settings: settings,
      openSettings: { [weak self] in self?.openSettings() },
      quit: { NSApp.terminate(nil) }))
    panel.sizingOptions = .preferredContentSize
    popover.contentViewController = panel
    popover.behavior = .transient
    popover.delegate = self

    monitor.refresh()
    updateButton()
    startTimer()
    // @Published는 값이 바뀌기 직전에 알려 주므로 다음 차례에 읽음
    settings.$interval.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.startTimer() } }.store(in: &bag)
    settings.$numberMode.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.updateButton() } }.store(in: &bag)
  }

  private func startTimer() {
    timer?.invalidate()
    let t = Timer(timeInterval: settings.interval, repeats: true) { [weak self] _ in
      self?.monitor.refresh()
      self?.updateButton()
    }
    t.tolerance = settings.interval * 0.2
    RunLoop.main.add(t, forMode: .common)   // 창·메뉴가 열려 있을 때도 돌게
    timer = t
  }

  // MARK: 메뉴 막대 버튼
  private func updateButton() {
    guard let button = item.button else { return }
    let s = monitor.snap
    // 색이 5% 단위로 바뀔 때만 다시 그림
    let bucket = Int((ChipIcon.busyness(s) / 5).rounded()) * 5
    if bucket != chipBucket {
      button.image = ChipIcon.chipImage(busy: Double(bucket))
      chipBucket = bucket
    }
    let text = numberText(s)
    if button.attributedTitle.string != text {   // 바뀔 때만(메뉴 막대 다시 배치를 줄임)
      button.attributedTitle = NSAttributedString(string: text, attributes: [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        .baselineOffset: 0.5,
      ])
    }
    button.toolTip = "CPU \(Int(s.cpu.rounded()))% · 메모리 \(Int(s.mem.rounded()))% · GPU \(s.gpu.map { "\(Int($0.rounded()))%" } ?? "–")"
  }

  private func numberText(_ s: Snapshot) -> String {
    let gpu = s.gpu ?? 0
    switch settings.numberMode {
    case .none: return ""
    case .max: return " " + pad(max(s.cpu, s.mem, gpu)) + "%"
    case .all: return " C" + pad(s.cpu) + " M" + pad(s.mem) + " G" + pad(gpu)
    }
  }

  /// 자릿수가 바뀌어도 폭이 흔들리지 않게 숫자 폭 공백(U+2007)으로 채움
  private func pad(_ v: Double) -> String {
    let s = String(Int(v.rounded()))
    return String(repeating: "\u{2007}", count: max(0, 2 - s.count)) + s
  }

  // MARK: 누르기 — 왼쪽: 창 / 오른쪽: 짧은 메뉴
  @objc private func clicked(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      popover.performClose(nil)
      let m = NSMenu()
      m.addItem(withTitle: "설정…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
      m.addItem(.separator())
      m.addItem(withTitle: "Hum 끝내기", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
      item.menu = m
      sender.performClick(nil)
      item.menu = nil
      return
    }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      monitor.detailed = true
      NSApp.activate()
      popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
      // .transient만으로는 다른 앱 창을 눌러도 안 닫힐 때가 있음 → 바깥 클릭(다른 앱)을 직접 감시
      outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
        self?.popover.performClose(nil)
      }
    }
  }

  func popoverDidClose(_ notification: Notification) {
    monitor.detailed = false
    if let m = outsideClick { NSEvent.removeMonitor(m); outsideClick = nil }
  }

  func applicationDidResignActive(_ notification: Notification) {
    if popover.isShown { popover.performClose(nil) }
  }

  // MARK: 설정창
  @objc private func openSettingsAction() { openSettings() }

  private func openSettings() {
    popover.performClose(nil)
    if settingsWindow == nil {
      let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
      w.title = "Hum 설정"
      w.styleMask = [.titled, .closable]
      w.isReleasedWhenClosed = false
      w.center()
      settingsWindow = w
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
