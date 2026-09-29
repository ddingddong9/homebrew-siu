# GameplayFootball 개발 인수인계

이 문서는 다른 Apple Silicon Mac에서 GameplayFootball 3D LAN 프로토타입을 이어서 개발하기 위한 최소 절차다. 기준 브랜치는 `codex/gameplayfootball-lan-plan`, 기준 커밋은 `c0415f8`이다.

이 브랜치의 `SIU Football.app`은 SIU 로비에서 GameplayFootball 경기 실행 파일을 연다. 기존 Swift 11대11 경기 엔진과는 별도다. 이 문서의 `--lan-host`/`--lan-join`은 로비를 거치지 않는 G2 개발용 직접 IPv4 시험이다.

## 빠른 시작

```sh
git clone --recurse-submodules https://github.com/ddingddong9/homebrew-siu.git
cd homebrew-siu
git checkout codex/gameplayfootball-lan-plan
git submodule update --init --recursive

# 처음 한 번: 전체 Xcode 앱은 필요 없다.
xcode-select --install

# Command Line Tools 설치가 끝난 뒤
brew install cmake ninja sdl2-compat sdl2_image sdl2_ttf sdl2_gfx boost openal-soft

# 프로토콜 단위 테스트
Scripts/test-gameplayfootball-lan.sh

# 빌드와 앱 생성
Scripts/build-gameplayfootball-macos.sh --quick-match
open "dist/SIU Football.app"
```

`SIU Football.app`은 SIU 로비를 첫 화면으로 열고, 빨강 방장·파랑 참가자 카드에서 방 생성/검색/승인 후 GameplayFootball 경기를 실행한다. **AI 상대 로컬 연습**도 같은 경기 실행 파일을 연다. 원본 GameplayFootball의 경기 전 로딩 그림은 표시하지 않는다. 기존 `Assets/icon/siu-cutout.png`를 아이콘으로 사용한다. 이 앱은 개발용이다. 실행 파일은 Homebrew의 동적 라이브러리를 사용하므로, 다른 Mac에 앱만 복사해서 실행할 수는 없다. 소스를 받은 Mac에서 위 의존성을 설치하고 다시 빌드해야 한다.

## SIU 로비 LAN 시험

두 Mac에서 앱을 열고 한쪽은 **방 만들기**, 다른 쪽은 **방 검색 → 참가**를 누른다. 방장이 참가를 허용하고 **경기 시작**을 누르면 양쪽에서 GameplayFootball이 열린다. 경기 프로세스가 끝나면 로비가 다시 나타난다. 로비의 Bonjour 제어 연결과 경기 중 UDP 연결은 별개다. 현재 경기 UDP에는 인증·콘텐츠 해시가 없어 신뢰하는 LAN에서만 시험한다.

로비에서 시작한 경기의 방장은 승인한 참가자의 Wi-Fi IPv4 주소에서 온 UDP 입력만 받는다. 주소 제한은 인증을 대신하지 않는다.

## 직접 LAN 시험 (개발용)

두 Mac 모두 같은 브랜치·서브모듈 커밋·Homebrew 의존성으로 빌드한다. 참가 Mac의 주소에는 **방장 Mac의 Wi-Fi IPv4 주소**를 쓴다. `127.0.0.1`은 한 Mac에서 두 프로세스를 시험할 때만 쓴다.

```sh
# 방장 Mac
Scripts/build-gameplayfootball-macos.sh --lan-host --run

# 참가 Mac
Scripts/build-gameplayfootball-macos.sh --lan-join=192.168.0.10 --run
```

기본 UDP 포트는 `38245`이다. 양쪽에서 `--lan-port=PORT`로 동일하게 변경할 수 있다. macOS 방화벽 또는 공유기에서 기기 간 UDP 통신을 막는 경우 허용해야 한다.

## 현재 구현 위치

| 경로 | 역할 |
| --- | --- |
| `Vendor/GameplayFootball` | 고정된 외부 원본 submodule (`68159a2`) |
| `GameplayFootballPatches/` | 원본을 수정하지 않고 빌드 때 적용하는 macOS·입력·LAN 연결 패치 |
| `GameplayFootballOverlay/` | UDP 프로토콜, 세션, 원격 HID, 상태/렌더 자세 보정 |
| `Scripts/build-gameplayfootball-macos.sh` | 임시 경로에서 arm64 빌드 후 `dist/SIU Football.app` 생성 |
| `Scripts/package-gameplayfootball-dev-app.sh` | 기존 SIU 아이콘이 포함된 개발 앱 묶음 생성 |
| `Tests/` | 네트워크 패킷·루프백 회귀 시험 |
| `GAMEPLAYFOOTBALL_PORT.md` | 포팅과 검증 현황 |
| `GAMEPLAYFOOTBALL_LAN_PLAN.md` | 제품 기획과 G0~G5 완료 기준 |

## 검증 상태와 다음 작업

- 통과: arm64 전체 빌드, 앱 묶음 생성, UDP 직렬화/크기/순서/유한값 검증, 로컬 루프백, 한 Mac의 두 게임 프로세스 간 입력·상태 패킷 왕복.
- 통과: SIU 로비 표시, 로컬 연습 버튼의 경기 실행, 한 Mac에서 Bonjour 방 검색→자동 승인→경기 시작 신호.
- 미검증: 실제 화면에서 키보드로 패스·슛·골이 정상 동작하는지, 두 M4 Mac Wi-Fi에서의 재현, 10분 경기 완주.
- 미구현: 양쪽 준비/팀 선택 UI, 콘텐츠 해시·경기 UDP 인증, 재접속, 호스트 전용 규칙·접촉 확정, 배포용 의존성 포함 앱.

G2의 다음 우선순위는 실제 두 Mac에서 같은 패스·슛·골 장면을 관찰하는 것이다. 참가자는 아직 자체 시뮬레이션을 돌린 뒤 호스트 상태로 보정하므로, 공정한 대전 완성으로 취급하면 안 된다. 세부 측정값과 한계는 [포팅 현황](GAMEPLAYFOOTBALL_PORT.md)에 기록되어 있다.
