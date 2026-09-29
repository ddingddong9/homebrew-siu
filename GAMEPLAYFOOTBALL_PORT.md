# GameplayFootball M4 Mac 포팅·LAN 프로토타입 현황

기준 소스는 `Vendor/GameplayFootball`의 고정 커밋 `68159a2f0f96eec8ebba26ab7820130f36b922a7`이다. 원본 파일은 수정하지 않고 `GameplayFootballPatches/`의 순서 있는 패치를 빌드 시 임시 소스에 적용한다. 원본 라이선스는 Apache-2.0이며, 번들 안의 개별 글꼴·자산 고지도 배포 시 확인해야 한다.

다른 Mac에서 이어서 개발하는 순서는 [GameplayFootball 개발 인수인계](GAMEPLAYFOOTBALL_HANDOFF.md)를 따른다.

## 빌드와 실행

Apple Silicon Mac에서 Xcode Command Line Tools와 Homebrew가 필요하다. 테스트에 사용한 의존성은 CMake, Ninja, SDL2 호환 라이브러리, SDL2_image, SDL2_ttf, SDL2_gfx, Boost, OpenAL, SQLite다.

친구가 **현재 Git 브랜치를 받아 자기 Mac에서 빌드**한다면 Command Line Tools가 필요하다(`xcode-select --install`). 전체 Xcode 앱은 필요하지 않다. 빌드가 끝나면 결과 폴더에 기존 SIU 아이콘을 쓴 `SIU Football.app`을 자동 생성한다. 이 기본 앱은 Homebrew 동적 라이브러리를 함께 넣지 않은 개발용 묶음이다.

macOS 26 Apple Silicon 테스트용으로 라이브러리를 포함한 압축 앱도 만들 수 있다. 두 번째 Mac은 이 압축 파일을 내려받아 풀고 앱을 열 수 있으며, 소스 빌드나 Homebrew 설치가 필요하지 않다. 현재 서명은 임시 서명이고 Apple 공증은 없으므로 다운로드한 Mac에서 첫 실행 시 보안 설정의 **열기 허용**이 필요할 수 있다. 이 절차는 별도 Mac에서 아직 검증하지 않았다.

```sh
Scripts/build-gameplayfootball-macos.sh --quick-match
python3 Scripts/package-gameplayfootball-test-app.py \
  "dist/SIU Football.app" "dist/SIU-Football-macos26-arm64-test.zip"
```

```sh
brew install cmake ninja sdl2-compat sdl2_image sdl2_ttf sdl2_gfx boost openal-soft
git submodule update --init Vendor/GameplayFootball
Scripts/build-gameplayfootball-macos.sh --run
```

개발용 빠른 경기는 `dist/SIU Football.app`의 SIU 로비에서 시작한다. IP 직접 연결 프로토타입은 다음과 같이 실행한다. 두 Mac에는 같은 커밋·패치·데이터와 같은 포트를 사용한다. 방장 IP는 방장 Mac의 Wi-Fi IPv4 주소이며, `127.0.0.1`은 같은 Mac의 두 프로세스 시험에만 쓴다.

```sh
# 방장 Mac
Scripts/build-gameplayfootball-macos.sh --lan-host --run

# 참가 Mac (방장 주소로 교체)
Scripts/build-gameplayfootball-macos.sh --lan-join=192.168.0.10 --run

# 전송 계층 회귀 시험
Scripts/test-gameplayfootball-lan.sh
```

`--lan-host`와 `--lan-join`은 원본 디버그 빠른 경기를 자동으로 켠다. `--lan-port=38245`로 양쪽 UDP 포트를 함께 바꿀 수 있다. `--run`은 이 두 옵션과 함께 사용하면 C++ 경기를 직접 실행하고, 옵션 없이 사용하면 SIU 로비 앱을 연다. 새 로비에는 Bonjour 방 검색·승인·시작 UI가 있지만 준비 상태·팀 선택·콘텐츠 검사는 아직 없다. macOS 방화벽이 UDP 수신을 막는 경우 허용이 필요하다. 모든 빌드는 기본으로 `dist/SIU Football.app`을 만들며 `--app-output=PATH`로 위치를 바꿀 수 있다. 이 앱은 동적 라이브러리를 포함한 배포용 앱은 아니다.

스크립트는 소스를 `/tmp/siu-gameplayfootball.*`에 복사해 빌드한다. 원본 체크아웃의 CMake 시작이 macOS의 경로 정규화 단계에서 멈춘 현상이 있어, 작업 디렉터리도 임시 경로로 옮긴다. 스크립트가 빌드 실행 파일과 로그 경로를 출력한다. 빌드 후 재실행은 표시된 `build` 디렉터리에서 `./gameplayfootball`을 실행한다. 게임 데이터와 설정은 그 디렉터리에 복사된다.

`build/football.config`에 `"siu_defense_mode" "basic"`을 한 줄 추가하면 기본수비 입력 배치로 전환된다. 기본값은 `tactical`이다. 이 설정은 키 바인딩을 위한 초기 포팅이며, 게임 안 프리셋 선택 UI는 아직 없다.

## 검증한 범위

- M4 Mac에서 AppleClang으로 arm64 실행 파일 컴파일에 성공했다.
- macOS 메인 스레드에서 SDL 비디오·창·이벤트·OpenGL 렌더러를 실행하도록 옮겼다. OpenGL 4.1 컨텍스트, 셰이더, 프레임버퍼 초기화와 오디오 초기화가 통과했다.
- 원본 메뉴 장면이 생성되고 경기 스케줄러가 실행되며, 종료 신호 후 렌더러·오디오·작업 스레드가 정리되는 것을 로그로 확인했다.
- GLSL 150 core에서 제거된 `texture2D()` 호출을 빌드용 복사본에서 `texture()`로 바꾼다.
- FC온라인 공식 안내의 기본 공격키(방향키, W/A/S/D, E, C)와 두 수비 프리셋의 Q/S/D/Z 배치를 원본 HID 기능에 연결했다. 기본수비에서 S 패스가 선수 교체도 실행하지 않도록, 공을 소유한 팀인지 확인하는 조건을 추가했다. 창 포커스를 잃으면 눌린 키 상태를 해제한다. 두 프리셋 모두 설정을 읽고 메뉴 루프까지 시작하는 것을 확인했다.
- 디버그 빠른 경기에서 `Match`·22명·경기장·심판 생성과 수 분간 실행을 로그로 확인했다. 이후 진단용 OpenGL 프레임으로 화면 구성을 확인했다.
- LAN UDP 프로토콜 v3의 입력(24B)과 상태(1,132B) 직렬화·역직렬화, 순서/크기/유한 실수 검사 및 루프백·제3자 패킷 차단 테스트가 통과했다. 방장은 원격 HID 입력을 읽고, 참가자는 선수 22명의 위치와 렌더링 애니메이션/프레임/방향, 공, 점수·시간·경기 단계를 받는다.
- 같은 M4 Mac의 두 게임 프로세스에서 약 10초의 경기 틱 동안 원격 입력 1,002개와 상태 249개 수신을 확인했다. 클라이언트의 렌더링 자세 5,478개가 표시 버퍼에 수락됐다. 위치 교정 전 평균 선수 차이는 약 0.045m, 공 차이는 약 0.001m였다. 이 수치는 키 입력이 없는 로컬 시험이며, 실제 패스·슛·골 일치 또는 다른 두 Mac의 Wi-Fi 연결을 입증하지 않는다.
- SIU 로비를 앱의 첫 화면으로 연결하고 빨강 방장/파랑 참가자 카드로 구분했다. 한 Mac에서 Bonjour 검색→승인→시작 메시지를 검증했고, 로컬 연습 버튼에서 경기 프로세스와 경기장 생성 로그를 확인했다. 기존 GameplayFootball 로딩 그림은 표시하지 않는다.
- 로비가 승인한 참가자의 Wi-Fi IPv4 주소를 경기 호스트에 전달하고, 호스트 UDP는 그 주소의 입력만 수락한다. 현재 패킷 인증은 없으므로 주소 제한만으로 참가자 신원을 증명하지는 않는다.
- macOS OpenGL 프레임을 진단 옵션으로 저장해 1280×720 경기장·22명·점수판·미니맵이 그려지는 것을 확인했다. `SIU_CAPTURE_PATH`와 `SIU_CAPTURE_FRAME`을 설정한 실행에서만 저장한다. 이 확인은 실제 키보드 플레이와 10분 경기 통과를 의미하지 않는다.
- 사용자가 보고한 반복 종료의 macOS 충돌 보고서에서 SDL 비디오/조이스틱 종료 스레드 문제를 확인했다. 비디오는 메인 스레드, 조이스틱은 초기화한 작업 스레드에서 정리하도록 수정한 후 진단용 정상 종료·재실행 2회가 종료 코드 0으로 통과했다.
- 빠른 경기에서 게임패드가 감지되어도 키보드를 빨강 팀에 배정하도록 수정했다. 진단 빌드에서 S 키 눌림/해제가 HID의 짧은 패스 입력까지 전달됐고, 킥오프 휘슬 뒤 S 입력으로 세트피스가 끝나며 경기 시계가 진행되는 것을 확인했다.
- 실제 키보드 조작이 된다는 사용자 확인을 받았다. 원본의 패스 대상 자동 전환을 유지하고, 꺼져 있던 근접 선수 자동 전환을 후보 250ms 유지·도달 시간 차이·전환 후 유지 시간 조건으로 다시 구현했다. 수동 전환은 1.5초 우선한다. 진단 경기에서 킥오프 이후 자동 선택 변화를 확인했지만 패스 수신·수비 각각의 체감은 사용자 재시험이 필요하다.
- macOS 26 arm64 테스트 앱에 Homebrew 동적 라이브러리 35개와 설치된 라이선스 고지를 포함했다. 압축 파일을 풀어 코드 서명을 검사하고, 압축에서 꺼낸 경기 실행 파일의 경기 생성·정상 종료를 확인했다. 다른 Mac의 Gatekeeper 통과와 실제 Wi-Fi 대전은 아직 확인하지 않았다.

아직 10분 경기 완주, 골키퍼 수동 위치 조정·상황별 배급, FC온라인 복합 슛/패스·개인기, 두 Mac LAN 대전은 검증·구현되지 않았다. OpenGL 실행 중 텍스처 샘플러 관련 드라이버 경고가 1회 발생해 화면 검증이 필요하다. 키 배치는 맞춰 가는 중이지만 원본 게임의 액션 의미와 FC온라인의 정확한 동작이 동일하다는 뜻은 아니다.

LAN도 아직 G2 통과가 아니다. 참가 Mac은 자체 경기 시뮬레이션을 계속 돌린 뒤 호스트 상태로 위치·표시 자세·점수를 보정한다. 무입력 시험에서도 로컬 시뮬레이션의 애니메이션 선택은 약 73% 달랐다. 표시 버퍼의 호스트 자세 적용은 빌드·실행 수준만 확인했고 눈으로 확인하지 못했다. 발-공 접촉 이벤트, 규칙 이벤트, 선택 선수, 입력 유실 재전송, 시간 보간, 콘텐츠 해시·인증, 연결 해제/재접속은 미완성이다. 현재 구현을 공정한 대전이라고 볼 수 없다.

다음 관문은 화면에서 메뉴→경기·양쪽 키보드·패스·슛·골을 관찰하고 두 M4 Mac Wi-Fi에서 재시험하는 것이다. 그 결과를 바탕으로 참가자 자체 판정을 제거하고 규칙/접촉 이벤트를 호스트만 확정하도록 분리해야 한다. 전체 목표와 완료 기준은 [기획서](GAMEPLAYFOOTBALL_LAN_PLAN.md)를 따른다.
