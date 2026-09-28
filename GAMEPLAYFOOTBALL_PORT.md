# GameplayFootball M4 Mac 포팅·LAN 프로토타입 현황

기준 소스는 `Vendor/GameplayFootball`의 고정 커밋 `68159a2f0f96eec8ebba26ab7820130f36b922a7`이다. 원본 파일은 수정하지 않고 `GameplayFootballPatches/`의 순서 있는 패치를 빌드 시 임시 소스에 적용한다. 원본 라이선스는 Apache-2.0이며, 번들 안의 개별 글꼴·자산 고지도 배포 시 확인해야 한다.

## 빌드와 실행

Apple Silicon Mac에서 Xcode Command Line Tools와 Homebrew가 필요하다. 테스트에 사용한 의존성은 CMake, Ninja, SDL2 호환 라이브러리, SDL2_image, SDL2_ttf, SDL2_gfx, Boost, OpenAL, SQLite다.

친구가 **현재 Git 브랜치를 받아 자기 Mac에서 빌드**한다면 Command Line Tools가 필요하다(`xcode-select --install`). 전체 Xcode 앱은 필요하지 않다. 현재 `GameplayFootballDev.app`은 Homebrew 동적 라이브러리를 함께 넣지 않은 개발용 묶음이어서, 앱 폴더만 복사해 설치하는 방식도 아직 지원하지 않는다. 추후 의존성을 포함한 배포용 앱을 만들면 친구 Mac에서 컴파일할 필요가 없어 Command Line Tools 요구를 없앨 수 있다.

```sh
brew install cmake ninja sdl2-compat sdl2_image sdl2_ttf sdl2_gfx boost openal-soft
git submodule update --init Vendor/GameplayFootball
Scripts/build-gameplayfootball-macos.sh --run
```

개발용 빠른 경기와 IP 직접 연결 프로토타입은 다음과 같이 실행한다. 두 Mac에는 같은 커밋·패치·데이터와 같은 포트를 사용한다. 방장 IP는 방장 Mac의 Wi-Fi IPv4 주소이며, `127.0.0.1`은 같은 Mac의 두 프로세스 시험에만 쓴다.

```sh
# 방장 Mac
Scripts/build-gameplayfootball-macos.sh --lan-host --run

# 참가 Mac (방장 주소로 교체)
Scripts/build-gameplayfootball-macos.sh --lan-join=192.168.0.10 --run

# 전송 계층 회귀 시험
Scripts/test-gameplayfootball-lan.sh
```

`--lan-host`와 `--lan-join`은 원본 디버그 빠른 경기를 자동으로 켠다. `--lan-port=38245`로 양쪽 UDP 포트를 함께 바꿀 수 있다. 현재는 방 검색·승인·연결 상태 UI가 없으므로 친구용 실행 방식이 아닌 G2 개발 시험용이다. macOS 방화벽이 UDP 수신을 막는 경우 허용이 필요하다. 빌드 결과의 경로에서 `Scripts/package-gameplayfootball-dev-app.sh /tmp/…/build`를 실행하면 개발용 `.app`을 만들 수 있지만 동적 라이브러리를 포함한 배포용 앱은 아니다.

스크립트는 소스를 `/tmp/siu-gameplayfootball.*`에 복사해 빌드한다. 원본 체크아웃의 CMake 시작이 macOS의 경로 정규화 단계에서 멈춘 현상이 있어, 작업 디렉터리도 임시 경로로 옮긴다. 스크립트가 빌드 실행 파일과 로그 경로를 출력한다. 빌드 후 재실행은 표시된 `build` 디렉터리에서 `./gameplayfootball`을 실행한다. 게임 데이터와 설정은 그 디렉터리에 복사된다.

`build/football.config`에 `"siu_defense_mode" "basic"`을 한 줄 추가하면 기본수비 입력 배치로 전환된다. 기본값은 `tactical`이다. 이 설정은 키 바인딩을 위한 초기 포팅이며, 게임 안 프리셋 선택 UI는 아직 없다.

## 검증한 범위

- M4 Mac에서 AppleClang으로 arm64 실행 파일 컴파일에 성공했다.
- macOS 메인 스레드에서 SDL 비디오·창·이벤트·OpenGL 렌더러를 실행하도록 옮겼다. OpenGL 4.1 컨텍스트, 셰이더, 프레임버퍼 초기화와 오디오 초기화가 통과했다.
- 원본 메뉴 장면이 생성되고 경기 스케줄러가 실행되며, 종료 신호 후 렌더러·오디오·작업 스레드가 정리되는 것을 로그로 확인했다.
- GLSL 150 core에서 제거된 `texture2D()` 호출을 빌드용 복사본에서 `texture()`로 바꾼다.
- FC온라인 공식 안내의 기본 공격키(방향키, W/A/S/D, E, C)와 두 수비 프리셋의 Q/S/D/Z 배치를 원본 HID 기능에 연결했다. 기본수비에서 S 패스가 선수 교체도 실행하지 않도록, 공을 소유한 팀인지 확인하는 조건을 추가했다. 창 포커스를 잃으면 눌린 키 상태를 해제한다. 두 프리셋 모두 설정을 읽고 메뉴 루프까지 시작하는 것을 확인했다.
- 디버그 빠른 경기에서 `Match`·22명·경기장·심판 생성과 수 분간 실행을 로그로 확인했다. 화면은 아직 직접 확인하지 못했다.
- LAN UDP 프로토콜 v3의 입력(24B)과 상태(1,132B) 직렬화·역직렬화, 순서/크기/유한 실수 검사 및 루프백·제3자 패킷 차단 테스트가 통과했다. 방장은 원격 HID 입력을 읽고, 참가자는 선수 22명의 위치와 렌더링 애니메이션/프레임/방향, 공, 점수·시간·경기 단계를 받는다.
- 같은 M4 Mac의 두 게임 프로세스에서 약 10초의 경기 틱 동안 원격 입력 1,002개와 상태 249개 수신을 확인했다. 클라이언트의 렌더링 자세 5,478개가 표시 버퍼에 수락됐다. 위치 교정 전 평균 선수 차이는 약 0.045m, 공 차이는 약 0.001m였다. 이 수치는 키 입력이 없는 로컬 시험이며, 실제 패스·슛·골 일치 또는 다른 두 Mac의 Wi-Fi 연결을 입증하지 않는다.

아직 화면의 정상 표시, 실제 키보드 플레이, 골키퍼 수동 위치 조정·상황별 배급, FC온라인 복합 슛/패스·개인기, 두 Mac LAN 대전은 검증·구현되지 않았다. OpenGL 실행 중 텍스처 샘플러 관련 드라이버 경고가 1회 발생해 화면 검증이 필요하다. 키 배치는 맞춰 가는 중이지만 원본 게임의 액션 의미와 FC온라인의 정확한 동작이 동일하다는 뜻은 아니다.

LAN도 아직 G2 통과가 아니다. 참가 Mac은 자체 경기 시뮬레이션을 계속 돌린 뒤 호스트 상태로 위치·표시 자세·점수를 보정한다. 무입력 시험에서도 로컬 시뮬레이션의 애니메이션 선택은 약 73% 달랐다. 표시 버퍼의 호스트 자세 적용은 빌드·실행 수준만 확인했고 눈으로 확인하지 못했다. 발-공 접촉 이벤트, 규칙 이벤트, 선택 선수, 입력 유실 재전송, 시간 보간, 콘텐츠 해시·인증, 연결 해제/재접속은 미완성이다. 현재 구현을 공정한 대전이라고 볼 수 없다.

다음 관문은 화면에서 메뉴→경기·양쪽 키보드·패스·슛·골을 관찰하고 두 M4 Mac Wi-Fi에서 재시험하는 것이다. 그 결과를 바탕으로 참가자 자체 판정을 제거하고 규칙/접촉 이벤트를 호스트만 확정하도록 분리해야 한다. 전체 목표와 완료 기준은 [기획서](GAMEPLAYFOOTBALL_LAN_PLAN.md)를 따른다.
