class_name Stats
extends RefCounted

## packages/shared/src/balance.ts + gear.ts 이식본.
##
## 수치는 여기 적지 않는다 — `data/balance.json`(shared 에서 내보낸 것)에서 읽는다.
## 공식만 옮긴다. 이유와 배경은 [stat-balance.md](../../docs/features/stat-balance.md) 에 있다.
##
## **2026-09-20 에 판정에 붙였다.** `World` 의 피해 계산과 `Items` 의 강화가 여기를
## 부르고, `Combat` 은 경험치 표를 `data/balance.json` 에서 읽는다.
##
## 검증: `godot/tests/stats_test.gd` 가 TS·파이썬으로 낸 값과 대조한다.

static func _b() -> Dictionary:
	return GameData.balance()


static func _g() -> Dictionary:
	return GameData.balance().get("gear", {})


# ---------------------------------------------------------------- 기본 스탯

## 레벨 L 의 성장 배수 (Lv1 = 1.0). **복리다** — 레벨 1개가 언제나 총 피해 +2%
static func growth(level: int) -> float:
	return pow(1.0 + float(_b().get("growth", 0.02)), float(level - 1))


## 맨몸 기본 스탯 {hp, atk, df}
static func base(level: int) -> Dictionary:
	var b := _b()
	var g := growth(level)
	return {
		"hp": float(b.get("hpBase", 100)) * g,
		"atk": float(b.get("atkBase", 10)) * g,
		"df": float(b.get("defBase", 10)) * g,
	}


static func max_level() -> int:
	return int(_b().get("maxLevel", 200))


static func field_count() -> int:
	return int(ceil(float(max_level()) / float(_b().get("fieldSpan", 10))))


## 레벨 L 이 속한 사냥터 번호 (1~20)
static func field_of(level: int) -> int:
	var span := float(_b().get("fieldSpan", 10))
	return clampi(int(ceil(float(level) / span)), 1, field_count())


# ---------------------------------------------------------------- 스킬 단계

## 그 레벨의 스킬 해금 단계. **그룹 크기가 여기 묶인다** — 초반에는 스킬이 없어서
## 50마리를 15초에 정리할 수 없으므로 스폰 수도 같이 작다
static func skill_stage(level: int) -> Dictionary:
	var stages: Array = _b().get("skillStages", [])
	if stages.is_empty():
		return {"spawn": 50, "aoe": 20, "melee": 6}
	var cur: Dictionary = stages[0]
	for stage in stages:
		if level >= int(stage.get("level", 1)):
			cur = stage
	return cur


static func spawn_count(level: int) -> int:
	return int(skill_stage(level).get("spawn", 50))


static func aoe_targets(level: int) -> int:
	return int(skill_stage(level).get("aoe", 20))


## 동시에 나를 때리는 마릿수. 몬스터 1마리 공격력을 이것으로 나눠 역산하므로,
## 스킬이 열려 이 값이 커지면 **한 마리 몫은 오히려 줄어든다** (총량은 그대로)
static func melee_attackers(level: int) -> int:
	return int(skill_stage(level).get("melee", 6))


# ---------------------------------------------------------------- 장비 등급

static func grade_count() -> int:
	return int(_g().get("gradeCount", 7))


## 등급 간 배수 — 전 축 공통 ×2.434. 역산은 `gear.ts` `gradeRatio` 한 곳에서 하고,
## 여기는 내보낸 등급1·등급7 합계로 되푼다 (영웅 무기 = 일반 무기의 피해 3배)
static func grade_ratio() -> float:
	var g := _g()
	var lo := float(g.get("sumStart", 35.0))
	var hi := float(g.get("sumEnd", 856.0))
	return pow(hi / lo, 1.0 / float(grade_count() - 1))


## 등급 g 풀세트의 공격력 % 합계. 소수 등급이면 등비 보간된다
static func grade_sum(grade: float) -> float:
	if grade <= 0.0:
		return 0.0
	var g := minf(grade, float(grade_count()))
	return float(_g().get("sumStart", 35.0)) * pow(grade_ratio(), g - 1.0)


## 등급 g 착용 레벨 — 1 / 31 / 61 / 91 / 121 / 151 / 181
static func equip_level(grade: int) -> int:
	return 1 + int(_g().get("gradeLvSpan", 30)) * (grade - 1)


## 레벨 L 에서 낄 수 있는 최고 등급
static func grade_of(level: int) -> int:
	var span := int(_g().get("gradeLvSpan", 30))
	return clampi(1 + int((level - 1) / span), 1, grade_count())


## 보조 스탯용 등급 진행도. 등급 1 = 0, 최고 등급 = 1 (선형)
static func grade_progress(grade: float) -> float:
	return maxf(0.0, (minf(grade, float(grade_count())) - 1.0) / float(grade_count() - 1))


## 등급 g 풀세트가 주는 스탯 총량. atk/df/hp 는 %, 나머지는 비율
static func stat_budget(grade: float) -> Dictionary:
	var g := _g()
	var s := grade_sum(grade)
	var r := grade_progress(grade)
	return {
		"atk": s * float(g.get("atkFactor", 1.0)),
		"df": s * float(g.get("defFactor", 0.6)),
		"hp": s * float(g.get("hpFactor", 0.35)),
		"crit": float(g.get("critRateMax", 0.5)) * r,
		"critDamage": float(g.get("critDmgMax", 1.0)) * r,
		"aspd": float(g.get("aspdMax", 0.2)) * r,
		"move": float(g.get("moveSpdMax", 0.25)) * r,
	}


## 강화 단계별 증가율. 닫힌 식이 없어 이분법으로 첫 구간을 찾는다
## (첫 구간 : 마지막 = 1 : enhAccel, 전체 곱 = enhTotal)
static func enhance_gains() -> Array[float]:
	var g := _g()
	var steps := int(g.get("enhMax", 10))
	var total := float(g.get("enhTotal", 6.0))
	var accel := float(g.get("enhAccel", 7.0))
	var n := steps - 1
	var k := pow(accel, 1.0 / float(n - 1))
	var lo := 1e-5
	var hi := 1.0
	for _i in 200:
		var mid := (lo + hi) / 2.0
		var t := 1.0
		for j in n:
			t *= 1.0 + mid * pow(k, float(j))
		if t < total:
			lo = mid
		else:
			hi = mid
	var out: Array[float] = []
	for j in n:
		out.append(lo * pow(k, float(j)))
	return out


## 강화 단계(1~10)의 배수. 1단 = ×1.0, 10단 = ×6.0
static func enhance_multiplier(step: int) -> float:
	var steps := int(_g().get("enhMax", 10))
	var s := clampi(step, 1, steps)
	var m := 1.0
	var gains := enhance_gains()
	for i in s - 1:
		m *= 1.0 + gains[i]
	return m


## 아이템 하나를 굴려 그 단계에 **도달할** 확률. 실패하면 파괴되므로 성공률의 곱이다
static func enhance_reach(step: int) -> float:
	var odds: Array = _g().get("enhOdds", [])
	var s := clampi(step, 1, int(_g().get("enhMax", 10)))
	var p := 1.0
	for i in mini(s - 1, odds.size()):
		p *= float(odds[i])
	return p


## 슬롯 하나가 주는 수치. 강화는 %스탯(atk/df/hp)에만 곱한다 —
## 두 곱산 버킷이 동시에 커지면 총 배수 상한을 관리할 수 없다
static func slot_stats(slot: String, grade: float, enhance: int = 1) -> Dictionary:
	var share: Dictionary = _g().get("slotShare", {}).get(slot, {})
	var budget := stat_budget(grade)
	var mult := enhance_multiplier(enhance)
	var out := {}
	for stat in budget:
		var v: float = budget[stat] * float(share.get(stat, 0.0))
		if stat == "atk" or stat == "df" or stat == "hp":
			v *= mult
		out[stat] = v
	return out


# ---------------------------------------------------------------- 기준 플레이어

## 그 레벨에서 몬스터 역산에 쓰는 기준 강화 단계 (사냥터 구간별로 4 → 7단)
static func enh_ref_step(level: int) -> int:
	var rows: Array = _b().get("enhRefByField", [])
	var f := field_of(level)
	var cur := 4
	for row in rows:
		if f >= int(row.get("field", 1)):
			cur = int(row.get("step", 4))
	return cur


## 몬스터 역산에 쓰는 **기준 장비 등급 — 30레벨에 걸쳐 보간한다.**
## 계단식으로 올리면 해금 레벨에서 몬스터가 한 번에 1.7배 이상 세져,
## 장비를 아직 못 구한 플레이어는 레벨업이 벌이 된다
static func ref_grade(level: int) -> float:
	var g := grade_of(level)
	if g <= 1:
		return float(g)
	var span := float(_g().get("gradeLvSpan", 30))
	var t := minf(1.0, float(level - equip_level(g)) / span)
	return float(g - 1) + t


## 등급 g 아이템이 나오는 사냥터의 시작 레벨
static func drop_level(grade: int) -> int:
	var span := int(_b().get("fieldSpan", 10))
	var f := mini(field_count(), int(ceil(float(equip_level(grade)) / float(span))) + 1)
	return span * (f - 1) + 1


## 그 레벨에서 현실적으로 갖고 있는 착용 상태 — [[슬롯, 등급, 강화], ...].
## 등급1 드랍 사냥터(Lv11) 전에는 **시작 장비인 무기 한 자루뿐**이다
static func ref_worn(level: int) -> Array:
	if level < drop_level(1):
		return [["weapon", 1.0, 1]]
	var grade := ref_grade(level)
	var step := enh_ref_step(level)
	var out: Array = []
	for slot in _g().get("slots", []):
		out.append([slot, grade, step])
	return out


## 착용 상태의 스탯 합계
static func gear_totals(worn: Array) -> Dictionary:
	var total := {"atk": 0.0, "df": 0.0, "hp": 0.0, "crit": 0.0, "critDamage": 0.0, "aspd": 0.0, "move": 0.0}
	for entry in worn:
		var s := slot_stats(str(entry[0]), float(entry[1]), int(entry[2]))
		for stat in total:
			total[stat] = float(total[stat]) + float(s.get(stat, 0.0))
	return total


## 치명타까지 반영한 평균 피해 배수
static func crit_multiplier(totals: Dictionary) -> float:
	return 1.0 + float(totals.get("crit", 0.0)) * float(totals.get("critDamage", 0.0))


## 레벨·장비·직업으로 플레이어를 짓는다. job 이 빈 문자열이면 배수 1.0 인 기준 직업
static func build_player(level: int, worn: Array, job: String = "") -> Dictionary:
	var b := base(level)
	var t := gear_totals(worn)
	var mult: Dictionary = _b().get("jobMult", {}).get(job, {})
	var m_atk := float(mult.get("atk", 1.0))
	var m_hp := float(mult.get("hp", 1.0))
	var m_df := float(mult.get("df", 1.0))
	var m_int := float(mult.get("interval", _b().get("playerAttackInterval", 1.0)))
	return {
		"level": level,
		"hp": float(b["hp"]) * (1.0 + float(t["hp"]) / 100.0) * m_hp,
		"atk": float(b["atk"]) * (1.0 + float(t["atk"]) / 100.0) * m_atk,
		"df": float(b["df"]) * (1.0 + float(t["df"]) / 100.0) * m_df,
		"crit": crit_multiplier(t),
		"interval": m_int / (1.0 + float(t["aspd"])),
	}


## 몬스터 역산의 기준이 되는 플레이어
static func ref_player(level: int) -> Dictionary:
	return build_player(level, ref_worn(level))


# ---------------------------------------------------------------- 피해·몬스터

## 피해 공식의 K. **상수로 두면 안 된다** — 기준 플레이어의 감소율이 정확히 30% 가
## 되도록 역산한다. 공격자 레벨에 의존하므로 레벨 차이 페널티가 공식에 내장된다.
##
## **레벨마다 한 번만 구한다** ★ — `ref_player` 는 기준 장비 여섯 벌을 강화까지
## 다시 합산해서 한 번에 0.8ms 다. 한 대 칠 때마다 불렀더니 할퀴기(다섯 대 × 무리)가
## 시전 한 번에 수십 ms 를 썼고, 무리에 둘러싸이면 몬스터가 때릴 때마다 또 불렀다
## (2026-09-23 "스킬 사용할 때 자꾸 히치가 걸려"). 표(`balance`)가 바뀌면 다시 구한다
static func k_of(attacker_level: int) -> float:
	var b := _b()
	if not is_same(b, _k_table):
		_k_table = b
		_k_memo.clear()
	if _k_memo.has(attacker_level):
		return _k_memo[attacker_level]
	var t := float(b.get("targetReduce", 0.3))
	var k: float = ref_player(attacker_level)["df"] * (1.0 - t) / t
	_k_memo[attacker_level] = k
	return k


## `k_of` 의 레벨별 값과, 그 값을 구한 표
static var _k_memo: Dictionary = {}
static var _k_table: Dictionary = {}


## 피해 = 공격력 × K / (K + 방어력). **뺄셈이 아니라 나눗셈이다** —
## 방어력이 아무리 커도 감소율이 100% 에 도달하지 않는다
static func damage(atk: float, attacker_level: int, df: float) -> float:
	var k := k_of(attacker_level)
	return maxf(1.0, atk * k / (k + df))


## 몬스터 능력치 — **고정 표(`monsterStats`)에서 읽는다.** ★★
##
## 2026-09-21 지시: "몬스터 능력치가 자동으로 역산 되면 안돼." 그 전에는 여기서
## (레벨, 그 레벨의 기준 장비) 로 역산했고, 장비를 손대면 몬스터가 소리 없이
## 따라 움직였다. 표는 `packages/shared/src/monsterTable.ts` 가 원본이고
## `balance.json` 으로 실려 온다 — 여기는 읽기만 한다.
##
## 몬스터에게 치명타는 주지 않는다 — 유일한 경고 신호가 "몇 대 맞았나" 인데
## 치명타는 예고 없는 죽음을 만든다
static func monster(level: int, role: String = "normal") -> Dictionary:
	var b := _b()
	var table: Array = b.get("monsterStats", [])
	if table.is_empty():
		return {"level": level, "role": role, "hp": 1.0, "atk": 1.0, "df": 0.0, "interval": 1.5, "exp": 0.0}
	var row: Array = table[clampi(level - 1, 0, table.size() - 1)]
	var r: Dictionary = b.get("roleMult", {}).get(role, {"hp": 1.0, "atk": 1.0})
	var mon_hp := float(row[0]) * float(r.get("hp", 1.0))
	return {
		"level": level,
		"role": role,
		"hp": mon_hp,
		"atk": float(row[1]) * float(r.get("atk", 1.0)),
		"df": float(row[2]),
		"interval": float(b.get("monAttackInterval", 1.5)),
		"exp": mon_hp * float(b.get("expCoef", 0.2)),
	}
