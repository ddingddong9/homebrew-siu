# SIU 오픈소스 축구게임 조사

확인일: 2026-09-28. 저장소 설명뿐 아니라 라이선스, 소스 일부, CI 작업 결과를 확인했다. 아래 프로젝트를 이 Mac에서 빌드하거나 플레이한 것은 아니다. 외부 코드/자산을 SIU에 편입하지 않았다.

## 결론

11대11 3D 경기의 전체 기반 후보는 **League-Soccer**, 가벼운 2D 행동 구조 참고는 **Super Soccer / soccer-course**, 공 물리·AI의 비교 기준은 **Google Research Football**이다. EA FIFA/FC의 공식 소스가 아니라 별도로 개발된 축구게임들이다.

이전 재설계의 ‘Swift 시뮬레이션 자체 구현’을 유일한 길로 확정하지 않는다. 기존 SIU를 보존하면서 League-Soccer의 독립 실행을 먼저 검증해, 검증된 축구 코어를 활용하는 것이 실제로 더 나은지 판단한다. 빌드 통과만으로 경기 품질·macOS 실행·LAN 대전·재배포 준비 완료를 판단하지 않는다.

## 후보 비교

| 후보 | 확인한 강점 | 제한과 SIU 적용 판단 |
| --- | --- | --- |
| [League-Soccer](https://github.com/awest813/League-Soccer) | Gameplay Football 계열 C++ 3D 경기, 선수/팀 AI, 애니메이션 접촉 프레임, 공 회전/마찰. 루트 Apache-2.0. 최근 macOS 빌드 성공 | 전체 기반 1순위 검증 후보. 기존 Swift/RealityKit에 바로 끼우는 라이브러리가 아님. 메뉴/경기/렌더러 결합과 자산 출처 확인 필요 |
| [Google Research Football](https://github.com/google-research/football) | 11대11 연구용 환경, 물리 기반 3D 경기, 키보드 제어와 팀 전환. 루트 Apache-2.0, 포함 엔진은 별도 Unlicense | 저장소가 2026-08-19 보관 상태. 문서상 사람 입력이 100ms당 한 행동이라 지연 가능. 연구용 래퍼를 그대로 SIU 조작 계층으로 쓰기에는 부적절 |
| [Super Soccer / soccer-course](https://github.com/nicolasbize/soccer-course) | Godot 2D, MIT. 이동·슛 준비·슛·태클·피격·회복·골키퍼 다이빙을 별도 상태로 구성. 유니폼 색 교체 셰이더 | 테크모풍 행동 구조 참고에 적합. 3D 중계 카메라/11대11/LAN 완성 기반으로 검증된 것은 아님. 직접 본 이동 코드는 즉시 속도 설정, 슛은 애니메이션 완료에 발사하므로 SIU의 개선 요구에 맞춰 수정해야 함 |
| [OpenSWOS](https://github.com/angree/openswos) | Godot 4 + C#의 SWOS 재구현. 자체 소스에 MIT 명시 | 초기 작업물이며 원본 Amiga 게임 파일이 필요. 원본 게임 자산은 라이선스에 포함되지 않음. 친구에게 독립 설치시키려는 SIU의 즉시 기반으로는 우선순위 낮음 |

추가 제외: [GodotBasic3DFootball](https://github.com/richardschembri/GodotBasic3DFootball)은 2018년 마지막 푸시, API에서 라이선스 미표시. 공개 저장소라는 이유만으로 코드를 재배포하지 않는다. [원본 GameplayFootball](https://github.com/BazkieBumpercar/GameplayFootball)은 개발자가 구조적 문제와 엔진의 테스트/문서 부족을 직접 경고하며 참고용 활용을 권한다.

## League-Soccer: 설명과 검증 사실 구분

검토 커밋: `a570c29613c114e1320065da91733aba7b35d15f`.

- [2026-09-18 CI 실행](https://github.com/awest813/League-Soccer/actions/runs/35405792831)의 전체 표시는 실패이지만, 작업별 API 결과는 macOS 14 / Ubuntu / Windows 빌드와 headless tests 성공이다. 실패 작업은 코드 포맷 검사다. ‘Mac 빌드 실패’라고 해석하면 안 된다.
- [CI 정의](https://github.com/awest813/League-Soccer/blob/a570c29613c114e1320065da91733aba7b35d15f/.github/workflows/ci.yml)의 실제 경기 smoke test는 Linux 쪽에 있다. macOS 빌드 성공은 Mac에서 입력·렌더링·경기 전체가 정상이라는 증거와 다르다.
- [선수 애니메이션](https://github.com/awest813/League-Soccer/blob/a570c29613c114e1320065da91733aba7b35d15f/src/onthepitch/player/humanoid/humanoid.cpp)은 `touchFrame == frameNum`에서 접촉 위치·공과의 거리를 검사한다. SIU에서 가장 부족했던 ‘다리 동작과 실제 공 반응 일치’를 검토할 구체적인 참고점이다.
- [공](https://github.com/awest813/League-Soccer/blob/a570c29613c114e1320065da91733aba7b35d15f/src/onthepitch/ball.cpp)에는 지면 마찰·반발과 회전에 따른 곡선 비행 처리가 있다. SIU에서 별도로 검증할 물리 기준으로 유용하다.
- [macOS 패키징](https://github.com/awest813/League-Soccer/blob/a570c29613c114e1320065da91733aba7b35d15f/scripts/package_macos.sh)은 확인한 커밋에서 실행 파일과 설정/자료 폴더를 복사한다. 주석의 설명과 달리 동적 라이브러리 복사·경로 수정·`.app` 생성·서명·공증 처리는 본문에서 확인되지 않는다. ‘Xcode/Homebrew 의존성 없는 친구용 앱’은 추가 구현 대상이다.
- 기존 SIU의 Bonjour 방 검색·동시 일시정지·숨겨진 개인기·업데이트 안내를 이 후보가 그대로 제공한다고 확인하지 않았다.

## 2D 후보에서 실제로 확인한 것

검토 커밋: `nicolasbize/soccer-course@c28147f5e5a37e0fa9ecd3157d80352dc1109f70`.

- [이동](https://github.com/nicolasbize/soccer-course/blob/c28147f5e5a37e0fa9ecd3157d80352dc1109f70/scenes/characters/character_states/player_state_moving.gd): 입력 방향에 속도를 바로 대입. 가속/제동/턴 관성은 그대로 얻을 수 없다.
- [슛](https://github.com/nicolasbize/soccer-course/blob/c28147f5e5a37e0fa9ecd3157d80352dc1109f70/scenes/characters/character_states/player_state_shooting.gd): kick 애니메이션이 완료되면 발사. 발 접촉 프레임 이벤트로 바꿔야 한다.
- [태클](https://github.com/nicolasbize/soccer-course/blob/c28147f5e5a37e0fa9ecd3157d80352dc1109f70/scenes/characters/character_states/player_state_tackling.gd): 태클 중 피해 판정 영역 활성화, 마찰 감속, 회복 상태 전환. SIU가 원한 태클→피격→회복 흐름에 참고 가능하다.
- [플레이 가능한 제작자 데모](https://gadgaming.itch.io/super-soccer)는 로컬 1~2인 플레이를 안내한다. 서로 다른 Mac의 LAN 대전과 같은 의미는 아니다.

## 다음 구현 의사결정

1. 기존 SIU/1대1 코드는 보존한다. 아직 외부 엔진으로 전환하지 않는다.
2. 별도 실험 경로에서 League-Soccer의 고정 커밋을 검토 후 빌드한다. 의존성 설치 스크립트를 검토 없이 실행하지 않는다.
3. Mac에서 30초 이동/제동/급회전/드리블/패스/슛/태클/골키퍼 영상을 확인하고 5분 경기를 완주한다. 입력 반응과 공 접촉을 직접 평가한다.
4. 자연스러운 동작이 확인되면 코어 재사용 범위를 결정한다. 엔진의 3D 애니메이션에 축구 계산이 결합되어 있다면 2D GIF로 단순 교체하지 않고 접촉 시점·발 위치를 전달하는 연결 계층을 설계한다. 사용자에게 선수까지 3D로 바꾸는 선택을 강요하지 않는다.
5. 독립 코어 활용 비용이 지나치게 크면 기존 설계의 metric/fixed-step Swift 코어를 진행하고, 외부 프로젝트는 행동/물리 검증의 참고로 한정한다.
6. 어느 길이든 두 Mac LAN·기존 개인기·App 번들·Homebrew 설치는 별도 인수검증을 거친다. 외부 라이선스/고지와 모델·음악·폰트 등 자산의 권리는 파일별로 점검한다.

현재 상태: 조사 및 설계 갱신 완료. 외부 의존성 설치, 엔진 편입, 기존 게임 실행 코드 변경, 공개 배포는 하지 않았다.
