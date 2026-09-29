class_name KillCheck
extends RefCounted

## 최소 처치 시간 — "이 캐릭터가 이 몬스터를 이보다 빨리 잡을 수는 없다" (docs/features/server.md
## "처치 보고를 어떻게 믿나" 2). **넉넉하게 잡는다** — 정상 플레이를 거절하는 쪽이 훨씬 나쁘다.
##
## 피해는 공격력에 비례한다(`Stats.damage` = 공격력 × K/(K+방어), 한 방 최소 1). 그래서 "스킬 배율의
## 합" 으로 셈한다. 시간 W 동안 넣을 수 있는 배율은 많아야
##
##     Σ(스킬) 한 번에 넣는 배율 × (1 + W / 재사용 간격)  +  평타도 같은 꼴
##
## — **시전 잠금(`castMs`)을 무시하고 모든 스킬을 동시에 쏜다고 친다.** 치명타는 늘 터진다고 친다.
## 그래서 실제보다 늘 크다. 이것으로 몬스터 체력에 닿는 W 를 구하고, 그 절반(`HEADROOM`)에서
## 네트워크 흔들림(`SLACK_MS`)을 더 뺀 것을 기준으로 쓴다.
##
## **스킬이나 강화에 피해 효과를 더하면 여기를 같이 고친다** — `KNOWN_SKILL_KEYS` ·
## `KNOWN_UPGRADE_KEYS` 에 없는 칸이 표에 생기면 `server_test` 가 실패해서 알려 준다.

const HEADROOM := 0.5
const SLACK_MS := 1500.0

## 여기서 셈하는 칸 · 피해와 무관한 칸. 표에 새 칸이 생기면 어느 쪽인지 정해 여기에 넣는다
const KNOWN_SKILL_KEYS := [
	"power", "hits", "cooldown", "castMs",  # 셈한다
	"arc", "delayMs", "description", "hitGap", "id", "job", "maxTargets", "name",
	"projectile", "range", "reqLevel", "tier", "atTarget",
]
const KNOWN_UPGRADE_KEYS := [
	"extraHits", "zoneMs", "zoneTickMs", "zonePower", "followPower", "powerMul",  # 셈한다
	"id", "skill", "name", "desc", "exp", "stunMs", "stunLook", "rangeMul", "followMs",
]


## 그 몬스터를 잡는 데 걸리는 최소 시간(ms) — 이보다 빨리 잡았다는 보고는 거절한다. 0 이면 한 방도 된다
static func min_ms(ledger: Dictionary, kind: Dictionary) -> float:
	var stats := World.stats_of(str(ledger.job), int(ledger.level), ledger.get("equipped", {}))
	var k := Stats.k_of(int(ledger.level))
	var defense := float(kind.get("defense", 0)) * (1.0 - float(stats.get("penetration", 0.0)))
	# 배율 1 당 피해 — 치명타는 늘 터진다고 친다
	var per_power := float(stats.attack) * k / (k + defense) * (1.0 + maxf(float(stats.critDamage), 0.0))

	# 한꺼번에 넣는 것(burst)과 1ms 당 넣는 것(rate). 한 방 최소 1 이라 타수도 더한다
	var burst := 0.0
	var rate := 0.0
	var basic_ms := maxf(1.0, float(Combat.effective_cooldown(stats.attackCooldown, stats.attackSpeed)))
	burst += per_power + 1.0
	rate += (per_power + 1.0) / basic_ms
	var cut := clampf(float(stats.get("cooldown", 0.0)), 0.0, 0.9)
	for skill_id in ledger.get("skills", []):
		var skill: Dictionary = Skills.all().get(str(skill_id), {})
		if skill.is_empty():
			continue
		var hits := float(skill.get("hits", 1))
		var power := float(skill.get("power", 1)) * hits
		var owned: Array = ledger.get("skill_upgrades", {}).get(str(skill_id), [])
		for upgrade in Skills.upgrades_of(str(skill_id)):
			if not (str(upgrade.id) in owned):
				continue
			var extra := float(upgrade.get("extraHits", 0))
			hits += extra
			power += float(skill.get("power", 1)) * extra
			power += float(upgrade.get("followPower", 0))
			if upgrade.has("zoneMs"):
				var ticks := float(upgrade.zoneMs) / maxf(1.0, float(upgrade.get("zoneTickMs", 500)))
				power += float(upgrade.get("zonePower", 1)) * ticks
				hits += ticks
		# 위력 강화는 전부에 곱한다 — 지대까지 곱하면 실제보다 크다(넉넉한 쪽이다)
		power *= Skills.power_mul(str(skill_id), owned)
		var every := maxf(1.0, float(skill.get("cooldown", 0)) * (1.0 - cut))
		var cast := power * per_power + hits
		burst += cast
		rate += cast / every

	var hp := float(kind.get("maxHp", 1))
	if hp <= burst or rate <= 0.0:
		return 0.0
	return (hp - burst) / rate


## 보고를 받아도 되나 — 몬스터가 나올 수 있게 된 뒤로 `elapsed_ms` 가 지났다
static func allows(elapsed_ms: float, need_ms: float) -> bool:
	return elapsed_ms + SLACK_MS >= need_ms * HEADROOM
