import AppKit
import Darwin
import IOKit.pwr_mgt

/// 많이 쓰는 프로그램 한 줄. 같은 앱의 도우미 프로세스(예: 브라우저 탭)는 앱 하나로 묶음
struct AppUsage: Identifiable {
  let id: String              // 묶음 키: 앱 번들 경로 또는 「proc:이름」
  let name: String
  let icon: NSImage?
  let cpu: Double             // %(코어 하나를 꽉 쓰면 100)
  let memory: UInt64
  let app: NSRunningApplication?   // 정상 종료를 요청할 수 있는 앱이면
}

/// 프로그램별 CPU·메모리. 직전 호출과의 차이로 CPU를 계산하므로 같은 인스턴스를 계속 씀
/// 내 계정의 프로세스만 읽힘(다른 사용자·시스템 프로세스는 권한이 없어 빠짐)
final class ProcessSampler {
  private var lastCPU: [pid_t: UInt64] = [:]
  private var lastWall: UInt64 = 0
  private var groupOf: [pid_t: (key: String, name: String, bundle: String?)] = [:]
  private var icons: [String: NSImage] = [:]

  func sample(top n: Int) -> [AppUsage] {
    let now = mach_absolute_time()
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    let got = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
    let wall = lastWall == 0 ? 0 : Double(now &- lastWall)   // ri_*_time과 같은 단위(mach 시간)

    struct Acc { var cpu = 0.0; var mem: UInt64 = 0; var name = ""; var bundle: String? }
    var groups: [String: Acc] = [:]
    var cpuNow: [pid_t: UInt64] = [:]
    let me = getpid()
    for pid in pids.prefix(max(0, got)) where pid > 0 && pid != me {
      var ru = rusage_info_v4()
      let r = withUnsafeMutablePointer(to: &ru) { p in
        p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
      }
      guard r == 0 else { continue }
      let t = ru.ri_user_time + ru.ri_system_time
      cpuNow[pid] = t
      var cpu = 0.0
      if wall > 0, let last = lastCPU[pid], t >= last { cpu = Double(t - last) / wall * 100 }
      let g = group(pid)
      groups[g.key, default: Acc(name: g.name, bundle: g.bundle)].cpu += cpu
      groups[g.key, default: Acc(name: g.name, bundle: g.bundle)].mem += ru.ri_phys_footprint
    }
    lastCPU = cpuNow
    lastWall = now
    groupOf = groupOf.filter { cpuNow[$0.key] != nil }

    let running = NSWorkspace.shared.runningApplications
    return groups
      .sorted { $0.value.cpu != $1.value.cpu ? $0.value.cpu > $1.value.cpu : $0.value.mem > $1.value.mem }
      .prefix(n)
      .map { key, acc in
        let app = acc.bundle.flatMap { b in running.first { $0.bundleURL?.path == b && $0.activationPolicy != .prohibited } }
        return AppUsage(id: key, name: acc.name, icon: icon(key, bundle: acc.bundle), cpu: acc.cpu, memory: acc.mem, app: app)
      }
  }

  /// 실행 파일 경로에서 가장 바깥 .app을 찾아 그 앱으로 묶음
  private func group(_ pid: pid_t) -> (key: String, name: String, bundle: String?) {
    if let g = groupOf[pid] { return g }
    var g: (key: String, name: String, bundle: String?)
    let path = Self.path(pid)
    if let r = path?.range(of: ".app/") {
      let bundle = String(path![..<r.lowerBound]) + ".app"
      let name = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle(path: bundle)?.bundleIdentifier ?? "-").first?.localizedName
        ?? ((bundle as NSString).lastPathComponent as NSString).deletingPathExtension
      g = (bundle, name, bundle)
    } else {
      let name = Self.name(pid) ?? path.map { ($0 as NSString).lastPathComponent } ?? "pid \(pid)"
      g = ("proc:" + name, name, nil)
    }
    groupOf[pid] = g
    return g
  }

  private func icon(_ key: String, bundle: String?) -> NSImage? {
    guard let bundle else { return nil }
    if let i = icons[key] { return i }
    let i = NSWorkspace.shared.icon(forFile: bundle)
    icons[key] = i
    return i
  }

  static func path(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
    return proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
  }

  static func name(_ pid: pid_t) -> String? {
    var buf = [CChar](repeating: 0, count: 256)
    return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : nil
  }
}

/// 잠자기(또는 화면 꺼짐)를 막고 있는 프로그램 — `pmset -g assertions`와 같은 정보
struct SleepBlocker: Identifiable {
  let id: pid_t
  let name: String
  let reasons: [String]
  let keepsDisplay: Bool      // 화면까지 켜 두는지
  let icon: NSImage?
}

enum SleepBlockers {
  private static let systemTypes: Set<String> = ["PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion"]
  private static let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]

  static func read() -> [SleepBlocker] {
    var ref: Unmanaged<CFDictionary>?
    guard IOPMCopyAssertionsByProcess(&ref) == kIOReturnSuccess,
          let dict = ref?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
    var out: [SleepBlocker] = []
    for (pidNum, list) in dict {
      let pid = pid_t(pidNum.int32Value)
      guard pid != getpid() else { continue }
      var reasons: [String] = []
      var display = false, any = false
      for a in list {
        guard let type = a["AssertType"] as? String, systemTypes.contains(type) || displayTypes.contains(type) else { continue }
        if let level = a["AssertLevel"] as? Int, level == 0 { continue }   // 풀린 것
        any = true
        if displayTypes.contains(type) { display = true }
        if let r = a["AssertName"] as? String, !r.isEmpty, !reasons.contains(r) { reasons.append(r) }
      }
      guard any else { continue }
      // 이름을 못 읽는 건 시스템 프로세스(powerd·coreaudiod 등) — 늘 걸려 있거나 다른 앱 때문에 걸린 것이라 뺌
      let app = NSRunningApplication(processIdentifier: pid)
      guard let name = app?.localizedName ?? ProcessSampler.name(pid) else { continue }
      out.append(SleepBlocker(id: pid, name: name, reasons: reasons, keepsDisplay: display, icon: app?.icon))
    }
    return out.sorted { ($0.keepsDisplay ? 0 : 1, $0.name) < ($1.keepsDisplay ? 0 : 1, $1.name) }
  }
}
