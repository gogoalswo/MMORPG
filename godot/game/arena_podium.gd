class_name ArenaPodium
extends SubViewportContainer

## 결투장 시상대 — 랭킹 1 · 2 · 3위가 **장착 정보대로** 입고 단 위에 선다 (2026-10-12 요청: 결투장 창 스크린샷 +
## "여기에 랭킹 1,2,3위 장착정보 반영해서 시상대 만들어서 모델링 띄워") → docs/features/arena.md "시상대"
##
##          이름(1위)
##   이름     ┌───┐    이름
##   ┌───┐    │ 1 │   ┌───┐
##   │ 2 │    │   │   │ 3 │      ← 바르코 돌 3단 시상대 한 덩이(`arena_podium.glb`) + 앞면에 금빛 숫자 (Label3D)
##
## 창 안의 작은 3D 화면이다 — 따로 노는 세계(`own_world_3d`)에 카메라 · 빛 · 시상대 · 캐릭터 셋을 둔다. 바탕은 비춘다(`transparent_bg`).
## 캐릭터는 내 캐릭터와 같은 모델(`Rig.create("varco_fighter")`)에 `Rig.set_weapon` · `set_gear` 로 입힌다 — 게임 속 나와 같은 길.
## 단은 처음엔 코드로 지은 상자였다가 같은 날 "단도 바르코로 만들고" 로 바르코 모델이 됐다.

## 화면 높이(px)
const HEIGHT := 250.0
const MODEL := "res://assets/models/arena_podium.glb"
## 모델은 폭 1 · 원점 바닥으로 받았다. 폭은 `MODEL_SCALE.x` 배, 높이는 그보다 25% 낮게 키운다 — 원화의 단이 사람 키에 비해
## 높아서(1위 단이 폭의 절반) 그대로 키우면 1위 단이 1.4m 다. 돌 덩어리라 높이만 줄여도 티가 안 난다
const MODEL_SCALE := Vector3(2.6, 1.95, 2.6)
## 단 셋 — 모델 좌표(폭 1)로 **잰** 윗면 가운데 x 와 높이 (2026-10-12, 정점을 x 칸으로 나눠 칸마다 가장 높은 y).
## 모델을 갈면 다시 잰다 (docs/features/arena.md "시상대")
const TIERS := [
	{"place": 2, "x": -0.35, "top": 0.38},
	{"place": 1, "x": 0.02, "top": 0.525},
	{"place": 3, "x": 0.375, "top": 0.30},
]
## 앞면 — 모델 깊이 반(0.195)보다 조금 앞에 숫자를 띄운다
const FRONT_Z := 0.2
const GOLD := Color("#e0c27a")
## 카메라 — 정면 조금 위에서 단 셋과 머리 · 이름표까지 다 들어오게
const CAMERA_AT := Vector3(0.0, 1.7, 6.2)
const CAMERA_LOOK := Vector3(0.0, 1.45, 0.0)
const CAMERA_FOV := 36.0

var _view: SubViewport
var _camera: Camera3D
## 자리(1 · 2 · 3) → {rig, name(Label3D), top(단 윗면 y, m)}
var _stands := {}


static func make() -> ArenaPodium:
	var podium := ArenaPodium.new()
	podium._build()
	return podium


func _build() -> void:
	name = "ArenaPodium"
	stretch = true
	custom_minimum_size = Vector2(0, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view = SubViewport.new()
	_view.name = "view"
	_view.own_world_3d = true
	_view.transparent_bg = true
	_view.msaa_3d = Viewport.MSAA_2X
	add_child(_view)

	var env := WorldEnvironment.new()
	var look := Environment.new()
	look.background_mode = Environment.BG_CLEAR_COLOR
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color("#8a8070")
	look.ambient_light_energy = 0.9
	env.environment = look
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.25
	_view.add_child(sun)

	_camera = Camera3D.new()
	_camera.name = "camera"
	_camera.fov = CAMERA_FOV
	_view.add_child(_camera)
	_camera.look_at_from_position(CAMERA_AT, CAMERA_LOOK)

	if ResourceLoader.exists(MODEL):
		var model: Node3D = (load(MODEL) as PackedScene).instantiate()
		model.name = "podium"
		model.scale = MODEL_SCALE
		_view.add_child(model)

	for tier in TIERS:
		var place := int(tier.place)
		var x := float(tier.x) * MODEL_SCALE.x
		var top := float(tier.top) * MODEL_SCALE.y
		# 앞면 숫자 — 단 높이의 가운데
		var number := Label3D.new()
		number.name = "number_%d" % place
		number.text = str(place)
		number.font_size = 150
		number.pixel_size = 0.0022
		number.modulate = GOLD
		number.outline_size = 10
		number.outline_modulate = Color(0, 0, 0, 0.6)
		number.position = Vector3(x, top * 0.5, FRONT_Z * MODEL_SCALE.z)
		_view.add_child(number)

		var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
		if rig != null:
			rig.name = "rig_%d" % place
			rig.position = Vector3(x, top, 0.0)
			rig.visible = false
			_view.add_child(rig)
		var tag := Label3D.new()
		tag.name = "name_%d" % place
		tag.font_size = 72
		tag.pixel_size = 0.0028
		tag.outline_size = 14
		tag.modulate = Color("#f1dc9c") if place == 1 else Color("#ddd6c4")
		tag.outline_modulate = Color(0, 0, 0, 0.85)
		tag.position = Vector3(x, top + Rig.HUMAN_HEIGHT + 0.22, 0.0)
		tag.visible = false
		_view.add_child(tag)
		_stands[place] = {"rig": rig, "name": tag, "top": top, "x": x}


## 랭킹 위 셋 `[1위 줄, 2위 줄, 3위 줄]` — 줄은 `Arena.board` 의 랭킹 줄(`name` · `equipped`). 없는 자리는 빈 단
func show_top(rows: Array, font: Font) -> void:
	for place in [1, 2, 3]:
		var stand: Dictionary = _stands[place]
		var row: Dictionary = rows[place - 1] if rows.size() >= place else {}
		var rig: Rig = stand.rig
		var tag: Label3D = stand.name
		tag.visible = not row.is_empty()
		tag.text = str(row.get("name", ""))
		if font != null:
			tag.font = font
		if rig == null:
			continue
		rig.visible = not row.is_empty()
		if row.is_empty():
			continue
		dress(rig, row.get("equipped", {}))
		rig.play("Idle", 1.0, fmod(place * 1.3, maxf(rig.clip_length("Idle"), 0.1)))


## 장착 정보대로 입힌다 — 게임 속 내 캐릭터(`game.gd` `_wear_weapon`)와 같은 길: 무기는 등급 · 강화(주먹 기운),
## 갑옷 · 투구 · 신발은 등급 스킨
static func dress(rig: Rig, equipped: Dictionary) -> void:
	var weapon: Dictionary = equipped.get("weapon", {})
	rig.set_weapon(int(weapon.get("grade", 0)), int(weapon.get("enhance", 0)))
	for slot in Armor.SLOTS:
		var item: Dictionary = equipped.get(slot, {})
		rig.set_gear(slot, int(item.get("grade", 0)))


func rig_of(place: int) -> Rig:
	return _stands.get(place, {}).get("rig")


func name_of(place: int) -> Label3D:
	return _stands.get(place, {}).get("name")


func camera() -> Camera3D:
	return _camera


## 단 윗면 높이(m) — 테스트가 머리 · 발이 화면 안인지 볼 때 쓴다
func top_of(place: int) -> float:
	return float(_stands.get(place, {}).get("top", 0.0))
