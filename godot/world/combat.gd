class_name Combat
extends RefCounted

## packages/shared/src/combat.ts 이식본.
##
## 수치는 여기 적지 않는다 — `data/combat.json`(shared 에서 내보낸 것)에서 읽는다.
## 공식만 옮긴다. 이유와 배경은 원본 주석과 docs/features/combat.md 에 있다.
##
## 반올림: JS 의 Math.round 와 고도의 roundi 는 **음수에서만** 다르다
## (-2.5 → JS 는 -2, 고도는 -3). 여기 값은 전부 양수라 같은 답이 나온다.
##
## 검증: godot/tests/combat_test.gd 가 TS 로 낸 값과 대조한다.

static func _c() -> Dictionary:
	return GameData.combat()


## 공격 속도를 반영한 실제 공격 간격 (ms)
## **상한이 없다** (2026-09-23 지시). `cooldown / (1 + 공속)` 이라 아무리 높아도
## 0 으로 나누지 않는다. 음수만 막는다 — 0 미만이면 값이 뒤집힌다
static func effective_cooldown(cooldown: float, attack_speed: float) -> int:
	return maxi(1, roundi(cooldown / (1.0 + maxf(attack_speed, 0.0))))


## 이번 공격이 몸을 묶는 시간. 다음 공격까지의 간격을 넘지 않는다.
## 안 묶으면 공격 모션을 튼 채로 달려서 발은 달리는데 팔만 휘두르는 그림이 된다
static func attack_root_ms(cooldown_ms: float) -> int:
	return maxi(0, mini(int(_c().get("attackRootMs", 400)), roundi(cooldown_ms)))


## 짐승이 한 번 휘두르는 동안 묶이는 시간. 공격 간격을 넘지 않는다.
##
## 사람과 달리 이 값이 곧 **공격 클립을 보여 주는 창의 길이**다. 판정과 화면이
## 같은 값을 봐야 동작이 끝나는 순간에 발이 떨어진다 — 어느 한쪽이 길면
## 휘두르며 달리거나 다 휘두르고도 멈춰 있는다
static func monster_root_ms(cooldown_ms: float) -> int:
	return maxi(0, mini(int(_c().get("monsterSwingMs", 650)), roundi(cooldown_ms)))


## 굴림값(0~1)이 치명타인지. **상한이 없다** — 100% 를 넘기면 늘 치명타다
static func roll_crit(chance: float, roll: float) -> bool:
	return roll < maxf(chance, 0.0)


## 직업·레벨로 스탯을 만든다. 바탕값 + 레벨당 x (레벨 - 1)
## 맨몸 능력치 — **밸런스 설계의 복리 곡선**이다 (`Stats.base(L)` × 직업 배수).
##
## 2026-09-20 에 갈아끼웠다. 그 전에는 `jobStats` 의 선형 증가(레벨당 +2.4 공격 같은
## 고정값)였는데, 레벨당 상대 성장이 초반 +18% / 후반 +0.5% 로 40배 차이가 나
## "장비 비중" 의 기준이 사라진다. `jobStats` 는 이제 **사거리**만 쓴다.
##
## **치명타는 기본이 0 이다** — 설계에서 치확·치피는 목걸이 전담이라 장비에서만 온다
static func stats_for(job: String, level: int) -> Dictionary:
	var table: Dictionary = _c().get("jobStats", {})
	if not table.has(job):
		push_error("없는 직업: %s" % job)
		return {}
	var row: Array = table[job]
	var b := Stats.base(level)
	var m: Dictionary = GameData.balance().get("jobMult", {}).get(job, {})
	return {
		"maxHp": roundi(b["hp"] * float(m.get("hp", 1.0))),
		"attack": roundi(b["atk"] * float(m.get("atk", 1.0))),
		"defense": roundi(b["df"] * float(m.get("df", 1.0))),
		"attackRange": float(row[3]),
		# 설계의 직업별 공격 간격(초) → ms
		"attackCooldown": roundi(float(m.get("interval", 1.0)) * 1000.0),
		"crit": 0.0,
		"critDamage": 1.0,
		"attackSpeed": 0.0,
	}


## 피해량. 방어력을 빼기만 하면 방어가 공격을 넘는 순간 0 이 되어 전투가 멈춘다.
## 비율로 감쇠시켜 항상 조금은 들어가게 한다
static func compute_damage(attack: float, defense: float) -> int:
	var reduction := defense / (defense + 45.0)
	return maxi(1, roundi(attack * (1.0 - reduction)))


## 다음 레벨까지 필요한 경험치
## 다음 레벨까지 필요한 경험치 — **만렙까지 걸리는 시간에서 역산한 표**를 읽는다
## (`data/balance.json` 의 expTable, 2,880시간 = 24시간 × 120일).
## 그 전에는 `55 × 레벨^1.2` 라 사냥 속도와 무관했다
static func exp_to_next(level: int) -> int:
	var table: Array = GameData.balance().get("expTable", [])
	if table.is_empty():
		return roundi(55.0 * pow(float(level), 1.2))
	return maxi(1, int(table[clampi(level - 1, 0, table.size() - 1)]))


## 레벨과 남은 경험치를 다시 계산한다 (한 번에 여러 레벨이 오를 수 있다)
static func apply_exp(level: int, exp_now: int, gained: int) -> Dictionary:
	var max_level := int(_c().get("maxLevel", 200))
	var next_level := level
	var pool := exp_now + maxi(0, gained)

	while next_level < max_level:
		var need := exp_to_next(next_level)
		if pool < need:
			break
		pool -= need
		next_level += 1

	if next_level >= max_level:
		pool = 0
	return {"level": next_level, "exp": pool}


## 몬스터가 주는 경험치. **레벨 차이 보정을 걷었다** (2026-09-20).
##
## 설계에서 경험치는 몬스터 HP 에 정비례하므로 약한 몬스터는 이미 보상이 작다 —
## 따로 깎을 이유가 없다. 위쪽 한계도 경험치가 아니라 **사망**이 정한다
static func exp_reward(_monster_level: int, _player_level: int, base: float) -> int:
	return maxi(1, roundi(base))
