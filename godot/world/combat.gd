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
static func effective_cooldown(cooldown: float, attack_speed: float) -> int:
	var cap := float(_c().get("attackSpeedCap", 1.0))
	var speed := clampf(attack_speed, 0.0, cap)
	return maxi(1, roundi(cooldown / (1.0 + speed)))


## 이번 공격이 몸을 묶는 시간. 다음 공격까지의 간격을 넘지 않는다.
## 안 묶으면 공격 모션을 튼 채로 달려서 발은 달리는데 팔만 휘두르는 그림이 된다
static func attack_root_ms(cooldown_ms: float) -> int:
	return maxi(0, mini(int(_c().get("attackRootMs", 400)), roundi(cooldown_ms)))


## 굴림값(0~1)이 치명타인지
static func roll_crit(chance: float, roll: float) -> bool:
	var cap := float(_c().get("critCap", 0.75))
	return roll < clampf(chance, 0.0, cap)


## 직업·레벨로 스탯을 만든다. 바탕값 + 레벨당 x (레벨 - 1)
static func stats_for(job: String, level: int) -> Dictionary:
	var table: Dictionary = _c().get("jobStats", {})
	if not table.has(job):
		push_error("없는 직업: %s" % job)
		return {}
	var row: Array = table[job]
	var steps := maxi(0, level - 1)
	return {
		"maxHp": roundi(float(row[0]) + float(row[5]) * steps),
		"attack": roundi(float(row[1]) + float(row[6]) * steps),
		"defense": roundi(float(row[2]) + float(row[7]) * steps),
		"attackRange": float(row[3]),
		"attackCooldown": float(row[4]),
		"crit": float(_c().get("baseCrit", 0.05)),
		"critDamage": float(_c().get("baseCritDamage", 1.5)),
		"attackSpeed": 0.0,
	}


## 피해량. 방어력을 빼기만 하면 방어가 공격을 넘는 순간 0 이 되어 전투가 멈춘다.
## 비율로 감쇠시켜 항상 조금은 들어가게 한다
static func compute_damage(attack: float, defense: float) -> int:
	var reduction := defense / (defense + 45.0)
	return maxi(1, roundi(attack * (1.0 - reduction)))


## 다음 레벨까지 필요한 경험치
static func exp_to_next(level: int) -> int:
	return roundi(55.0 * pow(float(level), 1.2))


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


## 레벨 차이에 따른 경험치 보정 — 약한 몬스터만 잡는 걸 막는다
static func exp_reward(monster_level: int, player_level: int, base: float) -> int:
	var gap := monster_level - player_level
	if gap <= -8:
		return 0
	var scale := (1.0 + gap * 0.12) if gap >= 0 else (1.0 + gap * 0.11)
	return maxi(1, roundi(base * maxf(0.1, scale)))
