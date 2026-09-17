# MMORPG

**고도(Godot) 엔진**으로 만드는 MMORPG. 로우폴리 3D + 고정 쿼터뷰, 목표는 모바일 앱이다.

브라우저에서도 확인할 수 있다 — **https://gogoalswo.github.io/MMORPG/**

옛 three.js 웹 클라이언트는 2026-09-17 에 지웠다. 두 벌이 있으니 어느 쪽을 고칠지
헷갈려서다. 기능별 구현 문서는 [docs/features/](docs/features/README.md) 를 보고,
**코드를 고치기 전에 문서를 먼저 읽는다** ([CLAUDE.md](CLAUDE.md)).

## 실행

고도 에디터로 `godot/` 폴더를 연다. 엔진은 저장소에 없다 — [고도 4.7.2](https://godotengine.org/download)
를 받아 쓴다.

```bash
npm install
npm run export:godot   # shared 표를 godot/data/*.json 으로
npm run sync:godot     # 모델·폰트·바닥 텍스처를 godot/assets 로
npm run test:godot     # 고도 테스트 (통과는 한 줄, 실패만 자세히)
```

| 명령 | 설명 |
|---|---|
| `npm run export:godot` | `packages/shared` 의 존·몬스터·아이템·스킬 표를 JSON 으로 |
| `npm run sync:godot` | 에셋을 `godot/assets` 로 (모델은 텍스처를 512px 로 줄인다) |
| `npm run test:godot` | 고도 테스트 — 판정·화면·모델까지 헤드리스로 |
| `npm test` | 공유 로직 테스트 (Node 내장 러너) |
| `npm run typecheck` | 타입 검사 |
| `npm run server` | 옛 Colyseus 서버. 출력을 `logs/server.log` 에도 남긴다 |
| `npm run probe -- state` | 그 서버에 헤드리스로 붙어 상태를 글로 찍는다 |
| `./scripts/fetch-assets.sh` | CC0 에셋 다운로드 |
| `npm run compress` | 바닥 텍스처 KTX2 압축 |

`main` 에 밀면 CI 가 테스트를 돌리고 **GitHub Pages 에 배포**한다 (약 1분 15초).
안드로이드 APK 는 Actions 의 `Android APK` 산출물로 나온다.

## 조작

폰과 브라우저에서 같다 — **바닥을 누르면** 그리로 걸어가고, **몬스터를 누르면**
사거리까지 가서 계속 친다. 아래 액션바 네 칸이 스킬, 옆의 `스킬`·`가방` 이 창을 연다.
마을의 파란 원반(차원문)을 밟으면 사냥터를 고른다.

## 구조

```
godot/            게임 본체
  world/          판정 — World(존·전투·몬스터 AI) · Combat · Items · Skills · Movement
  net/            Transport — 화면과 판정 사이의 유일한 통로
  game/           화면 — 카메라·바닥·모델·UI
  tests/          헤드리스 테스트 (판정부터 눌러서 걷는 것까지)
  data/           shared 에서 내보낸 표 (손으로 고치지 않는다)
packages/
  shared/         수치와 생성기 — 존 21 · 몬스터 60 · 장비 280 · 스킬 34
  server/         옛 Colyseus 서버. 판정 원본이라 남겨 뒀다
scripts/          내보내기·에셋 동기화·테스트 러너
```

**판정은 `World` 한 곳에서 한다.** 화면이 보내는 건 전부 요청이고, 사거리·쿨타임·
소지 여부·직업·레벨은 `World` 가 다시 본다. 지금은 로컬에서 직접 부르고, 나중에
고도 헤드리스 서버가 **같은 코드**를 돌린다 — 그래서 판정이 한 벌로 유지된다.

## 더 볼 것

| | |
|---|---|
| [docs/features/README.md](docs/features/README.md) | 기능별 문서. **코드를 고치기 전에 여기부터** |
| [docs/features/godot-migration.md](docs/features/godot-migration.md) | 어디에 무엇이 있는지, 옮긴 것과 안 옮긴 것, 빌드·배포·확인 |
| [docs/ASSETS.md](docs/ASSETS.md) | 에셋 출처와 라이선스 |
| [CLAUDE.md](CLAUDE.md) | 이 저장소에서 일하는 방식 |
