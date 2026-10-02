class_name FitnessFx
extends Control

## 헬스 강화 연출 — 헬스 창(`FitnessPanel`)이 가운데 문장 위·뒤에 얹는다
## (2026-10-02 요청: "헬스 강화 성공 실패에 따라서 아이콘에서 이펙트 나오게 해" → 시안 A).
##
##   burst — 성공. 문장 **뒤**에 금빛 섬광이 부풀고 빛줄기가 사방으로 뻗었다 사그라들고(`rays`),
##           문장 **앞**에서 금빛 반짝이가 밖으로 튀어 위로 떠오르며 깜빡인다(`sparks`). 빛이라 **가산**
##   smoke — 실패. 문장이 잿빛으로 바래며 좌우로 떨고, 가운데서 금이 갔다가 사라지고,
##           잿빛 연기가 아래로 흘러내리며 퍼진다. 흙·연기라 **알파**
##
## 퍼지는 동그란 고리는 쓰지 않는다(이펙트 규칙 3절). 그림 파일 없이 코드로 그린다(1절).
## 시간은 `_process` 의 delta 라 `Engine.time_scale` 을 따른다 (찍을 때 늦출 수 있다).
## → docs/features/effect-rules.md · docs/features/fitness.md "창"

const RAYS_TIME := 0.9
const SPARKS_TIME := 1.1
const SMOKE_TIME := 1.2
const GOLD := Color("#ffd98a")
const WHITE_GOLD := Color("#fff4d6")
const ASH := Color("#9a928a")
## 빛줄기 수 — 긴 것과 짧은 것이 번갈아 선다
const RAYS := 14
const SPARKS := 26
const PUFFS := 11
## 떨림 — 처음 0.35초, 폭 9px 에서 줄어든다
const SHAKE_TIME := 0.35
const SHAKE := 9.0
## 잿빛으로 바랬다가 돌아오는 색
const DIM := Color(0.5, 0.48, 0.46)

var kind := ""
var _t := 0.0
var _life := 1.0
var _emblem: Control
var _rays: Array = []
var _sparks: Array = []
var _puffs: Array = []
var _cracks: Array = []


## 성공 — 뒤판(빛줄기)과 앞판(반짝이) 둘을 문장 앞뒤에 끼운다
static func burst(holder: Control, emblem: Control) -> void:
	_clear(holder)
	var back := _make(holder, "rays", RAYS_TIME, emblem.get_index())
	back._additive()
	back._lay_rays()
	var front := _make(holder, "sparks", SPARKS_TIME, emblem.get_index() + 1)
	front._additive()
	front._lay_sparks()


## 실패 — 앞판 하나가 금 · 연기를 그리고 문장 색과 자리를 흔든다
static func smoke(holder: Control, emblem: Control) -> void:
	_clear(holder)
	var fx := _make(holder, "smoke", SMOKE_TIME, emblem.get_index() + 1)
	fx._emblem = emblem
	fx._lay_smoke()


## 연타(자동 · 빠른 두드림)면 앞 연출을 걷고 새로 건다 — 겹치면 문장 색이 꼬인다
static func _clear(holder: Control) -> void:
	for child in holder.get_children():
		if child is FitnessFx:
			child._finish()


static func _make(holder: Control, what: String, life: float, at: int) -> FitnessFx:
	var fx := FitnessFx.new()
	fx.name = "fx_" + what
	fx.kind = what
	fx._life = life
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(fx)
	holder.move_child(fx, at)
	return fx


func _additive() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


func _lay_rays() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var turn := rng.randf_range(0.0, TAU)
	for i in RAYS:
		_rays.append({
			"angle": turn + TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / RAYS,
			"reach": rng.randf_range(1.3, 1.6) if i % 2 == 0 else rng.randf_range(0.95, 1.15),
			"width": rng.randf_range(0.16, 0.22) if i % 2 == 0 else rng.randf_range(0.1, 0.14),
		})


func _lay_sparks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in SPARKS:
		var angle := rng.randf_range(0.0, TAU)
		var dir := Vector2(cos(angle), sin(angle))
		_sparks.append({
			"at": dir * rng.randf_range(0.08, 0.3),
			"vel": dir * rng.randf_range(0.5, 1.15),
			"delay": rng.randf_range(0.0, 0.25),
			"size": rng.randf_range(0.035, 0.07),
			"blink": rng.randf_range(14.0, 24.0),
			"star": i % 3 == 0,
		})


func _lay_smoke() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in PUFFS:
		# 문장 가장자리(아래쪽 반원)에서 피어 밖 · 아래로 흐른다 — 가운데서 피우면 문장 위 얼룩으로만 보였다
		var angle := lerpf(-0.25, PI + 0.25, (float(i) + rng.randf_range(0.0, 1.0)) / PUFFS)
		var out := Vector2(cos(angle), sin(angle))
		_puffs.append({
			"at": out * rng.randf_range(0.45, 0.6),
			"vel": out * rng.randf_range(0.25, 0.45) + Vector2(0.0, rng.randf_range(0.2, 0.35)),
			"delay": rng.randf_range(0.0, 0.18),
			"size": rng.randf_range(0.22, 0.34),
			"spin": rng.randf_range(-1.0, 1.0),
		})
	# 금 — 가운데 근처 한 점에서 갈래 다섯이 꺾이며 뻗는다. 문장 방패 밖으로 안 나가게 반지름 0.5 안
	var from := Vector2(rng.randf_range(-0.05, 0.05), rng.randf_range(-0.08, 0.02))
	for i in 5:
		var angle := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / 5.0
		var line := PackedVector2Array([from])
		var at := from
		for step in 5:
			angle += rng.randf_range(-0.55, 0.55)
			at += Vector2(cos(angle), sin(angle)) * rng.randf_range(0.07, 0.1)
			line.append(at)
		_cracks.append(line)


func _process(delta: float) -> void:
	_t += delta
	if _t >= _life:
		_finish()
		return
	if kind == "smoke" and is_instance_valid(_emblem):
		var fall := clampf(1.0 - _t / SHAKE_TIME, 0.0, 1.0)
		_emblem.position.x = sin(_t * 62.0) * SHAKE * fall
		# 바로 바랬다가 0.25초부터 0.9초까지 돌아온다
		var back := smoothstep(0.25, 0.9, _t)
		_emblem.modulate = DIM.lerp(Color.WHITE, back)
	queue_redraw()


## 끝 — 문장 색 · 자리를 되돌리고 지운다 (연타로 일찍 걷혀도 같은 길)
func _finish() -> void:
	if kind == "smoke" and is_instance_valid(_emblem):
		_emblem.position.x = 0.0
		_emblem.modulate = Color.WHITE
	kind = ""
	queue_free()


func _draw() -> void:
	match kind:
		"rays": _draw_rays()
		"sparks": _draw_sparks()
		"smoke": _draw_smoke()


## 섬광은 빨리 부풀고 천천히 가라앉는다. 빛줄기는 0.15초 만에 뻗고 천천히 돌며 사그라든다
func _draw_rays() -> void:
	var k := _t / RAYS_TIME
	var mid := size * 0.5
	var unit := size.x * 0.5
	var glow := sin(PI * pow(k, 0.4))
	var radius := unit * (1.5 + 0.4 * k)
	draw_texture_rect(FxTex.glow(), Rect2(mid - Vector2(radius, radius), Vector2(radius, radius) * 2.0),
		false, Color(GOLD, glow))
	var grow := ease(clampf(_t / 0.15, 0.0, 1.0), 0.4)
	var fade := clampf(1.0 - (k - 0.3) / 0.7, 0.0, 1.0)
	if fade <= 0.0:
		return
	var spin := 0.35 * _t
	for ray in _rays:
		var angle: float = ray.angle + spin
		var reach: float = unit * float(ray.reach) * (0.5 + 0.5 * grow) * (1.0 + 0.15 * k)
		var half: float = float(ray.width) * (1.0 - 0.4 * k)
		var tip := mid + Vector2(cos(angle), sin(angle)) * reach
		var left := mid + Vector2(cos(angle - half), sin(angle - half)) * unit * 0.55
		var right := mid + Vector2(cos(angle + half), sin(angle + half)) * unit * 0.55
		# 뿌리는 진하고 끝은 사라진다 — 꼭짓점 색으로. 같은 길에 흰 심을 한 겹 더 (폭만 다른 두 겹)
		draw_polygon(PackedVector2Array([mid, left, tip, right]), PackedColorArray([
			Color(WHITE_GOLD, fade), Color(GOLD, 0.8 * fade), Color(GOLD, 0.0), Color(GOLD, 0.8 * fade),
		]))
		var core := half * 0.35
		draw_polygon(PackedVector2Array([
			mid, mid + Vector2(cos(angle - core), sin(angle - core)) * unit * 0.55, mid.lerp(tip, 0.85),
			mid + Vector2(cos(angle + core), sin(angle + core)) * unit * 0.55,
		]), PackedColorArray([
			Color(WHITE_GOLD, fade), Color(WHITE_GOLD, 0.7 * fade), Color(WHITE_GOLD, 0.0), Color(WHITE_GOLD, 0.7 * fade),
		]))


## 반짝이 — 밖으로 튀며 느려지고 조금 떠오른다. 넷 중 하나는 네 갈래 별
func _draw_sparks() -> void:
	var mid := size * 0.5
	var unit := size.x * 0.5
	for spark in _sparks:
		var local: float = _t - float(spark.delay)
		if local <= 0.0:
			continue
		var life: float = clampf(1.0 - local / (SPARKS_TIME - float(spark.delay)), 0.0, 1.0)
		if life <= 0.0:
			continue
		# 감속 이동 — 처음 빠르고 끝이 느리다
		var went := (1.0 - exp(-3.0 * local)) / 3.0
		var at: Vector2 = mid + (Vector2(spark.at) + Vector2(spark.vel) * went * 2.2 + Vector2(0.0, -0.18 * local * local)) * unit
		var twinkle := 0.65 + 0.35 * sin(local * float(spark.blink))
		var r: float = float(spark.size) * unit * (0.6 + 0.4 * life)
		var alpha := life * twinkle
		draw_texture_rect(FxTex.glow(), Rect2(at - Vector2(r, r) * 2.5, Vector2(r, r) * 5.0), false, Color(GOLD, 0.7 * alpha))
		if spark.star:
			_star(at, r * 3.2, local * 2.0, Color(WHITE_GOLD, alpha))
		else:
			draw_circle(at, r * 0.55, Color(WHITE_GOLD, alpha))


## 네 갈래 별 — `EnhanceFx._star` 와 같은 꼴(긴 십자 + 45° 짧은 십자)
func _star(at: Vector2, r: float, turn: float, tint: Color) -> void:
	if r < 0.5:
		return
	for layer in 2:
		var long := r if layer == 0 else r * 0.45
		var waist := long * 0.16
		var points := PackedVector2Array()
		for i in 8:
			var angle := turn + PI * 0.25 * i + (PI * 0.25 if layer == 1 else 0.0)
			points.append(at + Vector2(cos(angle), sin(angle)) * (long if i % 2 == 0 else waist))
		draw_colored_polygon(points, tint)


## 금이 0.12초 만에 그어지고 0.55초부터 흐려진다. 연기는 늦게 피어 아래로 흐르며 부푼다
func _draw_smoke() -> void:
	var mid := size * 0.5
	var unit := size.x * 0.5
	var draw_k := clampf(_t / 0.12, 0.0, 1.0)
	var crack_a := clampf(1.0 - (_t - 0.55) / 0.35, 0.0, 1.0)
	if crack_a > 0.0:
		var shift := _emblem.position if is_instance_valid(_emblem) else Vector2.ZERO
		for line in _cracks:
			var shown := int(ceil(draw_k * float(line.size() - 1))) + 1
			var points := PackedVector2Array()
			for i in mini(shown, line.size()):
				points.append(mid + shift + Vector2(line[i]) * unit)
			if points.size() < 2:
				continue
			draw_polyline(points, Color(0.05, 0.02, 0.0, 0.9 * crack_a), 6.0, true)
			draw_polyline(points, Color(1.0, 0.4, 0.25, 0.8 * crack_a), 2.0, true)
	for puff in _puffs:
		var local: float = _t - float(puff.delay)
		if local <= 0.0:
			continue
		var k: float = clampf(local / (SMOKE_TIME - float(puff.delay)), 0.0, 1.0)
		var at: Vector2 = mid + (Vector2(puff.at) + Vector2(puff.vel) * local) * unit
		var r: float = float(puff.size) * unit * (0.6 + 0.9 * k)
		# 빨리 짙어졌다가 천천히 흩어진다
		var alpha := sin(PI * pow(k, 0.35)) * 0.6
		draw_set_transform(at, float(puff.spin) * local, Vector2.ONE)
		draw_texture_rect(FxTex.puff(), Rect2(-Vector2(r, r), Vector2(r, r) * 2.0), false, Color(ASH, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
