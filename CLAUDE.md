# Hum

맥이 얼마나 바쁜지 메뉴 막대의 **칩 아이콘** 색으로 보여 주고, 누르면 자세한 상태 창이 뜨는 앱. 이름은 기계가 일할 때 내는 「웅웅」 소리(*humming along* = 잘 돌아가고 있다).

- GitHub `kyungryeol-yoon/hum`(공개) — **범용**으로: 특정 사용자 환경에 맞춘 기본값·코드 금지. **커밋·푸시는 요청할 때만**
- RunCat 대신 만든 앱 — **RunCat의 이름·그림·생김새는 쓰지 않는다**(정보 항목만 참고)
- Swift + SwiftPM, 외부 라이브러리 없음, 애플 실리콘·macOS 15+, ad-hoc 서명. 번들 ID `io.github.kyungryeol-yoon.hum`(앞으로 만들 앱도 `io.github.kyungryeol-yoon.<앱>`)
- 사용자용 설명은 `README.md`, 개발 메모는 이 파일. 설명은 한국어

## 구조(`Sources/Hum/`)
- `main.swift` — `NSStatusItem` 버튼(왼쪽 클릭: 상태 창, 오른쪽: 설정·끝내기 메뉴), `NSPopover`, 설정창
- `Icon.swift` — 칩 아이콘(`ChipIcon`), 바쁜 정도 색
- `Stats.swift` — CPU·메모리·GPU·디스크·네트워크·배터리·발열 읽기
- `Processes.swift` — 많이 쓰는 프로그램(`ProcessSampler`), 잠자기 막는 프로그램(`SleepBlockers`)
- `Monitor.swift` — 갱신·기록(창이 열려 있을 때만 프로그램 목록 읽음)
- `PanelView.swift` — 상태 창(SwiftUI) · `Settings.swift` — 설정 값·설정창

## 정한 것
- **아이콘**: 둥근 두꺼운 테두리 + 변마다 핀 3개, 안쪽 네모를 바쁜 정도 색으로 채움. 움직임 없음
  - 바쁜 정도 = max(CPU, GPU). 0~50 초록 → 75 주황 → 92+ 빨강, 사이는 색상환을 따라 섞음(RGB로 섞으면 올리브색)
  - 색이 5% 단위로 바뀔 때만 다시 그림. 옆 숫자: 없음 / 가장 높은 값 / 셋 다
  - 시험하고 버린 것: 막대·링·격자형(4K에서 작음), 칩 몸통 채우기, 움직이는 회로·파형, 깜빡임(정신없음)
- **상태 창**: 상태 한마디 + 큰 % · 최근 그래프 · 묶음별 카드(성능 / 저장 공간·연결 / 많이 쓰는 프로그램 / 잠자기를 막는 프로그램)
  - 메모리 색은 사용률이 아니라 압박으로. 네트워크는 `en*`만 합침(VPN 중복 제외), 내부 IP 누르면 복사
  - 프로그램은 도우미 프로세스를 바깥 `.app`으로 묶음, 내 계정 프로세스만. 종료는 `NSRunningApplication.terminate()`
  - 잠자기 막는 프로그램: 이름 못 읽는 시스템 프로세스는 뺌
- **설정**: 옆 숫자 · 갱신 간격 1/2/5초(기본 2) · 로그인 자동 실행(`SMAppService` — /Applications에 둔 뒤 켤 것)
- **앱 아이콘**: 어두운 바탕 + 같은 칩(초록) — `packaging/make-icon.swift`로 `AppIcon.icns` 생성

## 주의할 것
- 메뉴 막대 그림을 자주 바꾸면 `button.image` 교체마다 항목 전체를 다시 그려 CPU 10%대 → 애니메이션이 필요하면 버튼 위 `CALayer.contents`만 바꿀 것. 지금 창 닫힌 상태 CPU 0.5% 안팎
- 막대 애니메이션은 길이에만 걸 것(바깥에 걸면 창 높이 바뀔 때 막대가 글자 위로 미끄러짐)
- 창 바깥 클릭: `.transient`만으로는 안 닫힘 → 창이 열린 동안만 전역 마우스 감시 + 앱 비활성화 때 닫음
- SwiftUI body는 섹션 함수로 나누고 계산은 타입을 밝힌 함수로 — 한 덩어리면 CI 컴파일러가 타입 검사 시간 초과(v0.1.0 첫 빌드 실패 원인)

## 빌드·배포
- `./build.sh` → `build/Hum.app`. 시험할 땐 설치판을 끄고(`pkill -x Hum`) `open build/Hum.app` — `./build.sh install`은 brew 설치판을 덮어쓰므로 쓰지 않음
- 태그 `vX.Y.Z` 푸시 → `.github/workflows/release.yml`(macos-26 + 최신 Xcode) → Release zip → `homebrew-tap`의 `Casks/hum.rb` 갱신(`TAP_TOKEN`)
- cask 틀 `packaging/hum.rb`: `depends_on macos: :sequoia`, quarantine은 `postflight_steps`의 `run "/usr/bin/xattr"`로 지움(`writable_paths` 없으면 샌드박스가 막음)
- 설치 `brew install --cask kyungryeol-yoon/tap/hum` — v0.1.0 설치 확인(2026-11-21)

## 다음에 할 것
- [ ] 「동작 줄이기」·접근성 점검, 상태 창 키보드 조작
- [ ] README에 화면 설명·스크린샷
- [ ] 나중에 볼 정보: 전력(비공개 IOReport), 열린 로컬 포트, 블루투스 기기 배터리, 인터넷 응답 속도
