import AppKit
import ServiceManagement
import SwiftUI

/// 사용자 설정(UserDefaults에 저장)
final class Settings: ObservableObject {
  static let shared = Settings()
  static let intervals: [Double] = [1, 2, 5]
  private let d = UserDefaults.standard

  @Published var numberMode: NumberMode { didSet { d.set(numberMode.rawValue, forKey: "numberMode") } }
  @Published var interval: Double { didSet { d.set(interval, forKey: "interval") } }

  private init() {
    for old in ["colorMode", "iconStyle"] { d.removeObject(forKey: old) }   // 예전 시험용 설정
    numberMode = NumberMode(rawValue: d.string(forKey: "numberMode") ?? "") ?? .none
    let i = d.double(forKey: "interval")
    interval = Self.intervals.contains(i) ? i : 2
  }
}

struct SettingsView: View {
  @ObservedObject var settings: Settings
  @State private var loginStatus = SMAppService.mainApp.status
  @State private var loginError: String?

  private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "개발판" }

  var body: some View {
    Form {
      Section("메뉴 막대") {
        Picker("아이콘 옆 숫자", selection: $settings.numberMode) {
          ForEach(NumberMode.allCases) { Text($0.label).tag($0) }
        }
        HStack(spacing: 6) {
          Text("미리 보기").foregroundStyle(.secondary)
          Spacer()
          HStack(spacing: 4) {
            Image(nsImage: ChipIcon.chipImage(busy: 42))
            Text(preview).font(.system(size: 12, weight: .medium)).monospacedDigit()
          }
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
      }

      Section {
        Picker("갱신 간격", selection: $settings.interval) {
          ForEach(Settings.intervals, id: \.self) { Text("\(Int($0))초").tag($0) }
        }
        .pickerStyle(.segmented)
      } footer: {
        Text("짧을수록 빨리 반응하지만 Hum도 그만큼 조금 더 일해요.").font(.caption).foregroundStyle(.secondary)
      }

      Section {
        // 사용자가 스위치를 눌렀을 때만 등록·해제(실제 상태로 맞추는 것이 다시 등록·해제를 부르지 않게)
        Toggle("로그인할 때 자동으로 실행", isOn: Binding(
          get: { loginStatus == .enabled || loginStatus == .requiresApproval },
          set: { setLaunchAtLogin($0) }))
      } footer: {
        loginFooter
      }

      Section("칩 색") {
        ColorLegendRow(busy: 25, title: "초록", detail: "여유로워요 · 0~50%")
        ColorLegendRow(busy: 75, title: "주황", detail: "바빠요 · 75% 안팎")
        ColorLegendRow(busy: 95, title: "빨강", detail: "아주 바빠요 · 92% 이상")
        Text("CPU와 GPU 중 더 바쁜 쪽을 기준으로 해요. 사이 값은 색이 자연스럽게 섞여요.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section {
        HStack {
          Text("Hum \(version)")
          Spacer()
          Link("GitHub", destination: URL(string: "https://github.com/kyungryeol-yoon/hum")!)
        }
      }
    }
    .formStyle(.grouped)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      loginStatus = SMAppService.mainApp.status   // 시스템 설정에서 바꿨을 수 있음
    }
    .frame(width: 420)
    .fixedSize(horizontal: false, vertical: true)
  }

  private var preview: String {
    switch settings.numberMode {
    case .none: ""
    case .max: "42%"
    case .all: "C42 M68 G12"
    }
  }

  @ViewBuilder private var loginFooter: some View {
    if let loginError {
      Text(loginError).font(.caption).foregroundStyle(.red)
    } else if loginStatus == .requiresApproval {
      HStack(spacing: 6) {
        Text("시스템 설정 → 일반 → 로그인 항목에서 Hum을 허용해 주세요.").font(.caption).foregroundStyle(.secondary)
        Button("열기") { SMAppService.openSystemSettingsLoginItems() }
          .buttonStyle(.link).font(.caption)
      }
    }
  }

  private func setLaunchAtLogin(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      loginError = nil
    } catch {
      loginError = "설정하지 못했어요: \(error.localizedDescription)"
    }
    loginStatus = SMAppService.mainApp.status
  }
}

private struct ColorLegendRow: View {
  let busy: Double
  let title: String
  let detail: String
  var body: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: ChipIcon.statusColor(busy))).frame(width: 16, height: 16)
      Text(title)
      Spacer()
      Text(detail).foregroundStyle(.secondary)
    }
  }
}
