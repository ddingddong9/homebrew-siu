# siu

한 Mac에서 찬 축구공이 옆에 배치한 친구의 Mac 화면으로 날아가는 macOS 메뉴바 장난감입니다.

## 설치

```bash
brew install ddingddong9/siu/siu
```

이전 `mac-arrow` 사용자는 새 저장소로 바뀐 뒤 다음 명령으로 전환할 수 있습니다.

```bash
brew uninstall mac-arrow
brew untap ddingddong9/mac-arrow
brew install ddingddong9/siu/siu
```

## 화면 배치

두 Mac 모두 화면 위치와 상대방의 Bonjour 호스트명 또는 IP를 설정합니다.

```bash
siu setup
```

화면 카드를 macOS 디스플레이 설정처럼 드래그합니다. 기본 배치는 `2 친구`가 왼쪽, `1 나`가 오른쪽입니다. `+ 친구 화면 추가`로 여러 명을 배치할 수도 있습니다.

## 실행

두 Mac 모두 다음 명령으로 메뉴바 앱을 실행합니다.

```bash
siu start
```

상단 메뉴바의 `⚽️` 아이콘을 눌러 **선수 생성**을 선택합니다.

- 내 화면이 오른쪽이면 선수가 오른쪽 아래에서 왼쪽을 향합니다.
- 내 화면이 왼쪽이면 선수가 왼쪽 아래에서 오른쪽을 향합니다.
- 캐릭터의 상체는 고정되고 두 발만 좌우로 움직입니다.
- 캐릭터를 누르고 슛 방향 반대쪽으로 당겼다가 놓으면 공을 찹니다.
- 축구공은 해당 방향에서 가장 가까운 친구 화면으로 날아와 멈춥니다.
- **모든 축구공 지우기**로 화면에 남은 공을 초기화합니다.

명령어로도 바로 찰 수 있습니다.

```bash
siu kick left
siu kick right --y 0.25
siu kick friends-mac.local
```

처음 실행할 때 macOS가 네트워크 연결을 물으면 허용해야 합니다. 방화벽을 사용하는 경우 UDP `45678` 포트를 허용하세요.

## 개발

```bash
swift build -c release
.build/release/siu demo
```

캐릭터 스프라이트는 `Sources/MacArrow/Resources/siu-character.png`에 포함되어 있습니다.
