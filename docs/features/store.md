# 상점

## 무엇

오른쪽 위 평소 줄의 **상점** 단추(2026-10-02 — 가방 옆, 던전 자리)로 여는 전체 화면 창이다. 위에 **메인 카테고리 탭**, 왼쪽에 **서브 카테고리 목록**,
오른쪽에 **상품 카드 격자(3열)** 가 선다. **지금은 카테고리만 있고 상품은 없다** — 빈 서브는 "판매 중인 상품이
없습니다." 한 줄을 띄운다.

요청 (2026-10-02): 다른 게임의 상점 스크린샷 + "이런식으로 상점 만들거야 … 상품 패스 교환소 이쪽이 메인
카테고리고, 프로모션 클래스체인지 이쪽이 서브 카테고리야. 항목은 우선 상품이랑 월정액 메인 카테고리 넣고, 서브는
초보자 패키지, 재화 이렇게만 넣어. 월정액은 서브 카테고리로 상품만 넣고. 구체적인 상품은 아직 안 넣을꺼야".

| 메인 | 서브 |
|---|---|
| 상품 (`goods`) | 초보자 패키지 (`starter`) · 재화 (`currency`) |
| 월정액 (`monthly`) | 상품 (`goods`) |
| 뽑기 (`draw`) | 트레이너 (`trainer`) — ★ 2026-10-06, **유일하게 상품이 있다**: 1회 · 10회 (다이아) → [trainers.md](trainers.md) |

```
 돌판 틀(ui_dungeon_card, 전체 화면) ─────────────────────────────── X
 │ 상품 │ 월정액 │                                      상점   │  ← 메인 탭 (고른 것 금빛 글자 + 밑줄)
 ├──────────────┬──────────────────────────────────────────────┤
 │▌초보자 패키지 │ ┌ 이름 ─────┐ ┌──────────┐ ┌──────────┐     │
 │  재화         │ │ 설명       │ │          │ │          │     │  ← 상품 카드 3열 (세로 스크롤)
 │               │ │  [그림]    │ │          │ │          │     │
 │               │ │ KRW 55,000 │ │          │ │          │     │
```

## 어디

| 파일 | 역할 |
|---|---|
| `godot/game/store_panel.gd` `StorePanel` | 창 전부 — `CATEGORIES`(메인 → 서브 표) · 탭 · 서브 줄 · 카드(`_card`) · `set_products` |
| `godot/game/game.gd` `_toggle_store` · `_build_gate_panel` | 평소 줄의 "상점"(가방 옆, `MENU_QUICK`), 창을 헬스·도감 창과 같은 층(10)에 · 뒤에 불투명한 판(`StoreBack`) |
| `godot/tests/ui_test.gd` `_case_store` | 메뉴로 열림 · 탭 둘 · 서브 · 빈 안내 · 제목이 X 와 안 겹침 · 상품을 넣으면 카드 · X 로 닫힘 |
| `godot/tools/shot.gd` | `npm run shot:godot -- store` → `logs/shot_store.png` |

## 규칙

- **결은 다른 창과 같다** ([ui-art-style.md](ui-art-style.md) "창은 던전 결") — 돌판 틀, 메인 탭은 헬스 창 탭
  (`FitnessPanel._paint_tab`), 서브 줄은 던전 단계 창의 목록 줄(`GatePanel._row_box` — 고른 줄만 옅은 금빛 바탕 +
  왼쪽 금 막대), 카드는 어두운 평판 + 가는 흙금빛 선(`CELL_BG` · `CELL_LINE`). 받은 그림의 결을 새로 지어내지 않았다.
- 창 이름 "상점" 은 받은 그림처럼 **탭 줄 오른쪽 끝**이다. X 가 그 모서리에 서서 `TITLE_ROOM`(72) 만큼 비운다.
- 메인 탭을 바꾸면 서브는 **첫째로** 돌아간다.
- 카드 한 장 = `{name, note?, icon?, price}` — `price` 는 원 정수, `KRW 55,000` 으로 적는다. `icon` 은 `_icon` 이 찾는
  이름(없으면 그림 자리만 빈다).
- ★ **다이아 상품** (2026-10-06) — `{id, diamonds, art?}` 이면 값 자리가 **"다이아 N" 사기 단추**(`buy`, 청록 돌판 `GatePanel.paint_stone_button`)가 되고 누르면
  `buy_requested(id)` 를 낸다. `art` 는 그림을 바로 준 것. 뽑기 두 상품은 `icon` 으로 **바르코 카드 그림**
  (`ui_draw_trainer_1` · `_10`, 2026-10-07 — 전에는 트레이너 원화) → [trainers.md](trainers.md) "상점 상품 그림". 탭 줄 오른쪽에 **가진 다이아**(`set_diamonds`)를 적는다.
  뽑기 결과는 창 위에 덮는 **3D 연출 판**(`show_draw` → `TrainerDraw` — 밀랍 조각상이 내려서고 [모두 보기] 로 카드가 선다 · NEW · 확인)이다 → [trainers.md](trainers.md) "뽑기 연출"
- 메뉴 그림 `ui_icon_shop` 은 **끈 묶은 가죽 돈주머니**다 (2026-10-02 요청 "상점 아이콘도 바르코로 만들어").
  HUD 아이콘 기준([ui-art-style.md](ui-art-style.md) "HUD 아이콘 기준 (2026-09-29)") 프롬프트에 `<무엇>` 만
  `a plump leather coin pouch tied shut with a cord at the neck, two or three coins resting at its base` 로,
  참고 그림 둘을 물려 세 장 → 셋째. 해시는 `scripts/fetch-assets.sh`.

## 상품을 붙일 때

- **상품 표는 `packages/shared` 에 둔다**(값·지급 내용은 공유 수치다) → `npm run export:godot` 로 `godot/data` 에
  내보내고 `StorePanel.set_products("<메인>/<서브>", [...])` 로 채운다. 지금 `CATEGORIES` 는 창 구조라 창에 뒀다.
- **결제·지급은 서버가 판정한다** — 영수증 검증은 [server.md](server.md) "다이아" 와 같은 길이다. 창은 요청만 보낸다.
- 받은 그림의 "18일 후 판매 종료" · "계정별 매월 (0/2)" · NEW/STEP 깃발은 아직 안 만들었다 — 상품이 생길 때 같이.

## 관련

- [hud.md](hud.md) "메뉴 판" — 상점 단추가 서는 곳
- [ui-art-style.md](ui-art-style.md) — 창 결
- [server.md](server.md) — 다이아 결제(영수증 검증)
- [npc-town.md](npc-town.md) — 옛 NPC 상점(골드로 사고팔기)은 이것과 다르다
