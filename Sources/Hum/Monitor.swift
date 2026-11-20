import AppKit
import Combine

/// 화면들이 함께 보는 값. 메뉴 막대 아이콘은 늘, 자세한 정보(프로그램 목록 등)는 창이 열려 있을 때만 읽음
final class Monitor: ObservableObject {
  static let historyLength = 60

  @Published private(set) var snap = Snapshot()
  @Published private(set) var history: [Double] = []      // 바쁜 정도
  @Published private(set) var topApps: [AppUsage] = []
  @Published private(set) var blockers: [SleepBlocker] = []
  @Published private(set) var detailsReady = false

  var detailed = false {
    didSet {
      guard detailed != oldValue else { return }
      if detailed {
        // 프로그램별 CPU는 두 번 읽어야 나오므로 먼저 한 번 읽어 두고 잠깐 뒤 다시 채움
        _ = procs.sample(top: 0)
        blockers = SleepBlockers.read()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
          guard let self, self.detailed else { return }
          self.topApps = self.procs.sample(top: 3)
          self.detailsReady = true
        }
      } else {
        detailsReady = false
      }
    }
  }

  private let stats = Stats()
  private let procs = ProcessSampler()

  init() { _ = stats.read() }   // CPU는 차이로 계산하므로 한 번 먼저

  func refresh() {
    snap = stats.read()
    history.append(ChipIcon.busyness(snap))
    if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    if detailed {
      topApps = procs.sample(top: 3)
      blockers = SleepBlockers.read()
      detailsReady = true
    }
  }
}
