import Darwin
import Foundation
import IOKit
import IOKit.ps
import SystemConfiguration

/// 한 번 읽은 값. 퍼센트는 0~100
struct Snapshot {
  var cpu: Double = 0
  var cpuUser: Double = 0
  var cpuSystem: Double = 0
  var mem: Double = 0
  var memUsedBytes: UInt64 = 0
  var memTotalBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
  var pressure: Pressure = .normal
  var swapUsedBytes: UInt64 = 0
  var memAppBytes: UInt64 = 0        // 앱 메모리
  var memWiredBytes: UInt64 = 0      // 고정(와이어드) 메모리
  var memCompressedBytes: UInt64 = 0 // 압축된 메모리
  var gpu: Double? = nil   // 못 읽으면 nil
  var diskFreeBytes: Int64? = nil
  var diskTotalBytes: Int64? = nil
  var netIn: Double = 0    // 초당 바이트
  var netOut: Double = 0
  var thermal: ProcessInfo.ThermalState = .nominal
  var link: NetLink? = nil           // 지금 쓰는 연결
  var battery: Battery? = nil        // 배터리가 없는 맥이면 nil
}

/// 지금 인터넷에 쓰는 연결(시스템의 기본 연결)
struct NetLink {
  var kind: String     // 「Wi-Fi」·「이더넷」 등(시스템 언어로)
  var bsdName: String  // en0 등
  var ip: String?      // 내부 IPv4
}

struct Battery {
  var percent: Int
  var charging: Bool
  var onAC: Bool
  var minutesLeft: Int?   // 남은 시간(모르면 nil)
}

extension ProcessInfo.ThermalState {
  var label: String {
    switch self {
    case .nominal: "정상"
    case .fair: "조금 높음"
    case .serious: "높음"
    case .critical: "매우 높음"
    @unknown default: "알 수 없음"
    }
  }
}

/// 메모리 압박(`kern.memorystatus_vm_pressure_level`: 1 보통 · 2 경고 · 4 위험)
enum Pressure: Int {
  case normal = 1, warn = 2, critical = 4
  var label: String {
    switch self { case .normal: "보통"; case .warn: "높음"; case .critical: "위험" }
  }
}

/// CPU·메모리·GPU를 읽는다. CPU는 직전 호출과의 차이로 계산하므로 같은 인스턴스를 계속 쓴다
final class Stats {
  private var lastTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
  private var lastNet: [String: (inB: UInt32, outB: UInt32)] = [:]
  private var lastNetTime: Date?
  private var disk: (free: Int64?, total: Int64?, at: Date)?

  func read() -> Snapshot {
    var s = Snapshot()
    readCPU(&s)
    readMemory(&s)
    s.gpu = readGPU()
    readNetwork(&s)
    readDisk(&s)
    readLinkAndBattery(&s)
    s.thermal = ProcessInfo.processInfo.thermalState
    return s
  }

  // MARK: CPU — host_statistics(HOST_CPU_LOAD_INFO), 모든 코어 합계
  private func readCPU(_ s: inout Snapshot) {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    guard kr == KERN_SUCCESS else { return }
    let t = info.cpu_ticks
    let now = (user: UInt64(t.0), system: UInt64(t.1), idle: UInt64(t.2), nice: UInt64(t.3))
    defer { lastTicks = now }
    guard let last = lastTicks else { return }
    let user = Double(now.user &- last.user) + Double(now.nice &- last.nice)
    let system = Double(now.system &- last.system)
    let idle = Double(now.idle &- last.idle)
    let total = user + system + idle
    guard total > 0 else { return }
    s.cpuUser = user / total * 100
    s.cpuSystem = system / total * 100
    s.cpu = s.cpuUser + s.cpuSystem
  }

  // MARK: 메모리 — 활성 상태 보기의 「사용된 메모리」와 같은 식(앱 + 고정 + 압축)
  private func readMemory(_ s: inout Snapshot) {
    var vm = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &vm) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
      }
    }
    if kr == KERN_SUCCESS {
      let page = UInt64(vm_kernel_page_size)
      let app = (UInt64(vm.internal_page_count) &- UInt64(vm.purgeable_count)) * page
      let wired = UInt64(vm.wire_count) * page
      let compressed = UInt64(vm.compressor_page_count) * page
      s.memAppBytes = app
      s.memWiredBytes = wired
      s.memCompressedBytes = compressed
      s.memUsedBytes = min(app + wired + compressed, s.memTotalBytes)
      s.mem = Double(s.memUsedBytes) / Double(s.memTotalBytes) * 100
    }

    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
      s.pressure = Pressure(rawValue: Int(level)) ?? .normal
    }

    var swap = xsw_usage()
    size = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
      s.swapUsedBytes = swap.xsu_used
    }
  }

  // MARK: GPU — IORegistry IOAccelerator의 PerformanceStatistics
  private func readGPU() -> Double? {
    var iter: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(iter) }
    var best: Double?
    while case let entry = IOIteratorNext(iter), entry != 0 {
      defer { IOObjectRelease(entry) }
      guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
        .takeRetainedValue() as? [String: Any] else { continue }
      if let u = (stats["Device Utilization %"] as? NSNumber)?.doubleValue {
        best = max(best ?? 0, u)
      }
    }
    return best.map { min(max($0, 0), 100) }
  }

  // MARK: 네트워크 — getifaddrs의 링크 계층 통계. 실제 바깥 연결(en*)만 합침(utun 같은 VPN은 같은 트래픽을 한 번 더 세므로 뺌)
  private func readNetwork(_ s: inout Snapshot) {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return }
    defer { freeifaddrs(ifap) }
    var now: [String: (inB: UInt32, outB: UInt32)] = [:]
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let a = p.pointee
      guard let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = a.ifa_data else { continue }
      let name = String(cString: a.ifa_name)
      guard name.hasPrefix("en") else { continue }
      let d = data.assumingMemoryBound(to: if_data.self).pointee
      now[name] = (d.ifi_ibytes, d.ifi_obytes)
    }
    let t = Date()
    if let lastT = lastNetTime, t.timeIntervalSince(lastT) > 0 {
      var i: UInt64 = 0, o: UInt64 = 0
      for (name, v) in now {
        guard let l = lastNet[name] else { continue }
        i += UInt64(v.inB &- l.inB)   // 32비트 계수기라 4GB마다 0으로 돌아감 — 뺄셈을 감싸서 처리
        o += UInt64(v.outB &- l.outB)
      }
      let dt = t.timeIntervalSince(lastT)
      s.netIn = Double(i) / dt
      s.netOut = Double(o) / dt
    }
    lastNet = now
    lastNetTime = t
  }

  // MARK: 디스크 — 시동 디스크 남은 공간. 자주 바뀌지 않으니 30초에 한 번만 읽음
  private func readDisk(_ s: inout Snapshot) {
    if disk == nil || Date().timeIntervalSince(disk!.at) > 30 {
      let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
      disk = (v?.volumeAvailableCapacityForImportantUsage, v?.volumeTotalCapacity.map(Int64.init), Date())
    }
    s.diskFreeBytes = disk?.free
    s.diskTotalBytes = disk?.total
  }

  // MARK: 연결·배터리 — 자주 바뀌지 않으니 10초에 한 번
  private var slow: (link: NetLink?, battery: Battery?, at: Date)?

  private func readLinkAndBattery(_ s: inout Snapshot) {
    if slow == nil || Date().timeIntervalSince(slow!.at) > 10 {
      slow = (Self.primaryLink(), Self.battery(), Date())
    }
    s.link = slow?.link
    s.battery = slow?.battery
  }

  static func primaryLink() -> NetLink? {
    guard let global = SCDynamicStoreCopyValue(nil, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
          let bsd = global["PrimaryInterface"] as? String else { return nil }
    var kind = bsd
    if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface],
       let i = all.first(where: { SCNetworkInterfaceGetBSDName($0) as String? == bsd }),
       let name = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
      kind = name
    }
    return NetLink(kind: kind, bsdName: bsd, ip: ipv4(of: bsd))
  }

  private static func ipv4(of bsd: String) -> String? {
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
    defer { freeifaddrs(ifap) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let a = p.pointee
      guard String(cString: a.ifa_name) == bsd, let addr = a.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
        return String(cString: host)
      }
    }
    return nil
  }

  static func battery() -> Battery? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
      guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
            d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
            let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
      let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
      let charging = d[kIOPSIsChargingKey] as? Bool ?? false
      let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
      let minutes = (d[key] as? Int).flatMap { $0 > 0 ? $0 : nil }
      return Battery(percent: cur * 100 / max, charging: charging, onAC: onAC, minutesLeft: minutes)
    }
    return nil
  }
}
