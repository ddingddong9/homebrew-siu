# mac-arrow

한 Mac의 왼쪽으로 쏜 화살을 상대 Mac 화면의 오른쪽에서 날아오게 하는 작은 macOS 도구입니다.

## 설치

상대방은 다음 한 줄로 설치합니다.

```bash
brew install ddingddong9/mac-arrow/mac-arrow
```

## 사용

상대방 Mac에서 수신기를 켭니다.

```bash
mac-arrow receive
```

보내는 Mac에서 상대의 IP 또는 Bonjour 호스트명으로 발사합니다.

```bash
mac-arrow shoot friends-mac.local
# 높이 지정: 화면 아래 0.0, 위 1.0
mac-arrow shoot 192.168.0.23 --y 0.65
```

처음 수신할 때 macOS가 네트워크 연결 허용 여부를 물으면 허용해야 합니다. 방화벽을 사용하는 경우 UDP `45678` 포트를 허용하세요.

화면 효과만 미리 볼 수도 있습니다.

```bash
mac-arrow demo
```

## 로컬 개발

```bash
swift test
swift run mac-arrow demo
```

## 현재 범위

- 같은 Wi-Fi/LAN에서 IP 또는 `*.local` 호스트명으로 연결
- 오른쪽 화면 가장자리에서 화살이 날아와 꽂힌 뒤, 수신기를 종료할 때까지 그대로 남는 투명 오버레이
- `--y`로 발사 높이 전달

전역 단축키, 자동 상대 검색, 인터넷 원격 연결은 다음 단계로 추가할 수 있습니다.
