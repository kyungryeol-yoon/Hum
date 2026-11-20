# Homebrew cask 틀 — 릴리스할 때 GitHub Actions가 __VERSION__·__SHA256__을 채워 homebrew-tap/Casks/ 에 올림
cask "hum" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/kyungryeol-yoon/hum/releases/download/v#{version}/Hum-#{version}.zip"
  name "Hum"
  desc "Menu bar chip icon that shows how busy your Mac is"
  homepage "https://github.com/kyungryeol-yoon/hum"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Hum.app"

  # 애플 개발자 서명·공증을 하지 않은 앱이라, 「확인되지 않은 개발자」 경고 없이 열리도록 격리 표시를 지움
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Hum.app"],
                   sudo: false
  end

  uninstall quit: "io.github.kyungryeol-yoon.hum"

  zap trash: "~/Library/Preferences/io.github.kyungryeol-yoon.hum.plist"
end
