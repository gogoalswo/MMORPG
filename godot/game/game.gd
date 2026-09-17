extends Node3D

## 화면. 상태는 Transport 에서만 받아 그린다 — World 를 직접 만지지 않는다.
##
## 씬 파일 대신 코드로 짓는 이유: 에디터를 못 쓰는 환경에서 .tscn 을 손으로
## 쓰면 틀리기 쉽고, 이 화면은 존 데이터(바닥 크기·하늘색·안개)에서 나오는
## 것이라 어차피 코드가 정한다. 모델·UI 가 들어오는 단계에서 씬으로 옮긴다.
##
## 지금은 **예측/보정이 없다.** 로컬이라 지연이 0 이므로 스냅샷을 그대로 그려도
## 매끄럽다. 서버를 붙이는 단계에서 넣는다 → docs/features/networking-state.md

const STOP_DISTANCE := 0.15

var _transport: Transport
var _player: Node3D
## 기둥은 가운데가 원점이라 반만큼 띄워야 하고, 모델은 발이 원점이다
var _player_y := 0.9
## 이번 프레임에 걸었나 (달리기·대기 동작을 고르는 데 쓴다)
var _moving := false
## 카메라 스무딩에 쓴다 — _draw_state 가 델타를 따로 안 받는다
var _last_delta := 0.0
## 공격 동작을 언제까지 트나 (서버가 준 경직 시간)
var _swing_until := 0
var _camera: CameraRig
var _label: Label
var _marker: MeshInstance3D

var _target: Vector3 = Vector3.INF
var _seq := 0
var _half_size := 0.0
## 존마다 다시 짓는 것들(바닥·하늘·몬스터·차원문)은 여기 아래에 둔다.
## 캐릭터·카메라·UI 는 존이 바뀌어도 그대로라 밖에 있다
var _zone_node: Node3D
var _shown_zone := ""
## 눌러 둔 몬스터. 사거리에 들 때까지 걸어가서 계속 친다
var _target_mob := ""
## 몬스터 id -> 그려 둔 몸. 죽으면 감추고 살아나면 다시 보인다
var _mob_nodes: Dictionary = {}
## 마지막으로 일어난 일 한 줄 (맞았다·레벨 올랐다)
var _last_event := ""
var _ui_root: Control
var _hp_bar: ProgressBar
## 맞았을 때 화면 가장자리가 붉어지는 비네트 (game/hurt_flash.gd)
var _hurt: HurtFlash
var _gate_panel: PanelContainer
## 보스 범위 공격 예고. [{node, fill, start, end, radius}, ...]
var _aoe_marks: Array = []
var _npc_panel: PanelContainer
var _npc_title: Label
var _npc_rows: VBoxContainer
var _npc_role := ""
var _npc_tab := ""
var _npc_items: Array = []
## 액션바 4칸. 눌리면 그 스킬을 쓴다
var _bar_buttons: Array = []
var _skill_panel: PanelContainer
var _bag_panel: PanelContainer
var _bag_rows: VBoxContainer


func _ready() -> void:
	_transport = LocalTransport.new()
	add_child(_transport)
	_transport.open(GameData.start_zone())
	_transport.event.connect(_on_event)
	_build_persistent()
	# 캐시한 이전 빌드를 보고 있으면 화면이 직접 알려 준다
	Build.check_latest(self, func(latest: String) -> void:
		_last_event = "새 빌드가 있습니다 (%s) — 새로고침하세요" % latest
	)


## 판정이 낸 일. 글자 한 줄과 피격 이펙트로 보여준다
func _on_event(name: StringName, payload: Dictionary) -> void:
	match name:
		&"hit":
			_show_hit(payload)
			var who := "맞음" if payload.get("target_kind", "") == "player" else "피해"
			_last_event = "%s %d%s%s" % [
				who,
				payload.get("amount", 0),
				" 치명타!" if payload.get("crit", false) else "",
				"  처치!" if payload.get("killed", false) else "",
			]
		&"levelUp":
			_last_event = "레벨 %d 이 되었습니다" % payload.get("level", 0)
		&"swing":
			# 휘두르는 동안 발이 묶인다는 통보. 그 시간만큼 공격 동작을 튼다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
		&"died":
			_last_event = "쓰러졌습니다 — 아무 데나 눌러 마을에서 되살아나기"
			_target = Vector3.INF
			_target_mob = ""
			_marker.visible = false
			_gate_panel.visible = false
		&"revived":
			_last_event = "마을에서 되살아났습니다"
		&"aoe":
			_show_aoe(payload)
		&"npc":
			_show_npc(payload)
		&"skill":
			# 스킬도 같은 공격 동작을 쓴다
			_swing_until = Time.get_ticks_msec() + int(payload.get("root_ms", 400))
		&"skills":
			_last_event = "스킬을 배웠습니다"
		&"loot":
			var got := str(payload.get("item", {}).get("id", ""))
			if got == "":
				_last_event = "골드 %d" % payload.get("gold", 0)
			else:
				_last_event = "골드 %d, %s" % [
					payload.get("gold", 0), Items.get_item(got).get("name", got)
				]
		&"inventory":
			if _bag_panel.visible:
				_redraw_bag()
			if _npc_panel.visible:
				_redraw_npc()
		&"skillBar":
			pass
		&"notice":
			_last_event = str(payload.get("text", ""))
		&"gate":
			# 차원문에 섰다. 어디로 갈지는 사람이 고른다
			_gate_panel.visible = true
		&"zone":
			_last_event = "%s 에 도착했습니다" % GameData.zone(str(payload.get("zone", ""))).get("name", "")


## 존이 바뀌어도 살아 있는 것들
func _build_persistent() -> void:
	# 모델이 있으면 모델, 없으면 기둥. npm run sync:godot 을 안 돌렸을 수도 있다
	var rig := Rig.create("varco_knight", Rig.HUMAN_HEIGHT)
	if rig != null:
		_player = rig
		_player_y = 0.0
	else:
		var capsule := MeshInstance3D.new()
		var body := CapsuleMesh.new()
		body.radius = Movement.PLAYER_RADIUS
		body.height = 1.8
		capsule.mesh = body
		var body_mat := StandardMaterial3D.new()
		body_mat.albedo_color = Color("#e8d7b0")
		capsule.material_override = body_mat
		_player = capsule
		_player_y = 0.9
	add_child(_player)

	# 어디를 눌렀는지 보여주는 표시 (웹 클라의 클릭 이동 표시와 같은 역할)
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.35
	ring.outer_radius = 0.5
	_marker.mesh = ring
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color("#4aa8ff")
	ring_mat.emission_enabled = true
	ring_mat.emission = Color("#4aa8ff")
	_marker.material_override = ring_mat
	_marker.visible = false
	add_child(_marker)

	_camera = CameraRig.new()
	add_child(_camera)

	var ui := CanvasLayer.new()
	add_child(ui)

	# 한글 폰트를 테마로 깐다. 고도 기본 폰트에는 한글 글리프가 없어서
	# 안 깔면 "마을" 이 네모로 나온다 (npm run sync:godot 이 복사해 둔다)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 화면 아무 데나 눌러 걸어야 하므로 UI 바탕은 터치를 먹지 않는다.
	# 단추는 제 몫을 따로 먹는다
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.theme = _make_theme()
	ui.add_child(_ui_root)

	# 제일 먼저 넣어 HUD 글자 밑에 깔린다 — 비네트가 체력·상태를 가리면 안 된다
	_hurt = HurtFlash.new()
	_ui_root.add_child(_hurt)

	_label = Label.new()
	_label.position = Vector2(24, 24)
	_ui_root.add_child(_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(24, 150)
	_hp_bar.size = Vector2(360, 34)
	_hp_bar.show_percentage = false
	_ui_root.add_child(_hp_bar)

	_build_gate_panel()
	_build_npc_panel()
	_build_skill_bar()
	_build_skill_panel()
	_build_bag_panel()


## 가방과 장비. 웹 클라의 ui/inventory.ts 자리다.
## 목록은 **열 때마다 다시 그린다** — 줍고 끼는 동안 계속 바뀌기 때문이다
func _build_bag_panel() -> void:
	_bag_panel = PanelContainer.new()
	_bag_panel.set_anchors_preset(Control.PRESET_CENTER)
	_bag_panel.visible = false
	_ui_root.add_child(_bag_panel)

	_bag_rows = VBoxContainer.new()
	_bag_panel.add_child(_bag_rows)


func _toggle_bag() -> void:
	_bag_panel.visible = not _bag_panel.visible
	if _bag_panel.visible:
		_redraw_bag()


func _redraw_bag() -> void:
	for child in _bag_rows.get_children():
		child.queue_free()

	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return

	var title := Label.new()
	title.text = "가방 %d/%d   골드 %d" % [me.bag.size(), Items.bag_size(), me.get("gold", 0)]
	_bag_rows.add_child(title)

	# 끼고 있는 것 — 누르면 벗는다
	for slot in Items.slots():
		var stack: Dictionary = me.equipped.get(slot, {})
		var button := Button.new()
		if stack.is_empty():
			button.text = "[%s] 비었음" % slot
			button.disabled = true
		else:
			button.text = "[%s] %s" % [slot, _stack_label(stack)]
			button.pressed.connect(func() -> void:
				_transport.send(&"unequip", {"slot": str(slot)})
				_redraw_bag()
			)
		_bag_rows.add_child(button)

	# 가방 — 누르면 낀다. **낄 수 있는지는 World 가 다시 본다**
	for index in mini(me.bag.size(), 12):
		var stack: Dictionary = me.bag[index]
		var button := Button.new()
		button.text = _stack_label(stack)
		button.pressed.connect(func() -> void:
			_transport.send(&"equip", {"index": index})
			_redraw_bag()
		)
		_bag_rows.add_child(button)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _bag_panel.visible = false)
	_bag_rows.add_child(close)


## "낡은 장검 +3 (5등급) 공격 +7, 치명타 +2%"
func _stack_label(stack: Dictionary) -> String:
	var item := Items.get_item(str(stack.get("id", "")))
	var text := str(item.get("name", stack.get("id", "?")))
	var enhance := int(stack.get("enhance", 0))
	if enhance > 0:
		text += " +%d" % enhance
	text += " (%d등급)" % int(stack.get("grade", 1))
	var options: Array = []
	for option in stack.get("options", []):
		options.append(Items.describe_option(option))
	if not options.is_empty():
		text += "\n" + ", ".join(options)
	return text


## 액션바. 칸 수는 데이터가 정한다 (combat.json 의 skillBarSize)
func _build_skill_bar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.position = Vector2(-260, -110)
	_ui_root.add_child(row)

	for slot in int(GameData.combat().get("skillBarSize", 4)):
		var button := Button.new()
		button.custom_minimum_size = Vector2(125, 70)
		button.text = "-"
		button.pressed.connect(_on_bar_pressed.bind(slot))
		row.add_child(button)
		_bar_buttons.append(button)

	var open := Button.new()
	open.text = "스킬"
	open.custom_minimum_size = Vector2(110, 70)
	open.pressed.connect(func() -> void: _skill_panel.visible = not _skill_panel.visible)
	row.add_child(open)

	var bag := Button.new()
	bag.text = "가방"
	bag.custom_minimum_size = Vector2(110, 70)
	bag.pressed.connect(_toggle_bag)
	row.add_child(bag)


## 스킬창 — 내 직업 스킬을 늘어놓고, 누르면 배워서 액션바에 올린다.
## **스킬 내용은 다시 만들기로 했다.** 여기는 표를 읽어 줄을 세울 뿐이라
## 표가 바뀌면 그대로 따라온다
func _build_skill_panel() -> void:
	_skill_panel = PanelContainer.new()
	_skill_panel.set_anchors_preset(Control.PRESET_CENTER)
	_skill_panel.visible = false
	_ui_root.add_child(_skill_panel)

	var rows := VBoxContainer.new()
	_skill_panel.add_child(rows)

	var title := Label.new()
	title.text = "스킬"
	rows.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	rows.add_child(grid)

	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	for id in Skills.for_job(str(me.get("job", "knight"))):
		var skill: Dictionary = Skills.all().get(str(id), {})
		var button := Button.new()
		button.text = "%s\n%d레벨" % [skill.get("name", id), skill.get("reqLevel", 1)]
		button.pressed.connect(_on_skill_pressed.bind(str(id)))
		grid.add_child(button)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _skill_panel.visible = false)
	rows.add_child(close)


## 스킬창에서 고르면 배우고 빈 칸에 올린다. **배울 수 있는지는 World 가 다시 본다**
func _on_skill_pressed(skill_id: String) -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	_transport.send(&"learnSkill", {"skill": skill_id})

	var bar: Array = me.get("skill_bar", []).duplicate()
	if skill_id in bar:
		return
	var size := int(GameData.combat().get("skillBarSize", 4))
	if bar.size() >= size:
		bar.remove_at(0)
	bar.append(skill_id)
	_transport.send(&"setSkillBar", {"bar": bar})


func _on_bar_pressed(slot: int) -> void:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	var bar: Array = me.get("skill_bar", [])
	if slot >= bar.size():
		_skill_panel.visible = true
		return
	_transport.send(&"skill", {"skill": str(bar[slot])})


## NPC 와 말하는 창. 웹 클라의 ui/npcDialog.ts 자리다
func _build_npc_panel() -> void:
	_npc_panel = PanelContainer.new()
	_npc_panel.set_anchors_preset(Control.PRESET_CENTER)
	_npc_panel.visible = false
	_ui_root.add_child(_npc_panel)

	var rows := VBoxContainer.new()
	_npc_panel.add_child(rows)

	_npc_title = Label.new()
	rows.add_child(_npc_title)

	_npc_rows = VBoxContainer.new()
	rows.add_child(_npc_rows)


func _show_npc(payload: Dictionary) -> void:
	var role := str(payload.get("role", ""))
	var title := str(payload.get("title", ""))
	_npc_title.text = "%s%s" % [
		payload.get("name", ""),
		"  (%s)" % title if title != "" else "",
	]
	_npc_role = role
	_npc_items = payload.get("items", [])
	_npc_tab = "buy" if role == "shop" else "forge"
	_redraw_npc()
	_npc_panel.visible = true


## 목록은 **열 때마다 다시 그린다** — 사고팔고 두드리는 동안 계속 바뀐다.
## 웹 클라의 npcDialog(상점) · craftWindow(대장간 탭 3개) 자리다
func _redraw_npc() -> void:
	for child in _npc_rows.get_children():
		child.queue_free()

	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	if me.is_empty():
		return

	var gold := Label.new()
	gold.text = "골드 %d   가방 %d/%d" % [me.get("gold", 0), me.bag.size(), Items.bag_size()]
	_npc_rows.add_child(gold)

	var tabs := HBoxContainer.new()
	_npc_rows.add_child(tabs)
	var names := {"buy": "사기", "sell": "팔기"} if _npc_role == "shop" else {
		"forge": "새로 만들기", "enhance": "강화", "craft": "등급 올리기"
	}
	for key in names:
		var tab := Button.new()
		tab.text = names[key]
		tab.disabled = (_npc_tab == key)
		tab.pressed.connect(func() -> void:
			_npc_tab = str(key)
			_redraw_npc()
		)
		tabs.add_child(tab)

	match _npc_tab:
		"buy":
			_list_buy(me)
		"sell":
			_list_bag(me, "팔기", func(index: int) -> void:
				_transport.send(&"npcSell", {"index": index})
			)
		"forge":
			_list_forge(me)
		"enhance":
			_list_bag(me, "강화", func(index: int) -> void:
				_transport.send(&"npcEnhance", {"index": index})
			)
		"craft":
			_list_bag(me, "등급", func(index: int) -> void:
				_transport.send(&"npcCraft", {"index": index})
			)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _npc_panel.visible = false)
	_npc_rows.add_child(close)


func _list_buy(me: Dictionary) -> void:
	for id in _npc_items:
		var item := Items.get_item(str(id))
		var button := Button.new()
		button.text = "%s   %d G" % [item.get("name", id), item.get("price", 0)]
		button.disabled = int(me.get("gold", 0)) < int(item.get("price", 0))
		button.pressed.connect(func() -> void:
			_transport.send(&"npcBuy", {"item": str(id)})
			_redraw_npc()
		)
		_npc_rows.add_child(button)


## 만들 수 있는 것이 레벨을 따라 길어진다. **가진 재료로 만들 수 있는 것만** 올린다 —
## 안 거르면 200레벨에 160줄이 깔려 정작 무엇을 만들 수 있는지가 안 보인다
func _list_forge(me: Dictionary) -> void:
	var shown := 0
	for id in _npc_items:
		if shown >= 12:
			break
		var item := Items.get_item(str(id))
		var recipe := Items.forge_recipe(item)
		if recipe.is_empty():
			continue
		var have := 0
		for stack in me.bag:
			if str(stack.get("id", "")) == str(recipe.materialId):
				have += 1
		if have < int(recipe.materialCount):
			continue
		shown += 1
		var button := Button.new()
		button.text = "%s   %s %d개 + %d G" % [
			item.get("name", id), recipe.materialName, recipe.materialCount, recipe.gold
		]
		button.pressed.connect(func() -> void:
			_transport.send(&"npcForge", {"item": str(id)})
			_redraw_npc()
		)
		_npc_rows.add_child(button)
	if shown == 0:
		var empty := Label.new()
		empty.text = "만들 수 있는 것이 없습니다 (보스가 재료를 떨굽니다)"
		_npc_rows.add_child(empty)


func _list_bag(me: Dictionary, verb: String, action: Callable) -> void:
	if me.bag.is_empty():
		var empty := Label.new()
		empty.text = "가방이 비었습니다"
		_npc_rows.add_child(empty)
		return
	for index in mini(me.bag.size(), 12):
		var stack: Dictionary = me.bag[index]
		var button := Button.new()
		button.text = "%s  [%s]" % [_stack_label(stack), verb]
		button.pressed.connect(func() -> void:
			action.call(index)
			_redraw_npc()
		)
		_npc_rows.add_child(button)



func _make_theme() -> Theme:
	var theme := Theme.new()
	var path := "res://assets/fonts/NotoSansKR-subset.ttf"
	if ResourceLoader.exists(path):
		theme.default_font = load(path)
	theme.default_font_size = 28
	return theme


## 차원문에 서면 뜨는 사냥터 목록. 웹 클라의 ui/zoneGate.ts 와 같은 자리다
func _build_gate_panel() -> void:
	_gate_panel = PanelContainer.new()
	_gate_panel.set_anchors_preset(Control.PRESET_CENTER)
	_gate_panel.visible = false
	_ui_root.add_child(_gate_panel)

	var rows := VBoxContainer.new()
	_gate_panel.add_child(rows)

	var title := Label.new()
	title.text = "어디로 갈까요"
	rows.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	rows.add_child(grid)

	# 마을 + 사냥터 20곳. 순서는 데이터가 정한다 (zones.json 의 fieldOrder)
	var ids: Array = [GameData.start_zone()]
	ids.append_array(GameData.field_order())
	for id in ids:
		var zone := GameData.zone(str(id))
		var button := Button.new()
		button.text = str(zone.get("name", id))
		button.pressed.connect(_on_gate_pick.bind(str(id)))
		grid.add_child(button)

	var close := Button.new()
	close.text = "닫기"
	close.pressed.connect(func() -> void: _gate_panel.visible = false)
	rows.add_child(close)


func _on_gate_pick(zone_id: String) -> void:
	_gate_panel.visible = false
	_target = Vector3.INF
	_target_mob = ""
	_marker.visible = false
	_transport.send(&"travel", {"zone": zone_id})


## 존 하나를 짓는다. 차원문으로 옮기면 통째로 버리고 다시 짓는다
func _build_zone(zone_id: String) -> void:
	if _zone_node != null:
		_zone_node.queue_free()
	_aoe_marks.clear()
	_zone_node = Node3D.new()
	add_child(_zone_node)
	_shown_zone = zone_id

	var zone := GameData.zone(zone_id)
	var env: Dictionary = zone.get("env", {})
	var size := float(zone.get("size", 92))
	_half_size = Movement.zone_half_size(size)
	_target = Vector3.INF
	_marker.visible = false

	var world_env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(env.get("skyColor", "#b9c9d8"))
	e.ambient_light_energy = float(env.get("hemiIntensity", 1.1))
	e.fog_enabled = true
	e.fog_light_color = Color(env.get("fogColor", "#c2c8b8"))
	e.fog_density = 0.006
	world_env.environment = e
	_zone_node.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_energy = float(env.get("sunIntensity", 2.7))
	sun.rotation_degrees = Vector3(-50, -35, 0)
	_zone_node.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	ground.mesh = plane
	ground.material_override = Ground.material_for(env, size)
	_zone_node.add_child(ground)


	# 차원문. 여기 들어가면 존이 바뀐다 (World._check_gate)
	var gate: Dictionary = zone.get("gate", {})
	if not gate.is_empty():
		var gate_pos: Array = gate.get("position", [0, 0])
		var portal := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(gate.get("radius", 2.6))
		disc.bottom_radius = disc.top_radius
		disc.height = 0.08
		portal.mesh = disc
		var gate_mat := StandardMaterial3D.new()
		gate_mat.albedo_color = Color(gate.get("color", "#4aa8ff"))
		gate_mat.emission_enabled = true
		gate_mat.emission = Color(gate.get("color", "#4aa8ff"))
		portal.material_override = gate_mat
		portal.position = Vector3(float(gate_pos[0]), 0.04, float(gate_pos[1]))
		_zone_node.add_child(portal)

	# NPC. 모델이 없는 look 뿐이라 기둥에 이름표를 얹는다
	for npc in _transport.snapshot().get("npcs", []):
		var post := MeshInstance3D.new()
		var shape := CapsuleMesh.new()
		shape.radius = 0.35
		shape.height = 1.7
		post.mesh = shape
		var npc_mat := StandardMaterial3D.new()
		npc_mat.albedo_color = Color("#d8c48a") if npc.has("role") else Color("#b9b3a6")
		post.material_override = npc_mat
		post.position = Vector3(npc.x, shape.height * 0.5, npc.z)
		_zone_node.add_child(post)

		var plate := Label3D.new()
		plate.text = "%s\n%s" % [npc.get("name", ""), npc.get("title", "")]
		plate.font = _ui_root.theme.default_font
		plate.font_size = 64
		plate.pixel_size = 0.004
		plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		plate.no_depth_test = true
		plate.position = Vector3(npc.x, 2.3, npc.z)
		_zone_node.add_child(plate)

	# 몬스터. 자리는 World 가 정했고 여기서는 그리기만 한다.
	# 모델이 있는 look 만 모델이고 나머지는 기둥이다 (웹 클라도 같은 규칙)
	_mob_nodes.clear()
	for monster in _transport.snapshot().get("monsters", []):
		var kind := GameData.monster_kind(monster.kind)
		var look := str(kind.get("look", ""))
		var height := GameData.beast_height(look, float(monster.scale))
		var node: Node3D = Rig.create(look, height)
		var foot := 0.0
		if node == null:
			var body := MeshInstance3D.new()
			var shape := CapsuleMesh.new()
			shape.radius = monster.r
			shape.height = maxf(monster.r * 2.0 + 0.1, height)
			body.mesh = shape
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(monster.color)
			if monster.boss:
				mat.emission_enabled = true
				mat.emission = Color(monster.color) * 0.6
			body.material_override = mat
			node = body
			foot = shape.height * 0.5
		node.position = Vector3(monster.x, foot, monster.z)
		_zone_node.add_child(node)
		_mob_nodes[monster.id] = node


func _unhandled_input(event: InputEvent) -> void:
	# 터치는 기본 설정이 마우스로 바꿔 주므로 이 한 줄이 폰도 덮는다
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 죽어 있으면 어딜 눌러도 부활 요청이다
		if _am_dead():
			_transport.send(&"revive", {})
			return
		var hit := _ground_point(event.position)
		if hit == Vector3.INF:
			return
		# NPC 를 눌렀으면 말을 건다. **닿는지는 World 가 다시 본다**
		var npc := _npc_at(hit)
		if npc != "":
			_transport.send(&"npc", {"name": npc})
			return
		# 몬스터를 눌렀으면 그놈을 잡으러 간다. 아니면 그 자리로 걸어간다
		var mob := _mob_at(hit)
		if mob != "":
			_target_mob = mob
			_target = Vector3.INF
			_marker.visible = false
		else:
			_target_mob = ""
			_target = hit
			_marker.position = hit + Vector3(0, 0.05, 0)
			_marker.visible = true


## 바닥의 그 자리에 NPC 가 있나
func _npc_at(point: Vector3) -> String:
	for npc in _transport.snapshot().get("npcs", []):
		if Vector2(point.x - float(npc.x), point.z - float(npc.z)).length() < 1.2:
			return str(npc.get("name", ""))
	return ""


## 바닥의 그 자리에 산 몬스터가 있나. 손가락은 굵으니 반지름에 여유를 준다
func _mob_at(point: Vector3) -> String:
	var best := ""
	var best_gap := INF
	for monster in _transport.snapshot().get("monsters", []):
		if int(monster.hp) <= 0:
			continue
		var gap: float = Vector2(point.x - monster.x, point.z - monster.z).length() - monster.r
		if gap < 0.8 and gap < best_gap:
			best_gap = gap
			best = monster.id
	return best


## 화면의 한 점이 바닥의 어디인지
func _ground_point(screen: Vector2) -> Vector3:
	if _camera == null:
		return Vector3.INF
	var from := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	return hit if hit != null else Vector3.INF


func _process(delta: float) -> void:
	_moving = false
	_last_delta = delta
	_send_input(delta)
	_draw_state()
	_tick_aoe()


## 눌러 둔 자리로 향하는 방향을 만들어 보낸다. **요청일 뿐이고 판정은 World 가 한다.**
func _am_dead() -> bool:
	var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
	return bool(me.get("dead", false))


func _send_input(delta: float) -> void:
	if _zone_node == null or _am_dead():
		return
	if _target_mob != "":
		_chase_and_hit(delta)
		return
	if _target == Vector3.INF:
		return
	var me := _my_position()
	var to := Vector2(_target.x - me.x, _target.z - me.z)
	if to.length() <= STOP_DISTANCE:
		_target = Vector3.INF
		_marker.visible = false
		return
	_move(to.normalized(), delta)


## 눌러 둔 몬스터에게 걸어가서 사거리에 들면 계속 친다.
## 때릴 수 있는지는 **World 가 다시 본다** — 여기서 보내는 건 요청일 뿐이다
func _chase_and_hit(delta: float) -> void:
	var snap := _transport.snapshot()
	var me: Dictionary = snap.get("players", {}).get(_transport.my_id(), {})
	var mob := _find_mob(snap, _target_mob)
	if me.is_empty() or mob.is_empty() or int(mob.hp) <= 0:
		_target_mob = ""
		return

	var to := Vector2(mob.x - me.x, mob.z - me.z)
	var dir := to.normalized()
	var reach: float = float(me.stats.attackRange)
	if to.length() > reach:
		_move(dir, delta)
		return
	# 사거리 안이다. 제자리에서 그쪽을 보고(dt 0) 친다
	_move(dir, 0.0)
	_transport.send(&"attack", {})


func _move(dir: Vector2, delta: float) -> void:
	_seq += 1
	_moving = delta > 0.0
	_transport.send(&"input", {"seq": _seq, "dx": dir.x, "dz": dir.y, "dt": delta})


## 죽음 > 공격 > 달리기 > 대기 순으로 고른다.
##
## 공격 클립은 5.07초짜리라 통째로 틀면 한 번 휘두르는 데 5초가 걸린다.
## 웹 클라이언트는 0.8~1.60초 구간만 1.6배로 트는데(`modelRig` 의 ATTACK_CLIPS),
## 여기서도 같은 자리에서 시작한다. **정확한 구간 맞추기는 아직 안 했다** —
## 발이 미끄러지거나 동작이 어긋나면 그때 재서 고친다.
func _play_player_clip(me: Dictionary) -> void:
	if not _player is Rig:
		return
	var rig: Rig = _player
	if bool(me.get("dead", false)):
		rig.play("Death")
		return
	if Time.get_ticks_msec() < _swing_until:
		rig.play("Attack", 1.6, 0.8)
		return
	rig.play("Run" if _moving else "Idle")


func _find_mob(snap: Dictionary, id: String) -> Dictionary:
	for monster in snap.get("monsters", []):
		if monster.id == id:
			return monster
	return {}


func _my_position() -> Vector3:
	var players: Dictionary = _transport.snapshot().get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return Vector3.ZERO
	return Vector3(me.x, 0, me.z)


func _draw_state() -> void:
	var snap := _transport.snapshot()
	# 차원문으로 옮겼으면 존을 통째로 다시 짓는다
	var zone_now := str(snap.get("zone", ""))
	var zone_changed := zone_now != "" and zone_now != _shown_zone
	if zone_changed:
		_build_zone(zone_now)

	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(_transport.my_id(), {})
	if me.is_empty():
		return

	_player.position = Vector3(me.x, _player_y, me.z)
	_player.rotation.y = me.rot
	_play_player_clip(me)

	# 뒤 위에서 내려다본다. 지금은 고정 각도다
	# 존을 옮긴 프레임에는 보간 없이 곧바로 자리잡는다
	_camera.follow(_player.position, _last_delta, zone_changed)

	# 쫓아오는 놈들이 실제로 움직인다. 자리는 World 가 정하고 여기서는 따라 그린다
	for monster in snap.get("monsters", []):
		var node: Node3D = _mob_nodes.get(monster.id)
		if node == null:
			continue
		node.visible = int(monster.hp) > 0
		if not node.visible:
			continue
		node.position.x = monster.x
		node.position.z = monster.z
		node.rotation.y = monster.get("rot", 0.0)
		if node is Rig:
			var state := str(monster.get("state", "idle"))
			if state == "chase":
				node.play("Run")
			elif state == "attack":
				node.play("Attack")
			else:
				node.play("Idle")

	var alive := 0
	for monster in snap.get("monsters", []):
		if int(monster.hp) > 0:
			alive += 1
	_player.visible = not bool(me.get("dead", false))

	_hp_bar.max_value = me.stats.maxHp
	_hp_bar.value = me.hp
	_refresh_bar(me)

	_label.text = "%s   %d레벨   체력 %d/%d   경험치 %d/%d\n골드 %d   몬스터 %d/%d   %d fps   빌드 %s\n%s" % [
		GameData.zone(zone_now).get("name", zone_now),
		me.level,
		me.hp,
		me.stats.maxHp,
		me.exp,
		Combat.exp_to_next(int(me.level)),
		me.get("gold", 0),
		alive,
		snap.get("monsters", []).size(),
		Engine.get_frames_per_second(),
		Build.stamp(),
		_last_event,
	]


## 맞았다. 맞은 자리에서 터뜨리고, 맞은 몸을 붉게 물들이고, 내가 맞았으면
## 화면 가장자리까지 붉힌다. **판정은 여기서 하지 않는다** — payload 를 그대로 읽는다.
func _show_hit(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	var on_me := str(payload.get("target_kind", "")) == "player"
	var body: Node3D = null
	if on_me:
		body = _player
	else:
		body = _mob_nodes.get(str(payload.get("target", "")), null)

	# 자리는 World 가 준 것을 쓰고, 높이만 그려 둔 몸에서 잰다
	var at := Vector3(payload.get("x", 0.0), 0.0, payload.get("z", 0.0))
	at.y = HitFx.chest_y(body, 1.0)

	var font: Font = _ui_root.theme.default_font if _ui_root.theme != null else null
	var fx := HitFx.spawn(_zone_node, at, payload, font)
	if body != null and not bool(payload.get("heal", false)):
		fx.flash_body(body)

	# 회복은 맞은 것이 아니다
	if on_me and not bool(payload.get("heal", false)):
		var me: Dictionary = _transport.snapshot().get("players", {}).get(_transport.my_id(), {})
		var max_hp := float(me.get("stats", {}).get("maxHp", 100))
		# 최대 체력의 4분의 1을 한 번에 맞으면 제일 진하다
		_hurt.hit(float(payload.get("amount", 0)) / maxf(1.0, max_hp * 0.25))


## 보스 범위 공격 예고 원.
##
## 바깥 테두리는 **터질 자리와 크기**를 그대로 보여 주고(판정과 같은 반지름),
## 안쪽 원이 차오르며 남은 시간을 알린다. 다 차면 터진다 — 그 전에 테두리
## 밖으로 나가면 안 맞는다 (`World._burst_aoe` 가 원으로 다시 자른다).
func _show_aoe(payload: Dictionary) -> void:
	if _zone_node == null:
		return
	var radius := float(payload.get("radius", 7.0))
	var here := Vector3(payload.get("x", 0.0), 0.06, payload.get("z", 0.0))

	var mark := Node3D.new()
	mark.position = here
	_zone_node.add_child(mark)

	var edge := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.25
	ring.outer_radius = radius
	edge.mesh = ring
	edge.material_override = _aoe_material(0.85)
	mark.add_child(edge)

	var fill := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.04
	fill.mesh = disc
	fill.material_override = _aoe_material(0.3)
	mark.add_child(fill)

	var now := Time.get_ticks_msec()
	_aoe_marks.append({
		"node": mark,
		"fill": fill,
		"start": now,
		"end": now + int(payload.get("delay_ms", 1600)),
		"radius": radius,
	})


func _aoe_material(alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.25, 0.2, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## 액션바 글자를 상태에 맞춘다. 쿨타임이 남았으면 남은 초를 적는다
func _refresh_bar(me: Dictionary) -> void:
	var bar: Array = me.get("skill_bar", [])
	var ready_at: Dictionary = me.get("skill_ready_at", {})
	var now := Time.get_ticks_msec()
	for slot in _bar_buttons.size():
		var button: Button = _bar_buttons[slot]
		if slot >= bar.size():
			button.text = "+"
			button.disabled = false
			continue
		var id := str(bar[slot])
		var skill: Dictionary = Skills.all().get(id, {})
		var left := int(ready_at.get(id, 0)) - now
		if left > 0:
			button.text = "%s\n%.1f초" % [skill.get("name", id), left / 1000.0]
			button.disabled = true
		else:
			button.text = str(skill.get("name", id))
			button.disabled = false


func _tick_aoe() -> void:
	var now := Time.get_ticks_msec()
	var alive: Array = []
	for mark in _aoe_marks:
		if not is_instance_valid(mark.node):
			continue
		var span: float = maxf(1.0, float(mark.end - mark.start))
		var ratio := clampf((now - mark.start) / span, 0.0, 1.0)
		mark.fill.scale = Vector3(mark.radius * ratio, 1.0, mark.radius * ratio)
		if ratio >= 1.0:
			mark.node.queue_free()
			continue
		alive.append(mark)
	_aoe_marks = alive
