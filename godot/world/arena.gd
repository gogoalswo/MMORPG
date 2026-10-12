class_name Arena
extends RefCounted

## 결투장 (docs/features/arena.md) — 남의 캐릭터 **복사본**과 AI 끼리 싸운다. 실시간 PVP 가 아니다
## (2026-10-12 요청 "상대방 데이터는 서버에서 받아서 복사해서 사용할거야. 실시간 PVP가 아니라는 말이야").
##
## 지금은 **더미 50명**이다 ("일단 더미로 50개 만들어"). 서버(`LedgerServer._arena_board`)도 로컬
## (`LocalTransport`)도 이 `board` 를 그대로 돌려준다 — 진짜 상대(다른 계정의 장부 복사본)를 붙일 때
## 서버 쪽만 바꾸면 창은 그대로다. 결투(AI 대 AI)는 아직 없다.

const DUMMY_COUNT := 50
## 처음 들어온 사람의 결투 점수. 결투가 없어서 지금은 늘 이 값이다 (장부 칸도 아직 없다)
const START_SCORE := 1000
## 더미 점수 — 1위가 `DUMMY_TOP_SCORE`, 한 줄 내려갈 때마다 `DUMMY_SCORE_STEP` 씩.
## 1490 ~ 510 이라 처음 들어온 나(1000)는 26위 — 위로도 아래로도 상대가 보인다
const DUMMY_TOP_SCORE := 1490
const DUMMY_SCORE_STEP := 20
## 더미 레벨은 **내 레벨 ± 5** — 점수가 높을수록 높다. 고정 레벨이면 1레벨이 200레벨만 보게 된다
const DUMMY_LEVEL_SPREAD := 5
## 이름은 두 표를 겹쳐 짓는다 — 50명이 서로 다르게 (`dummy_name`)
const NAME_HEADS := ["푸른", "검은", "붉은", "하얀", "황금", "은빛", "거친", "고요한", "빛나는", "잠든"]
const NAME_TAILS := ["늑대", "매", "곰", "호랑이", "여우", "사자", "독수리", "용", "표범", "까마귀"]


## i 번째 더미 이름. 앞말은 i % 10, 뒷말은 (i / 10 × 3 + i % 10) % 10 — i < 50 이면 짝이 겹치지 않는다
static func dummy_name(i: int) -> String:
	return NAME_HEADS[i % 10] + NAME_TAILS[(floori(i / 10.0) * 3 + i % 10) % 10]


## 더미 상대 50명 — 점수 높은 순. 한 줄은 상대의 **복사본** `{id, name, job, level, score, power}`
## (`power` 는 자동 장착이 견주는 전투력 `Ledger.gear_power` — 더미는 맨몸이다)
static func dummies(my_level: int) -> Array:
	var max_level := int(GameData.combat().get("maxLevel", 200))
	var out: Array = []
	for i in DUMMY_COUNT:
		var lift := roundi((DUMMY_COUNT / 2.0 - 0.5 - i) * DUMMY_LEVEL_SPREAD / (DUMMY_COUNT / 2.0))
		var copy := {
			"id": "dummy_%02d" % (i + 1),
			"name": dummy_name(i),
			"job": "fighter",
			"level": clampi(my_level + lift, 1, max_level),
			"score": DUMMY_TOP_SCORE - DUMMY_SCORE_STEP * i,
		}
		copy["power"] = roundi(Ledger.gear_power(copy, {}))
		out.append(copy)
	return out


## 결투장 표 — 창이 받는 답 하나. `me` 는 장부(`job` · `level` · `equipped` …)에 `name` 을 얹은 것.
## `{t, ranking: [줄 + rank (내 줄은 me: true)], challengers: [더미 줄 + rank], me: {rank, score, power, level, name}, total, dummy}`
static func board(me: Dictionary) -> Dictionary:
	var challengers := dummies(int(me.get("level", 1)))
	var mine := {
		"id": "me", "name": str(me.get("name", "")), "job": str(me.get("job", "fighter")),
		"level": int(me.get("level", 1)), "score": START_SCORE,
		"power": roundi(Ledger.gear_power(me, me.get("equipped", {}))), "me": true,
	}
	var ranking: Array = challengers.duplicate()
	ranking.append(mine)
	# 같은 점수면 먼저 있던 쪽(더미)이 앞 — sort_custom 은 안정 정렬이 아니라 번호로 가른다
	var order := {}
	for i in ranking.size():
		order[ranking[i].id] = i
	ranking.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.score) != int(b.score):
			return int(a.score) > int(b.score)
		return int(order[a.id]) < int(order[b.id]))
	# 줄은 같은 Dictionary 라 `challengers` 에도 순위가 실린다
	for i in ranking.size():
		ranking[i]["rank"] = i + 1
	return {
		"t": "arenaBoard", "ranking": ranking, "challengers": challengers,
		"me": {"rank": int(mine.rank), "score": int(mine.score), "power": int(mine.power),
			"level": int(mine.level), "name": mine.name},
		"total": ranking.size(), "dummy": true,
	}
