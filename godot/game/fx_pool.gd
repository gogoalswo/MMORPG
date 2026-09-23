class_name FxPool
extends Node3D

## **이펙트 풀** — 다 쓴 이펙트를 지우지 않고 숨겨 두었다가 다음 시전에 되감아 쓴다.
##
## 스킬을 쓸 때마다 히치가 걸렸다 (2026-09-23 "스킬 사용할 때 자꾸 히치가 걸려").
## `tools/hitch.gd` 로 재 보니 원인이 둘이었다.
##
## 1. **만드는 값** — 이펙트 하나가 노드 수십 개·재질·`CPUParticles3D`·빛을 새로
##    만든다. 할퀴기 5ms · 낙뢰 7ms · 천붕각 5ms (헤드리스, 클라우드 PC).
## 2. **셰이더를 버렸다 다시 짓는다** ★ — `StandardMaterial3D` 는 같은 설정의 재질이
##    **하나도 안 남으면 셰이더를 버린다.** 앞 이펙트가 다 꺼진 뒤 다시 쓰면 셰이더를
##    처음부터 다시 짓고, 화면에서는 **다시 컴파일한다** — `FxWarm` 이 미리 구운
##    것도 굽던 이펙트가 사라지는 순간 같이 버려졌다. 하나라도 살려 두면 생성이
##    1.1~1.6ms → 0.15~0.5ms 로 준다 (헤드리스라 컴파일은 빠진 값이다).
##
## 풀은 **게임에 하나**, 존 밖에 붙는다 — 존은 차원문을 지날 때 통째로 버려지므로
## 거기 두면 풀도 같이 사라진다. 이펙트는 월드 좌표로 서므로 원점에 있는 이
## 노드 아래에 둬도 자리가 같다.
##
## 이펙트 쪽 규격 (`SkillFx` · `LightningFx` · `QuakeFx` · `IceFx` · `HitFx`):
## - 띄우는 `static func` 가 `FxPool.take(parent, 키)` 로 쉬는 것을 먼저 꺼낸다.
##   없으면 새로 만든다. **부모가 풀이 아니면 늘 새로 만든다** (테스트 무대·`FxWarm`).
## - 노드를 만드는 일(`_build`)과 되감는 일(`_start`)을 나눈다. 되감기에서는
##   **아무것도 새로 만들지 않는다** — 위치·시각·보는 쪽·색만 넣는다.
## - 끝나면 `FxPool.give(self, 키)` — 풀 아래면 숨겨서 돌려놓고, 아니면 지운다.
## - `finish()` — 도중에 멈춘다 (존을 옮길 때 `recall`).

## 게임을 열 때 미리 만들어 두는 수. **하나는 꼭 있어야 한다** — 재질을 붙들고
## 있어야 셰이더가 안 버려진다. 타격은 할퀴기 다섯 대 × 무리 여럿이라 여럿 둔다
const PREFILL := {&"claw": 2, &"bolt": 1, &"slam": 1, &"ice": 1, &"hit": 12}

## 키 → 쉬고 있는 이펙트
var _idle: Dictionary = {}


## 쉬고 있는 것 하나를 꺼낸다. 없거나 `parent` 가 풀이 아니면 null — 부르는 쪽이 만든다
static func take(parent: Node3D, key: StringName) -> Node3D:
	var pool := parent as FxPool
	if pool == null:
		return null
	var list: Array = pool._idle.get(key, [])
	while not list.is_empty():
		var fx: Node3D = list.pop_back()
		if not is_instance_valid(fx):
			continue
		fx.visible = true
		fx.process_mode = Node.PROCESS_MODE_INHERIT
		# 마지막 자식으로 — "가장 최근 것 = 끝" 을 지킨다 (테스트가 그렇게 찾는다)
		pool.move_child(fx, -1)
		return fx
	return null


## 다 쓴 이펙트를 돌려놓는다. 풀 아래가 아니면 예전처럼 지운다
static func give(fx: Node3D, key: StringName) -> void:
	var pool := fx.get_parent() as FxPool
	if pool == null:
		fx.queue_free()
		return
	fx.visible = false
	fx.process_mode = Node.PROCESS_MODE_DISABLED
	var list: Array = pool._idle.get_or_add(key, [])
	if not list.has(fx):
		list.append(fx)


## 지금 떠 있나 (쉬는 중이 아닌가). 테스트가 "치웠나" 를 이것으로 본다
static func busy(fx: Node) -> bool:
	return is_instance_valid(fx) and not fx.is_queued_for_deletion() \
		and fx.process_mode != Node.PROCESS_MODE_DISABLED


## 미리 만들어 쉬게 둔다 — 첫 시전에 만드는 값을 치르지 않고, 재질(= 셰이더)을 붙든다
## **전부 띄운 뒤에 한꺼번에 돌려놓는다** — 하나씩 띄우고 돌려놓으면 다음 것이
## 방금 돌려놓은 것을 꺼내 써서 하나만 찬다
func fill(font: Font) -> void:
	var made: Array = []
	for i in PREFILL[&"claw"]:
		made.append(SkillFx.claw(self, Vector3.ZERO, 0.0))
	for i in PREFILL[&"bolt"]:
		made.append(LightningFx.bolt(self, Vector3.ZERO, 0.0))
	for i in PREFILL[&"slam"]:
		made.append(QuakeFx.slam(self, Vector3.ZERO, 0.0))
	for i in PREFILL[&"ice"]:
		made.append(IceFx.burst(self, Vector3.ZERO, 0.0))
	for i in PREFILL[&"hit"]:
		made.append(HitFx.spawn(self, Vector3.ZERO, {"amount": 0}, font))
	for fx in made:
		fx.finish()


## 떠 있는 것을 전부 멈춰 돌려놓는다 — 존을 옮길 때. 예전에는 존과 같이 지워졌다
func recall() -> void:
	for child in get_children():
		if busy(child) and child.has_method("finish"):
			child.finish()
