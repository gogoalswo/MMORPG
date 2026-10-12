class_name Arena
extends RefCounted

## 결투장 (docs/features/arena.md) — 남의 캐릭터 **복사본**과 AI 끼리 싸운다. 실시간 PVP 가 아니다
## (2026-10-12 요청 "상대방 데이터는 서버에서 받아서 복사해서 사용할거야. 실시간 PVP가 아니라는 말이야").
##
## 상대 목록은 지금 **더미 50명**이다 ("일단 더미로 50개 만들어"). 서버(`LedgerServer._arena_board`)도 로컬
## (`LocalTransport`)도 이 `board` 를 그대로 돌려준다 — 진짜 상대(다른 계정의 장부 복사본)를 붙일 때
## 서버 쪽만 바꾸면 창은 그대로다.
##
## 결투(AI 대 AI, 같은 날 둘째 요청 "AI 결투 만들어")는 `World._start_duel` — 고른 복사본을 `foe` 로
## 몬스터 칸 하나로 세운다. 판의 규칙(카운트 · 시간 · 점수)은 shared 의 `arena.ts` 가 `zones.json` 의 `arena` 로 내보낸다.

const DUMMY_COUNT := 50
## 더미 점수 — 1위가 `DUMMY_TOP_SCORE`, 한 줄 내려갈 때마다 `DUMMY_SCORE_STEP` 씩.
## 1490 ~ 510 이라 처음 들어온 나(`start_score` 1000)는 26위 — 위로도 아래로도 상대가 보인다
const DUMMY_TOP_SCORE := 1490
const DUMMY_SCORE_STEP := 20
## 더미 레벨은 **내 레벨 ± 5** — 점수가 높을수록 높다. 고정 레벨이면 1레벨이 200레벨만 보게 된다
const DUMMY_LEVEL_SPREAD := 5
## 이름은 두 표를 겹쳐 짓는다 — 50명이 서로 다르게 (`dummy_name`)
const NAME_HEADS := ["푸른", "검은", "붉은", "하얀", "황금", "은빛", "거친", "고요한", "빛나는", "잠든"]
const NAME_TAILS := ["늑대", "매", "곰", "호랑이", "여우", "사자", "독수리", "용", "표범", "까마귀"]
## 상대 한 대 간격의 바닥(ms). 몬스터 휘두르기는 손이 닿는 순간(`Combat.monster_hit_delay_ms`, 0.2초)에
## 피해가 들어가서, 그보다 빨리 다시 휘두르면 앞의 한 대가 덮여 사라진다 — 더 빠른 공속은
## **간격을 여기로 늘리고 한 대를 그만큼 세게** 해 초당 피해를 맞춘다 (`foe`)
const FOE_MIN_SWING_MS := 250


static func table() -> Dictionary:
	return GameData.zones().get("arena", {})


static func zone() -> String:
	return str(table().get("zone", "arena"))


static func countdown_ms() -> int:
	return int(float(table().get("countdown", 3)) * 1000.0)


static func play_ms() -> int:
	return int(float(table().get("seconds", 60)) * 1000.0)


static func start_score() -> int:
	return int(table().get("startScore", 1000))


## 결과 뒤 점수 — 이기면 `winScore` 만큼 오르고 지면 `loseScore` 만큼 내린다. 0 아래로는 안 간다
## (shared `arenaNextScore` 와 같은 식)
static func next_score(score: int, won: bool) -> int:
	var t := table()
	return maxi(0, score + (int(t.get("winScore", 20)) if won else -int(t.get("loseScore", 10))))


## 장부의 결투 점수 — 아직 한 판도 안 했으면 시작 점수
static func score_of(p: Dictionary) -> int:
	return int(p.get("arena", {}).get("score", start_score()))


## 상대 복사본 → 몬스터 칸 하나. 틀(`duelist` — 모델 · 움직임)에 **복사본 장부로 계산한 능력치**를 덮어쓴다.
## 공격력 · 방어력 · 체력 · 치명타 · 관통 · 공속 · 사거리가 다 `World.stats_of` 그대로라 **내 캐릭터와 같은 식**이다.
## 피해도 내가 때릴 때와 같은 공식(`Stats.damage`)으로 들어간다 — `World._hit_player` 의 `duel` 갈래
static func foe(copy: Dictionary, x: float, z: float) -> Dictionary:
	var kind := GameData.monster_kind("duelist")
	var monster := World.make_monster("duel_foe", kind, x, z, 0.0, 0.0)
	var s := World.stats_of(
		str(copy.get("job", "fighter")), int(copy.get("level", 1)), copy.get("equipped", {}),
		copy.get("passives", {}), copy.get("fitness", {}), copy.get("codex", {}), copy.get("trainers", {})
	)
	var cooldown := Combat.effective_cooldown(float(s.attackCooldown), float(s.attackSpeed))
	var attack := float(s.attack)
	if cooldown < FOE_MIN_SWING_MS:
		attack *= float(FOE_MIN_SWING_MS) / float(cooldown)
		cooldown = FOE_MIN_SWING_MS
	monster.merge({
		"name": str(copy.get("name", "")),
		"foe_id": str(copy.get("id", "")),
		"duel": true,
		"level": int(copy.get("level", 1)),
		"max_hp": int(s.maxHp),
		"hp": int(s.maxHp),
		"attack": attack,
		"defense": float(s.defense),
		"crit": float(s.crit),
		"crit_damage": float(s.critDamage),
		"penetration": float(s.get("penetration", 0.0)),
		"attack_range": float(s.attackRange),
		"attack_cooldown": float(cooldown),
		# 화면이 앞차기를 트는 배속 — 기본 간격 / 지금 간격. 내 평타의 `swing.speed` 와 같은 값이다
		"swing_speed": float(s.attackCooldown) / maxf(1.0, float(cooldown)),
	}, true)
	return monster


## 결투장 전투력 — 자동 장착이 견주는 값(`Ledger.gear_power` = 한 대 기대 피해 × 버틸 체력)에 **공속 배수**를 곱한다
## (2026-10-12 요청 "공속도 넣어서 바꿔"). 배수 = 기본 간격 ÷ 지금 간격 (`Combat.effective_cooldown`) — 내 평타 배속
## (`swing.speed`)과 같은 값이라 공속 패시브가 없으면 1 이고, 질풍각 끝(초당 10타)이면 9배쯤이다.
## 자동 장착 값에는 안 넣었다 — 장비에 공속 옵션이 없어 어느 장비를 껴도 같은 배수라 고르는 데 쓸모가 없다
static func power(p: Dictionary) -> int:
	var equipped: Dictionary = p.get("equipped", {})
	var s := World.stats_of(
		str(p.get("job", "fighter")), int(p.get("level", 1)), equipped, p.get("passives", {}), p.get("fitness", {}),
		p.get("codex", {}), p.get("trainers", {})
	)
	var cooldown := Combat.effective_cooldown(float(s.attackCooldown), float(s.attackSpeed))
	return roundi(Ledger.gear_power(p, equipped) * float(s.attackCooldown) / maxf(1.0, float(cooldown)))


## i 번째 더미 이름. 앞말은 i % 10, 뒷말은 (⌊i / 10⌋ × 3 + i % 10) % 10 — i < 50 이면 짝이 겹치지 않는다
static func dummy_name(i: int) -> String:
	return NAME_HEADS[i % 10] + NAME_TAILS[(floori(i / 10.0) * 3 + i % 10) % 10]


## 더미 상대 50명 — 점수 높은 순. 한 줄은 상대의 **복사본** `{id, name, job, level, score, power}`
## (`power` 는 결투장 전투력 `power` — 더미는 맨몸이다)
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
		copy["power"] = power(copy)
		out.append(copy)
	return out


## 결투장 표 — 창이 받는 답 하나. `me` 는 장부(`job` · `level` · `equipped` · `arena` …)에 `name` 을 얹은 것.
## `{t, ranking: [줄 + rank (내 줄은 me: true)], challengers: [더미 줄 + rank], me: {rank, score, power, level, name}, total, dummy}`
static func board(me: Dictionary) -> Dictionary:
	var challengers := dummies(int(me.get("level", 1)))
	var mine := {
		"id": "me", "name": str(me.get("name", "")), "job": str(me.get("job", "fighter")),
		"level": int(me.get("level", 1)), "score": score_of(me),
		"power": power(me), "me": true,
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
