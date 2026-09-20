extends SceneTree

## `world/stats.gd` 가 설계 문서와 같은 답을 내는지 본다.
##
## 기준값은 [stat-balance.md](../../docs/features/stat-balance.md) 의 표를 손으로
## 박아 둔 것이고, `packages/shared/src/balance.test.ts` · `tools/balance_sim.py` 와
## **같은 숫자**다. 세 구현이 한 줄에 서 있어야 "수치를 두 곳에 두지 않는다" 가 지켜진다.
##
##   godot --headless --path godot --script tests/stats_test.gd

var _failed := 0


func _init() -> void:
	_base()
	_reduce()
	_monster_table()
	_ttk()
	_group_loss()
	_skill_stages()
	_gear()
	_enhance()
	_start_gear()
	_debug_gear()
	_new_axes()

	if _failed == 0:
		print("스탯: 전부 통과")
		quit(0)
	else:
		print("스탯: %d개 실패" % _failed)
		quit(1)


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


func _near(label: String, got: float, want: float, tol: float = 1e-9) -> void:
	if absf(got - want) > tol:
		_fail("%s: %s 이어야 하는데 %s" % [label, want, got])


func _eq(label: String, got: int, want: int) -> void:
	if got != want:
		_fail("%s: %d 이어야 하는데 %d" % [label, want, got])


## 문서 2장 — 레벨당 복리 ×1.02
func _base() -> void:
	var one := Stats.base(1)
	_near("Lv1 HP", one["hp"], 100.0)
	_near("Lv1 공격", one["atk"], 10.0)
	_near("Lv1 방어", one["df"], 10.0)

	var top := Stats.base(Stats.max_level())
	_eq("Lv200 맨몸 HP", roundi(top["hp"]), 5146)
	_eq("Lv200 맨몸 공격", roundi(top["atk"]), 515)
	_eq("Lv200 맨몸 방어", roundi(top["df"]), 515)

	# 레벨 1개는 언제나 +2% — 구간마다 다르면 "장비 비중" 의 기준이 사라진다
	for level in [2, 50, 120, 199]:
		_near("Lv%d 성장률" % level, Stats.base(level + 1)["atk"] / Stats.base(level)["atk"], 1.02, 1e-12)


## 문서 1장 — 감소율이 전 구간 30% 로 고정된다
func _reduce() -> void:
	for level in [1, 10, 50, 100, 150, 200]:
		var ref := Stats.ref_player(level)
		var reduce: float = ref["df"] / (Stats.k_of(level) + ref["df"])
		_near("Lv%d 감소율" % level, reduce, 0.3, 1e-12)


## 문서 6장 표 — 사냥터 끝 레벨에서 잰 값
func _monster_table() -> void:
	var rows := [
		{"level": 10, "grade": 1.0, "hp": 71, "atk": 2},
		{"level": 50, "grade": 1.63, "hp": 214, "atk": 4},
		{"level": 100, "grade": 3.3, "hp": 1043, "atk": 14},
		{"level": 150, "grade": 4.97, "hp": 7044, "atk": 64},
		{"level": 200, "grade": 6.63, "hp": 60224, "atk": 394},
	]
	for row in rows:
		var level := int(row["level"])
		_near("Lv%d 기준 등급" % level, snappedf(Stats.ref_grade(level), 0.01), float(row["grade"]), 1e-9)
		var m := Stats.monster(level)
		_eq("Lv%d 몬스터 HP" % level, roundi(m["hp"]), int(row["hp"]))
		_eq("Lv%d 몬스터 공격력" % level, roundi(m["atk"]), int(row["atk"]))


## 기준 장비로는 동레벨 몬스터를 정확히 6타에 잡는다.
## 여유(ttkMargin)가 없으면 경계에 얹혀 조금만 모자라도 7타가 된다
func _ttk() -> void:
	var level := 1
	while level <= Stats.max_level():
		var ref := Stats.ref_player(level)
		var m := Stats.monster(level)
		var per := Stats.damage(ref["atk"], level, m["df"]) * float(ref["crit"])
		_eq("Lv%d 타수" % level, int(ceil(float(m["hp"]) / per)), 6)
		level += 7


## 한 그룹을 정리하는 동안 HP 를 절반 잃는다 (몬스터 공격력이 이 목표의 역산이다)
func _group_loss() -> void:
	for level in [15, 100, 195]:
		var ref := Stats.ref_player(level)
		var m := Stats.monster(level)
		var per := Stats.damage(m["atk"], level, ref["df"])
		var taken: float = per * float(Stats.melee_attackers(level)) * 15.0 / float(m["interval"])
		_near("Lv%d 그룹 HP 손실" % level, taken / float(ref["hp"]), 0.5, 1e-9)


## 문서 5장 — 스킬 해금에 그룹 크기가 묶인다
func _skill_stages() -> void:
	var want := [
		{"level": 1, "spawn": 15, "aoe": 8, "melee": 3},
		{"level": 9, "spawn": 15, "aoe": 8, "melee": 3},
		{"level": 10, "spawn": 30, "aoe": 14, "melee": 4},
		{"level": 29, "spawn": 30, "aoe": 14, "melee": 4},
		{"level": 30, "spawn": 50, "aoe": 20, "melee": 6},
		{"level": 200, "spawn": 50, "aoe": 20, "melee": 6},
	]
	for row in want:
		var level := int(row["level"])
		_eq("Lv%d 스폰" % level, Stats.spawn_count(level), int(row["spawn"]))
		_eq("Lv%d 범위" % level, Stats.aoe_targets(level), int(row["aoe"]))
		_eq("Lv%d 동시 피격" % level, Stats.melee_attackers(level), int(row["melee"]))


## 문서 3장 — 등급 표와 등급7 슬롯 수치
func _gear() -> void:
	var table := [
		{"grade": 1, "level": 1, "sum": 35},
		{"grade": 2, "level": 31, "sum": 60},
		{"grade": 3, "level": 61, "sum": 102},
		{"grade": 4, "level": 91, "sum": 173},
		{"grade": 5, "level": 121, "sum": 295},
		{"grade": 6, "level": 151, "sum": 502},
		{"grade": 7, "level": 181, "sum": 856},
	]
	for row in table:
		var g := int(row["grade"])
		_eq("등급 %d 착용 레벨" % g, Stats.equip_level(g), int(row["level"]))
		_eq("등급 %d 풀셋 합" % g, roundi(Stats.grade_sum(float(g))), int(row["sum"]))
	_near("등급 간격", snappedf(Stats.grade_ratio(), 0.0001), 1.7037, 1e-9)

	# 등급7 실제 수치 (무강 → 강화 4단)
	_eq("등급7 무기 무강", roundi(Stats.slot_stats("weapon", 7.0, 1)["atk"]), 514)
	_eq("등급7 무기 4단", roundi(Stats.slot_stats("weapon", 7.0, 4)["atk"]), 670)
	_eq("등급7 갑옷 방어", roundi(Stats.slot_stats("armor", 7.0, 1)["df"]), 205)
	_eq("등급7 갑옷 HP", roundi(Stats.slot_stats("armor", 7.0, 1)["hp"]), 120)
	_eq("등급7 목걸이 치확", roundi(Stats.slot_stats("necklace", 7.0, 1)["crit"] * 100.0), 50)
	_eq("등급7 반지 공속", roundi(Stats.slot_stats("ring", 7.0, 1)["aspd"] * 100.0), 20)
	_eq("등급7 신발 이동", roundi(Stats.slot_stats("boots", 7.0, 1)["move"] * 100.0), 25)


## 문서 4장 — 강화 배수·도달률
func _enhance() -> void:
	var mult := [1.0, 1.07, 1.17, 1.3, 1.5, 1.78, 2.2, 2.88, 4.0, 6.0]
	for step in range(1, 11):
		_near("%d단 배수" % step, snappedf(Stats.enhance_multiplier(step), 0.01), mult[step - 1], 1e-9)
	_near("4단 도달률", Stats.enhance_reach(4), 0.504, 1e-9)
	_near("10단 도달률", Stats.enhance_reach(10), 0.00036288, 1e-12)

	# 강화는 %스탯에만 곱한다 — 치명타·공속이 같이 커지면 상한을 관리할 수 없다
	var bare := Stats.slot_stats("necklace", 7.0, 1)
	var maxed := Stats.slot_stats("necklace", 7.0, 10)
	_near("치확은 강화를 안 먹는다", maxed["crit"], bare["crit"])
	_near("공속은 강화를 안 먹는다", Stats.slot_stats("ring", 7.0, 10)["aspd"], Stats.slot_stats("ring", 7.0, 1)["aspd"])


## **디버그 수단이 시뮬레이터와 같은 조건을 세우는가** (설계 문서 9장 5번).
##
## 레벨·등급·강화를 강제로 맞췄을 때, 게임 안 플레이어가 설계의 기준 플레이어와
## 같은 세기가 되어야 "설계대로 도는가" 를 화면에서 확인할 수 있다
func _debug_gear() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	w.debug_gear("me", 100, 4, 3)

	var me: Dictionary = w.snapshot().players["me"]
	if int(me.level) != 100:
		_fail("레벨이 100 이 아니다 (%d)" % int(me.level))
	if me.equipped.size() != 6:
		_fail("여섯 칸이 안 찼다 (%d)" % me.equipped.size())
	if int(me.hp) != int(me.stats.maxHp):
		_fail("체력이 가득 안 찼다")

	# 설계의 기준 플레이어(Lv100, 등급 보간 3.30, 강화 5단)와 자릿수가 같아야 한다.
	# 등급을 4 로 강제했으니 기준보다 조금 세다 — 두 배를 넘지는 않는다
	var ref := Stats.ref_player(100)
	var ratio := float(me.stats.attack) / float(ref["atk"])
	if ratio < 0.5 or ratio > 2.5:
		_fail("공격력이 기준의 %.2f 배다 (%d vs %d)" % [ratio, int(me.stats.attack), roundi(ref["atk"])])
	else:
		print("  디버그 Lv100 등급4 +3: 공격 %d (기준 %d), HP %d" % [
			int(me.stats.attack), roundi(ref["atk"]), int(me.stats.maxHp)
		])


## **쿨감·관통이 판정에 실제로 닿는가** (2026-09-20 에 넣은 옵션 두 축).
## 스탯에만 있고 계산에 안 쓰이면 장식이다
func _new_axes() -> void:
	var w := World.new()
	w.open("meadow")
	w.join("me")
	var me: Dictionary = w.snapshot().players["me"]

	# 관통 — 상대 방어력을 그만큼 없는 셈 치고 때린다
	var mob := World.make_monster(
		"dummy", GameData.monster_kind("mob003"), 1.5, 0.0, 10000.0, 0.0
	)
	var plain := Stats.damage(float(me.stats.attack), int(me.level), float(mob.defense))
	var pierced := Stats.damage(
		float(me.stats.attack), int(me.level), float(mob.defense) * 0.5
	)
	if pierced <= plain:
		_fail("관통이 피해를 못 올린다 (%.1f -> %.1f)" % [plain, pierced])
	else:
		print("  관통 50%%: 피해 %.1f -> %.1f" % [plain, pierced])

	# 쿨감 — 옵션이 붙으면 스탯에 실려야 한다
	me.equipped = {
		"ring": {
			"id": "r_00", "grade": 10, "enhance": 0,
			"options": [{"kind": "cooldown", "value": 1.0}, {"kind": "penetration", "value": 3.3}],
		}
	}
	w._refresh_stats(me)
	if float(me.stats.get("cooldown", 0.0)) <= 0.0:
		_fail("쿨감이 스탯에 안 실렸다")
	if float(me.stats.get("penetration", 0.0)) <= 0.0:
		_fail("관통이 스탯에 안 실렸다")


## 시작 장비는 무기 한 자루. 등급1 은 사냥터 2 에서야 나온다
func _start_gear() -> void:
	_eq("등급1 드랍 시작 레벨", Stats.drop_level(1), 11)
	for level in [1, 5, 10]:
		var worn := Stats.ref_worn(level)
		if worn.size() != 1 or str(worn[0][0]) != "weapon":
			_fail("Lv%d 시작 장비가 무기 한 자루가 아니다 (%s)" % [level, worn])
	_eq("Lv11 착용 칸", Stats.ref_worn(11).size(), 6)
