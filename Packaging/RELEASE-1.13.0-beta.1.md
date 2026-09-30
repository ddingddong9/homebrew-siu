# SIU 1.13.0 beta 1 — 1대1 홈 · 누끼 개인기 · 공 움직임

- 앱 실행 시 축구장 메인 대기 화면: 방 만들기, 방 참가, AI 연습, 설정, 조작 안내.
- 사용자 제공 원본 GIF에서 추출한 71개 투명 프레임: 득점 후 호날두 세레머니, E 발재간, Q 백숏.
- 발재간은 공 소유 중, 백숏은 공 근처에서 바라보는 방향의 반대로 발동. E/Q는 SIU 추가 키.
- AI 연습 및 LAN 대전 지원. 호스트가 판정하고 상대에게 동작 이벤트를 전달.
- 공 무늬 회전, 드리블 발끝 터치, 높이별 그림자, 슛 잔상, 작은 착지 바운스.
- 화면 효과 설정 저장, 연습 종료 후 홈 복귀.

## 설치 / 업데이트

```sh
brew update
brew upgrade --cask ddingddong9/siu/siu-app-beta
```

처음 설치할 때:

```sh
brew tap ddingddong9/siu
brew trust --cask ddingddong9/siu/siu-app-beta
brew install --cask ddingddong9/siu/siu-app-beta
```

앱을 종료한 뒤 업데이트하세요. 두 Mac 모두 이 버전을 사용해야 합니다(1대1 LAN 프로토콜 10).
macOS 13 이상, Apple Silicon/Intel universal 빌드. 배포 ZIP 직접 설치는 Xcode/Command Line Tools가 필요 없습니다.
임시 서명이며 Apple 공증은 아직 없습니다. 신뢰하는 같은 와이파이에서만 사용하세요.

## 검증과 제한

물리·메시지 인증·루프백 UDP 양방향 새 동작 이벤트·Bonjour 방 검색·참가/거절 시뮬레이션과
71개 누끼 프레임 alpha 검사를 실행했습니다. 동일 프로세스/한 Mac 검증이며 실제 두 Mac LAN 대전은
별도 검증이 필요합니다. 영상 원본의 낮은 해상도, 프레임 밖으로 잘린 부분, 상대에게 가려진 부분은
누끼 프레임에도 한계가 있습니다. 영상 사용·배포 권한은 사용자 확인에 근거합니다.
