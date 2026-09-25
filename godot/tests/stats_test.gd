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
		# **2026-09-23 에 HP 를 되돌렸다** (지시: "몬스터 HP 30%를 다시 올려").
		# 2026-09-21 에 장신구 배분을 고치면서 소리 없이 따라 내려갔던 값을
		# 장신구 변경 직전 것으로 복원했다 — 공격력·방어력은 그때도 안 바뀌었다.
		# **2026-09-24 에 HP 를 공격력 축 배수만큼 올렸다** ("등급간 배수를 키워").
		# 같은 날 방어·HP 축도 같은 배수가 되어 공격력·방어력 열도 설계 비율만큼 올렸다
		# 2026-09-25 에 HP 를 초반부터 서서히 올려 Lv200 에서 3배 (`3^((L−1)/199)`)
		{"level": 10, "grade": 1.0, "hp": 75, "atk": 2},
		{"level": 50, "grade": 1.63, "hp": 308, "atk": 4},
		{"level": 100, "grade": 3.3, "hp": 3272, "atk": 20},
		{"level": 150, "grade": 4.97, "hp": 57924, "atk": 192},
		{"level": 200, "grade": 6.63, "hp": 1278546, "atk": 2547},
	]
	for row in rows:
		var level := int(row["level"])
		_near("Lv%d 기준 등급" % level, snappedf(Stats.ref_grade(level), 0.01), float(row["grade"]), 1e-9)
		var m := Stats.monster(level)
		_eq("Lv%d 몬스터 HP" % level, roundi(m["hp"]), int(row["hp"]))
		_eq("Lv%d 몬스터 공격력" % level, roundi(m["atk"]), int(row["atk"]))


## 동레벨 타수 — **6타는 목표이지 불변식이 아니다.**
##
## 2026-09-23 지시: "동레벨 6타, 만렙 2880 시간을 무조건 적으로 지키려고 하지마.
## 후반부에 가면 동레벨 몬스터가 6타가 넘을 수 있어."
##
## 6타에 딱 맞추라고 걸어 두면 장비 배분이나 옵션을 고칠 때마다 몬스터 표를
## 되맞추게 되는데, 그게 바로 하지 말라고 한 일이다. 말이 되는 범위만 본다
func _ttk() -> void:
	var level := 1
	var first := 0
	var last := 0
	while level <= Stats.max_level():
		var ref := Stats.ref_player(level)
		var m := Stats.monster(level)
		var per := Stats.damage(ref["atk"], level, m["df"]) * float(ref["crit"])
		var hits := int(ceil(float(m["hp"]) / per))
		if first == 0:
			first = hits
		last = hits
		if hits < 6:
			_fail("Lv%d 타수 %d — 기준 장비로 설계보다 쉬우면 곡선이 무너진다" % [level, hits])
		# 한도 18 → 54 (2026-09-25): 몬스터 HP 를 서서히 3배로 올려 Lv197 평타가 50타다
		elif hits > 54:
			_fail("Lv%d 타수 %d — 기준 장비로도 너무 오래 걸린다" % [level, hits])
		level += 7
	if last < first:
		_fail("초반 %d타 -> 후반 %d타 로 되레 쉬워졌다" % [first, last])
	print("  동레벨 타수: 초반 %d타 -> 후반 %d타 (6타는 목표, 후반은 넘어도 된다)" % [first, last])


## 한 그룹을 정리하는 동안 HP 를 절반쯤 잃는다.
##
## **딱 맞지는 않는다** — 2026-09-21 에 몬스터를 고정 표로 바꾸면서 값이 소수
## 둘째 자리에서 끊겼다. 표를 손으로 고치면 더 벌어지는데 그건 의도된 일이라
## 폭을 5% 로 둔다 (`balance.test.ts` 의 DESIGN_DRIFT 와 같은 기준이다)
func _group_loss() -> void:
	for level in [15, 100, 195]:
		var ref := Stats.ref_player(level)
		var m := Stats.monster(level)
		var per := Stats.damage(m["atk"], level, ref["df"])
		var taken: float = per * float(Stats.melee_attackers(level)) * 15.0 / float(m["interval"])
		_near("Lv%d 그룹 HP 손실" % level, taken / float(ref["hp"]), 0.5, 0.025)


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
		# 2026-09-24 에 등급 배수 ×1.7037 → ×2.434 (영웅 무기 = 일반의 피해 3배, 전 축 공통)
		{"grade": 2, "level": 31, "sum": 85},
		{"grade": 3, "level": 61, "sum": 207},
		{"grade": 4, "level": 91, "sum": 505},
		{"grade": 5, "level": 121, "sum": 1229},
		{"grade": 6, "level": 151, "sum": 2993},
		{"grade": 7, "level": 181, "sum": 7286},
	]
	for row in table:
		var g := int(row["grade"])
		_eq("등급 %d 착용 레벨" % g, Stats.equip_level(g), int(row["level"]))
		_eq("등급 %d 풀셋 합" % g, roundi(Stats.grade_sum(float(g))), int(row["sum"]))
	# 영웅 무기 = 일반 무기의 피해 3배에서 역산한 배수다 (2026-09-24)
	_near("등급 간격", snappedf(Stats.grade_ratio(), 0.001), 2.434, 1e-9)
	var common := 1.0 + float(Stats.slot_stats("weapon", 1.0, 1)["atk"]) / 100.0
	var hero := 1.0 + float(Stats.slot_stats("weapon", 4.0, 1)["atk"]) / 100.0
	# 3배로 역산했지만 2026-09-25 에 장비 공격력 % 를 반으로 내려("반으로 줄여") 약 2.1배다
	_near("영웅/일반 무기 피해", snappedf(hero / common, 0.01), 2.08, 1e-6)

	# 등급7 실제 수치 (무강 → 강화 4단).
	# **2026-09-21 에 배분을 바꿨다** — 무기 0.6→0.5, 갑옷 0.4→1/3, 장신구가 그 절반.
	# 치확·공속은 장비 기본에서 걷었고(랜덤 옵션 전담) 풀세트 합은 그대로다
	_eq("등급7 무기 무강", roundi(Stats.slot_stats("weapon", 7.0, 1)["atk"]), 1822)
	_eq("등급7 무기 4단", roundi(Stats.slot_stats("weapon", 7.0, 4)["atk"]), 2375)
	_eq("등급7 갑옷 방어", roundi(Stats.slot_stats("armor", 7.0, 1)["df"]), 1457)
	_eq("등급7 갑옷 HP", roundi(Stats.slot_stats("armor", 7.0, 1)["hp"]), 850)
	_eq("등급7 목걸이 공격", roundi(Stats.slot_stats("necklace", 7.0, 1)["atk"]), 911)
	_eq("등급7 목걸이 방어", roundi(Stats.slot_stats("necklace", 7.0, 1)["df"]), 729)
	_eq("등급7 목걸이 치확", roundi(Stats.slot_stats("necklace", 7.0, 1)["crit"] * 100.0), 0)
	_eq("등급7 반지 공속", roundi(Stats.slot_stats("ring", 7.0, 1)["aspd"] * 100.0), 0)
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
			"id": "g1_r", "grade": 1, "enhance": 0,
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
