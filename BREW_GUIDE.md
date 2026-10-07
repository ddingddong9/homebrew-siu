# SIU 앱 설치·업데이트 명령어 (1.15.0-beta.1)

현재 게임은 `siu-app-beta` **앱 cask**다. `brew install siu` 또는 `brew install siu-beta`는 예전 CLI를 설치하므로 현재 1대1·2대2 앱 설치에 사용하지 않는다.

## Homebrew가 없는 친구

[Homebrew 공식 설치 안내](https://brew.sh/ko/)에서 설치한다. Homebrew 설치 과정에서 CLT를 요구할 수 있으며 [공식 요구사항](https://docs.brew.sh/Installation)을 따른다. SIU 자체는 미리 빌드되어 Xcode·CLT 없이 실행된다. Homebrew 없이 설치하려면 [최신 릴리스](https://github.com/ddingddong9/homebrew-siu/releases/tag/v1.15.0-beta.1)의 `siu-v1.15.0-beta.1-macos-app.zip`을 풀고 `SIU.app`을 응용프로그램으로 옮긴다. 미공증 베타라 macOS 보안 안내가 나타날 수 있다. 시스템 전체 보안 설정을 끄지 않는다.

## 최초 설치 (네 Mac 각각)

```bash
brew tap ddingddong9/siu
brew trust --cask ddingddong9/siu/siu-app-beta
brew install --cask ddingddong9/siu/siu-app-beta
open /Applications/SIU.app
```

`brew trust`는 저장소 전체 대신 이 cask만 신뢰한다. 해당 기능이 없는 예전 Homebrew라면 먼저 `brew update`로 갱신한다.

## 기존 설치 업데이트

경기를 종료하고 SIU 앱을 완전히 종료한 뒤 실행한다.

```bash
brew update
brew upgrade --cask ddingddong9/siu/siu-app-beta
open /Applications/SIU.app
```

## 버전·다운로드 확인

```bash
brew info --cask ddingddong9/siu/siu-app-beta
brew list --cask --versions siu-app-beta
brew fetch --cask ddingddong9/siu/siu-app-beta
```

앱 버전은 아래 명령으로도 확인한다.

```bash
/usr/libexec/PlistBuddy -c 'Print :SIUReleaseVersion' /Applications/SIU.app/Contents/Info.plist
```

## 수동 설치했거나 업데이트가 꼬인 경우

수동 설치 앱이 이미 `/Applications/SIU.app`에 있으면 최초 `brew install`이 기존 앱과 충돌할 수 있다. 기존 앱을 Finder에서 다른 폴더로 옮겨 보관한 뒤 설치한다. Homebrew가 관리하는 설치를 다시 설치하려면 앱 종료 후:

```bash
brew reinstall --cask ddingddong9/siu/siu-app-beta
```

삭제가 필요한 경우에만 다음 명령을 실행한다. 앱을 제거하는 명령이다.

```bash
brew uninstall --cask ddingddong9/siu/siu-app-beta
```

## 2대2 참가 순서와 키

네 Mac을 같은 와이파이에 연결하고 모두 **1.15.0-beta.1**을 실행한다. 홈의 **4인 LAN 대전**에서 방장은 **방 만들기**, 친구 세 명은 **방 검색 → 방 선택 → 참가**. 방장이 각 참가자를 승인한다. 한 명씩 승인 완료 후 다음 사람이 참가하면 배정 순서를 맞추기 쉽다.

| 승인 순서 | 팀·선수 |
|---|---|
| 방장 | 빨강 #1 |
| 첫 참가 | 빨강 #2 |
| 두 번째 참가 | 파랑 #3 |
| 세 번째 참가 | 파랑 #4 |

4/4가 되면 방장이 **4인 경기 시작**. 경기 시간은 3분. 팀 재배정 UI는 아직 없으며 원하는 팀 순서로 참가한다. 연결이 끊기면 경기 중단, 다시 인원을 모아 새 경기를 시작한다. 네 사람이 모두 직접 조작하며 AI 대체 선수는 없다.

| 2대2 키 | 동작 |
|---|---|
| 방향키 | 이동·바라보는 방향 |
| E 유지 | 스태미나를 소비하며 달리기 (1대1은 Shift) |
| D | 슛 |
| S | 같은 팀 동료 위치로 패스 |
| W | 동료 이동 방향 앞 공간으로 스루패스; 정지 중에는 공격 방향으로 선행 |
| A | 전방 대시 슬라이딩 태클, 감속 이동 중 공·상대 접촉 판정 |
| Z 유지 + D | 과장된 바나나 감아차기: 큰 옆 궤적 뒤 골문 쪽 유도; 수비 접촉 시 유도 해제 |
| Shift + Q | 백숏: 공을 뒤로 당기고 180° 방향전환, 소유 유지 |
| Shift + E | 발재간 |
| Shift + X | 사포 |
| Esc (방장) | 일시정지·재개 |

기본 키는 요청한 FC온라인 방식에 맞추었다. 개인기는 Shift 조합의 **SIU 간소화 입력**이며 공식 개인기의 방향키 시퀀스를 그대로 재현하지 않는다. [FC온라인 공식 조작 안내](https://m.fconline.nexon.com/news/guide/view?n4articlecategorysn=3&n4articlesn=160). 1대1에는 기존 키를 유지하고 백숏의 동작만 수정했다. 앱의 조작 안내에서 모드별 차이를 확인한다.

## 검증 범위

스태미나는 최대 100, 이동하며 달릴 때 초당 24 소모·걷거나 쉬면 초당 15 회복. 소진 시 20 이상 회복 후 재사용. 태클은 0.55초 슬라이딩, 1.15초 재사용 제한. 선수 아래 게이지에 표시하며 두 모드 모두 적용된다.

물리·패스·스루패스·백숏·4인 TCP 루프백·참가 슬롯·상태 전달·일시정지·연결 중단 자동 테스트를 수행한다. 실제 Mac 4대의 와이파이 대전과 지연·패킷 손실 환경은 별도 검증이 필요하다. 공유기의 AP 격리/게스트 와이파이가 켜져 있으면 같은 SSID라도 연결되지 않을 수 있다. macOS의 SIU 로컬 네트워크 권한과 방화벽을 확인한다.
