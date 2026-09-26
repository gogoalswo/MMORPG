extends SceneTree

## **이펙트를 눈으로 보는 도구.** 게임을 가상 디스플레이에 띄워 스킬을 한 번
## 시전하고, 그 장면을 `logs/shot_NN.png` 로 뽑는다.
##
## 2026-09-18 에 만들었다 — 낙뢰를 노드 수치로만 확인해서 "퀄리티가 너무
## 떨어진다" 는 지적을 받았다. 방출기 21개·알갱이 99개·338px 이 다 통과인데
## **화면에는 번개가 없었다**: 62m/s 짜리 줄기가 프레임 사이로 지나갔고,
## 땅의 금은 흰 꽃, 파편은 노란 알갱이였다. 노드로 읽을 수 없는 것이 있다
## → [verification.md](../../docs/features/verification.md)
##
##   npm run shot:godot                  낙뢰(thunder_fall)
##   npm run shot:godot -- rising_kick    스킬 id 를 주면 그것
##   npm run shot:godot -- rising_kick@90 그 쪽(도, 0 = +Z)을 보고 쓴다
##   npm run shot:godot -- thunder_fall+stun+wide@45  스킬 강화를 붙여서 쓴다 (`+` 로 여럿, `@` 는 맨 뒤)
##   npm run shot:godot -- sky_breaker 2,9,20,45,90,150   찍을 프레임을 준다
##                                        (긴 이펙트는 기본 0.36초로 모자란다)
##   npm run shot:godot -- enhance        강화 팝업 다중 강화 한 바퀴 (logs/shot_enhance.png)
##   npm run shot:godot -- fist           주먹 기운 등급 1~7 (logs/shot_sheet.png)
##   npm run shot:godot -- fist:enhance   강화 단계별 오로라 — 희귀·태초 +5~+9
##
## 여섯 장의 **가운데를 잘라 한 장으로 붙인 것**(`logs/shot_sheet.png`)도 뽑는다.
## 한 장씩 읽으면 여섯 배를 낸다 — 시간 순서를 보는 데는 이것 한 장이면 된다.
##
## **시간을 늦춰서 찍는다** (`SLOW`). 소프트웨어 렌더가 5~9fps 라 프레임 간격이
## 0.1~0.2초인데 이펙트 한 토막은 0.12초짜리다 — 제 속도로 찍으면 이미 꺼진
## 뒤만 남는다.

## 게임 시간을 몇 배로 늦추나
const SLOW := 0.08
## 몇 프레임째를 찍나. `SLOW` 를 곱하면 대략 0.03·0.08·0.15·0.22·0.32·0.48초다
const SHOTS := [2, 5, 9, 14, 20, 30]
## 요구 레벨과 포인트를 안 보고 배우게 해 준다 (스킬창을 누를 사람이 없다)
const LEVEL := 200

## `portal` 로 찍을 때 — 문에서 몇 미터 앞에 서나(반지름 2.6 밖이어야 창이 안 뜬다)
const PORTAL_STAND := 6.0
## 카메라가 보는 높이. 아치가 5.2m 라 가운데를 봐야 문이 화면에 든다
const PORTAL_LOOK := 2.4
## 문까지의 거리. 게임 각(요 45·피치 42)은 그대로 두고 가까이만 당긴다 —
## 소용돌이가 화면에서 작으면 찍어도 못 읽는다 (CLAUDE.md 의 "확인이 되는 크기로")
const PORTAL_DISTANCE := 9.0
## 몇 프레임째를 찍나. 소용돌이는 계속 돌므로 한 바퀴를 고르게 나눈다
const PORTAL_SHOTS := [4, 12, 20, 28]
## `hud` 로 찍을 때. 고리가 도는지 보려면 몇 프레임 떨어뜨려 찍어야 한다
const HUD_SHOTS := [6, 20, 40]

## `range:` 로 찍을 때 — 몬스터 무리 한가운데에 선다. 마을에서 찍으면 모양은
## 보이지만 **덮는 넓이**를 못 본다 (범위기를 보는 이유가 그건데)
const RANGE_ZONE := "meadow"
const RANGE_PACK := Vector3(-28.0, 0.0, -28.0)
## 표시가 1.1초 살아 있고 마지막 0.45초는 흐려진다 — 한창 진할 때를 고른다
const RANGE_SHOTS := [3, 10]


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	var skill := "thunder_fall"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]) != "":
		skill = str(args[0])
	var shots: Array = SHOTS
	if args.size() > 1 and str(args[1]) != "":
		shots = Array(str(args[1]).split(",")).map(func(s): return int(s))

	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	# 차원문은 스킬이 아니라 **늘 켜져 있는** 이펙트다 — 시전 대신 문 앞에 세우고 찍는다
	if skill == "portal":
		await _portal(game)
		return

	# 차원문 창 — 이펙트가 아니라 UI 다. HUD 에 안 가리는지, 누른 줄이 눌려 보이는지
	if skill == "gate":
		await _gate(game)
		return

	# HUD 는 시전할 것이 없다 — 액션바를 채우고 자동사냥을 켠 채로 찍는다
	# (켜져 있어야 자동사냥 칸에서 고리가 돈다)
	if skill == "hud":
		await _hud(game)
		return

	# 스킬 범위 표시 — `npm run shot:godot -- range:sky_breaker`
	if skill.begins_with("range:"):
		await _range(game, skill.trim_prefix("range:"))
		return

	# 몬스터를 한 대로 잡는다 — 피해 숫자와 `+n EXP` 가 겹치지 않는지 본다
	if skill == "kill":
		await _kill(game)
		return
	# 치명타 한 대 — 자홍 숫자 · 몸 튕김 · 찌그러짐 · 흔들림 (잡지 않는다)
	if skill == "crit":
		await _kill(game, true)
		return

	# 강화 팝업의 다중 강화 한 바퀴 — 숫자 슬라이드 · 성공 반짝임 · 실패 X 와 깨짐
	if skill == "enhance":
		await _enhance(game)
		return

	# 주먹 기운 — 등급 일곱을 차례로 끼워 캐릭터 둘레를 가까이 찍는다
	if skill == "fist":
		await _fist(game)
		return
	# 강화 단계별 오로라 — 희귀·태초를 +5~+9 로 (색이 단계마다 바뀐다)
	if skill == "fist:enhance":
		await _fist(game, true)
		return

	# 장비 스킨 — 등급 1~7 세트(갑옷·투구·신발)를 입혀 온몸을 가까이 찍는다
	if skill == "gear" or skill == "gear:close":
		await _gear(game, skill == "gear:close")
		return
	# 맨주먹 — 무기를 벗기고 손을 가까이 (손가락을 말아 쥔 주먹이 제대로 쥐어졌나)
	if skill == "hand":
		await _hand(game)
		return

	# 창은 열어 놓고 한 장만 찍는다 — 움직이는 것이 없다
	if skill == "bag" or skill == "skills":
		await _window(game, skill)
		return

	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	# `rising_kick@90` 처럼 붙이면 그 쪽(도)을 보고 쓴다 — 캐릭터 기준 이펙트는
	# 보는 쪽에 따라 화면에서 모양이 달라서, 한 방향만 찍으면 못 보는 게 있다
	if "@" in skill:
		player["rot"] = deg_to_rad(float(skill.get_slice("@", 1)))
		skill = skill.get_slice("@", 0)
	# `thunder_fall+stun+wide` 처럼 붙이면 그 강화를 단 채로 쓴다 (`@` 는 맨 뒤) → skill-upgrades.md
	if "+" in skill:
		var parts := skill.split("+")
		skill = parts[0]
		player["skill_upgrades"] = {skill: Array(parts.slice(1))}
	game._transport.send(&"learnSkill", {"skill": skill})
	game._transport.send(&"setSkillBar", {"bar": [skill]})
	await process_frame

	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not (skill in me.get("skill_bar", [])):
		print("액션바에 %s 를 못 올렸다 — 내 직업 스킬인가?" % skill)
		quit(1)
		return

	# **한 번 제 속도로 다 돌리고, 두 번째를 찍는다** — 이펙트는 풀(`FxPool`)에서
	# 되감아 쓰므로, 한 번 끝난 것이 제대로 되감기는지가 첫 시전보다 중요하다
	Skills.set_switch("cooldownOff", true)
	game._transport.send(&"skill", {"skill": skill})
	var first_end := Time.get_ticks_msec() + 2600
	while Time.get_ticks_msec() < first_end:
		await process_frame
	Engine.time_scale = SLOW
	game._transport.send(&"skill", {"skill": skill})
	var began := Time.get_ticks_msec()

	var frame := 0
	var taken := 0
	var sheet: Image = null
	while taken < shots.size():
		await process_frame
		frame += 1
		if frame in shots:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("res://../logs/shot_%02d.png" % frame)
			sheet = _add_to_sheet(sheet, img, taken)
			taken += 1
			print("logs/shot_%02d.png  (게임 시간 %.2f초)" % [
				frame, float(Time.get_ticks_msec() - began) * 0.001 * SLOW])
	sheet.resize(int(sheet.get_width() * 0.6), int(sheet.get_height() * 0.6), Image.INTERPOLATE_BILINEAR)
	sheet.save_png("res://../logs/shot_sheet.png")
	print("logs/shot_sheet.png  (가운데를 잘라 3열로 붙인 것)")
	quit(0)


## 화면 가운데(캐릭터 둘레)를 잘라 3열 판에 붙인다
func _add_to_sheet(sheet: Image, img: Image, index: int) -> Image:
	var cell := Vector2i(int(img.get_width() * 0.6), int(img.get_height() * 0.66))
	if sheet == null:
		sheet = Image.create(cell.x * 3, cell.y * 2, false, img.get_format())
	var from := Vector2i((img.get_width() - cell.x) / 2, (img.get_height() - cell.y) / 2)
	sheet.blit_rect(img, Rect2i(from, cell), Vector2i((index % 3) * cell.x, (index / 3) * cell.y))
	return sheet


## 주먹 기운을 등급마다 한 장씩 찍어 4열 판(`logs/shot_sheet.png`)으로 붙인다
## (`npm run shot:godot -- fist`). 게임 각 그대로 가까이 당긴다 — 주먹은 화면에서
## 작아서 게임 거리로는 못 읽는다. **게임의 _process 를 멈추므로** 장착 표시
## (`_wear_weapon`)도 멈춘다 — 등급은 리그에 바로 끼운다
const FIST_DISTANCE := 3.4
const FIST_LOOK := 1.0
## 기운이 한창 피어오르도록 끼우고 나서 기다리는 프레임
const FIST_WAIT := 14


func _fist(game: Node3D, by_enhance := false) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	# 카메라 쪽에서 비스듬히 — 두 주먹이 다 보이게
	player["rot"] = CameraRig.YAW + 0.6
	await process_frame
	await process_frame
	game.set_process(false)
	var rig: Rig = game._player
	var focus: Vector3 = rig.position + Vector3(0, FIST_LOOK, 0)
	var pitch := deg_to_rad(CameraRig.PITCH)
	var away := Vector3(cos(pitch) * sin(CameraRig.YAW), sin(pitch), cos(pitch) * cos(CameraRig.YAW))
	game._camera.position = focus + away * FIST_DISTANCE
	game._camera.look_at(focus, Vector3.UP)
	rig.play("Idle")

	var cell := Vector2i(360, 440)
	var cols := 5 if by_enhance else 4
	var sheet: Image = null
	# 등급 1~7 (+9 — 오로라는 +6 부터라 겹을 다 보려면 강화가 있어야 한다)
	# · 또는 희귀와 태초를 +5~+9 로 (5열)
	var looks: Array = []
	if by_enhance:
		for grade in [3, 7]:
			for enhance in [5, 6, 7, 8, 9]:
				looks.append([grade, enhance])
	else:
		for grade in range(1, 8):
			looks.append([grade, 9])
	for index in looks.size():
		var grade: int = looks[index][0]
		rig.set_weapon(grade, looks[index][1])
		for i in FIST_WAIT:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if sheet == null:
			sheet = Image.create(cell.x * cols, cell.y * 2, false, img.get_format())
		var from := Vector2i((img.get_width() - cell.x) / 2, (img.get_height() - cell.y) / 2)
		sheet.blit_rect(img, Rect2i(from, cell), Vector2i((index % cols) * cell.x, (index / cols) * cell.y))
		print("  %d등급 +%d 찍음" % looks[index])
	sheet.resize(int(sheet.get_width() * 0.7), int(sheet.get_height() * 0.7), Image.INTERPOLATE_BILINEAR)
	sheet.save_png("res://../logs/shot_sheet.png")
	print("logs/shot_sheet.png  (%s)" % ("윗줄 희귀 +5~+9, 아랫줄 태초" if by_enhance else "1~4등급 윗줄, 5~7등급 아랫줄 (+9)"))
	quit(0)


## 맨주먹을 네 각도로 가까이 (`npm run shot:godot -- hand`) — 대기 · 옆 · 달리기 · 평타
func _hand(game: Node3D) -> void:
	await process_frame
	await process_frame
	game.set_process(false)
	var rig: Rig = game._player
	rig.set_weapon(0)
	var focus: Vector3 = rig.position + Vector3(0, 0.8, 0)
	var pitch := deg_to_rad(CameraRig.PITCH)
	var away := Vector3(cos(pitch) * sin(CameraRig.YAW), sin(pitch), cos(pitch) * cos(CameraRig.YAW))
	game._camera.position = focus + away * 1.7
	game._camera.look_at(focus, Vector3.UP)
	var cell := Vector2i(760, 600)
	var sheet: Image = null
	var looks := [["Idle", 0.3], ["Idle", -0.6], ["Run", 0.3], ["Jab", 0.3]]
	for index in looks.size():
		rig.rotation.y = CameraRig.YAW + float(looks[index][1])
		rig.play(str(looks[index][0]), 1.0, 0.0, true, 0.0)
		for i in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if sheet == null:
			sheet = Image.create(cell.x * 4, cell.y, false, img.get_format())
		var from := Vector2i((img.get_width() - cell.x) / 2, (img.get_height() - cell.y) / 2)
		sheet.blit_rect(img, Rect2i(from, cell), Vector2i(index * cell.x, 0))
	sheet.resize(int(sheet.get_width() * 0.4), int(sheet.get_height() * 0.4), Image.INTERPOLATE_BILINEAR)
	sheet.save_png("res://../logs/shot_sheet.png")
	print("logs/shot_sheet.png  (대기 앞 · 대기 옆 · 달리기 · 평타)")
	quit(0)


## 장비 스킨을 등급마다 한 장씩 — 맨몸 + 1~7등급 세트를 4열 판으로 (`npm run shot:godot -- gear`).
## 무기는 벗긴다 (오로라가 몸을 가린다). 게임의 _process 를 멈추므로 장비는 리그에 바로 입힌다
func _gear(game: Node3D, close := false) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["rot"] = CameraRig.YAW + 0.5
	await process_frame
	await process_frame
	game.set_process(false)
	var rig: Rig = game._player
	var focus: Vector3 = rig.position + Vector3(0, 1.3 if close else 0.95, 0)
	var pitch := deg_to_rad(CameraRig.PITCH)
	var away := Vector3(cos(pitch) * sin(CameraRig.YAW), sin(pitch), cos(pitch) * cos(CameraRig.YAW))
	game._camera.position = focus + away * (2.6 if close else 5.2)
	game._camera.look_at(focus, Vector3.UP)
	rig.set_weapon(0)
	rig.play("Idle")
	var cell := Vector2i(300, 520)
	var sheet: Image = null
	for grade in range(0, 8):
		for slot in Armor.SLOTS:
			rig.set_gear(slot, grade)
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if sheet == null:
			sheet = Image.create(cell.x * 4, cell.y * 2, false, img.get_format())
		var from := Vector2i((img.get_width() - cell.x) / 2, (img.get_height() - cell.y) / 2)
		sheet.blit_rect(img, Rect2i(from, cell), Vector2i((grade % 4) * cell.x, (grade / 4) * cell.y))
		print("  %d등급 찍음" % grade)
	sheet.resize(int(sheet.get_width() * 0.75), int(sheet.get_height() * 0.75), Image.INTERPOLATE_BILINEAR)
	sheet.save_png("res://../logs/shot_sheet.png")
	print("logs/shot_sheet.png  (윗줄 맨몸·1~3등급, 아랫줄 4~7등급)")
	quit(0)


## 차원문 창을 열어 찍는다. 한 장은 그냥, 한 장은 **줄을 누른 채**로 —
## 눌린 틀이 눈에 들어오는지는 글로 확인할 수 없다
func _gate(game: Node3D) -> void:
	game._open_gate()
	await process_frame
	await process_frame
	var panel: GatePanel = game._gate_panel
	var list: ScrollContainer = panel._scroll
	var frame := 0
	while frame < 6:
		await process_frame
		frame += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../logs/gate_off.png")
	print("logs/gate_off.png")

	# 세 번째 줄을 누른 채로 둔다
	var box := panel.row(2).get_global_rect()
	var at := Vector2(list.size.x * 0.5, box.get_center().y - list.global_position.y)
	panel._on_list_input(_press_event(at))
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../logs/gate_on.png")
	print("logs/gate_on.png  (셋째 줄을 누른 채)")
	quit(0)


func _press_event(at: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	return event


## 메인 HUD — 왼쪽 위 상태판, 오른쪽 위 메뉴, 아래 가운데 퀵슬롯과 자동사냥 칸.
## **고리가 도는 것을 보려면 여러 장이 필요하다** — 한 장만으로는 멈춘 그림과 같다
func _hud(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	player["exp"] = int(Combat.exp_to_next(LEVEL) * 0.4)
	for skill in Skills.for_job(str(player.get("job", "fighter"))).slice(0, 4):
		game._transport.send(&"learnSkill", {"skill": skill})
	game._transport.send(&"setSkillBar", {"bar": Skills.for_job(str(player.get("job", "fighter"))).slice(0, 4)})
	game._transport.send(&"autoHunt", {"on": true})
	# 체력이 가득이면 막대가 줄어드는 모습을 못 본다 — 3/5 로 깎아 둔다
	await process_frame
	player["hp"] = int(float(player["hp"]) * 0.6)

	var frame := 0
	var taken := 0
	while taken < HUD_SHOTS.size():
		await process_frame
		frame += 1
		if frame in HUD_SHOTS:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("res://../logs/shot_%02d.png" % frame)
			taken += 1
			print("logs/shot_%02d.png  (고리 각 %.2f)" % [frame, game._auto_spin.rotation])
	quit(0)


## 스킬 범위 표시(`SkillFx` 가 아니라 `SkillRange`). **무리 한가운데에서 찍는다** —
## 반경·각이 맞는지는 `skill_test.gd` 가 숫자로 보지만, 그게 화면에서 얼마나
## 덮는지는 찍어야만 안다 (설계에서 범위가 곧 사냥 속도라서 보는 값이다)
func _range(game: Node3D, skill: String) -> void:
	var world = game._transport._world
	game._transport.send(&"travel", {"zone": RANGE_ZONE})
	await process_frame
	var player: Dictionary = world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	player["x"] = RANGE_PACK.x
	player["z"] = RANGE_PACK.z
	game._transport.send(&"learnSkill", {"skill": skill})
	game._transport.send(&"setSkillBar", {"bar": [skill]})
	game._toggle_range()
	for i in 4:
		await process_frame

	Engine.time_scale = SLOW
	game._transport.send(&"skill", {"skill": skill})
	var frame := 0
	var taken := 0
	while taken < RANGE_SHOTS.size():
		await process_frame
		frame += 1
		if frame in RANGE_SHOTS:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../logs/range_%02d.png" % frame)
			taken += 1
			print("logs/range_%02d.png  %s" % [frame, game._range_label.text])
	quit(0)


## 사냥터에서 가장 가까운 몬스터를 한 대에 잡는다. 정면·사거리 판정은 건너뛰고
## 맞히는 자리(`_hit_monster`)부터 탄다 — 처치·보상 이벤트는 게임과 같은 길로 나온다.
## 처치 섬광·피해 숫자와 왼쪽 아래 채팅창(`ChatLog`)을 **게임 시간으로** 찍는다.
## 채팅창에 장비 줄도 보이도록 장비 두 개를 떨어뜨린 것처럼 넣는다 (드롭은 운이라)
func _kill(game: Node3D, crit := false) -> void:
	var world = game._transport._world
	game._transport.send(&"travel", {"zone": RANGE_ZONE})
	await process_frame
	var me: String = game._transport.my_id()
	var player: Dictionary = world._players[me]
	player["x"] = RANGE_PACK.x
	player["z"] = RANGE_PACK.z
	var mob: Dictionary = {}
	var best := INF
	for m in world.snapshot().monsters:
		m.aggro = 0.0
		m.target = ""
		var d: float = Vector2(m.x - player.x, m.z - player.z).length()
		if int(m.hp) > 0 and d < best:
			best = d
			mob = m
	# 몬스터 코앞에서 그쪽을 보고 선다
	var dir: Vector2 = Vector2(player.x - mob.x, player.z - mob.z).normalized()
	player["x"] = mob.x + dir.x * 1.5
	player["z"] = mob.z + dir.y * 1.5
	player["rot"] = atan2(mob.x - player.x, mob.z - player.z)
	if not crit:
		mob["hp"] = 1
	for i in 6:
		await process_frame

	var slow := 0.04 if crit else 0.25
	Engine.time_scale = slow
	var at := [0.05, 0.15, 0.3, 0.5, 0.8, 1.15]
	if crit:
		# 치명타는 판정이 주사위라 이벤트를 직접 넣는다. 튕김이 0.18초 안에 끝나서 앞을 촘촘히
		at = [0.02, 0.05, 0.1, 0.16, 0.3, 0.55]
		game._on_event(&"hit", {
			"target": str(mob.id), "target_kind": "monster", "amount": 128,
			"crit": true, "killed": false, "x": mob.x, "z": mob.z,
		})
	else:
		# 등급 일곱 색이 한 창에 보이게 등급마다 하나씩 (슬롯은 돌려 가며)
		var codes := ["w", "a", "h", "b", "n", "r", "w"]
		for g in range(2, 8):
			var id := "g%d_%s" % [g, codes[g - 1]]
			game._on_event(&"loot", {"gold": 3, "item": {"id": id, "grade": g, "enhance": 0}})
		world._hit_monster(player, mob, 1.0, "")
	var began := Time.get_ticks_msec()
	var taken := 0
	var sheet: Image = null
	while taken < at.size():
		await process_frame
		var t := float(Time.get_ticks_msec() - began) * 0.001 * slow
		if t >= at[taken]:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("res://../logs/shot_kill_%d.png" % taken)
			sheet = _add_to_sheet(sheet, img, taken)
			print("logs/shot_kill_%d.png  (게임 시간 %.2f초)" % [taken, t])
			taken += 1
	sheet.save_png("res://../logs/shot_sheet.png")
	print("logs/shot_sheet.png")
	quit(0)


## 가방창·스킬창. 조각(판·칸·탭·단추)을 갈아 끼웠을 때 테가 뭉개지지 않는지
## 눈으로 본다 — 글자가 상자 밖으로 나오는 것은 수치로 안 잡힌다 (2026-09-19 경험)
func _window(game: Node3D, which: String) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	if which == "skills":
		for skill in Skills.for_job(str(player.get("job", "fighter"))).slice(0, 4):
			game._transport.send(&"learnSkill", {"skill": skill})
		# 강화 칸이 비어 보이지 않도록 낙뢰를 고르고 경험치북을 쥐여 준 뒤 300 을 넣어 둔다
		game._transport.send(&"debugBooks", {})
		player["skill_upgrade_exp"] = {"thunder_fall": {"stun": 300}}
		game._toggle_skills()
		var ids: Array = Skills.for_job(str(player.get("job", "fighter")))
		if "thunder_fall" in ids:
			game._pick_skill(ids.find("thunder_fall"))
	else:
		# 상세 창까지 한 장에 나오도록 등급이 다른 것을 몇 개 넣고 하나를 고른다
		game._transport.send(&"debugGauntlets", {})
		for grade in [5, 3, 1]:
			for slot in ["armor", "ring"]:
				player.bag.append({
					"id": Items.item_id(grade, slot), "grade": grade,
					"enhance": grade % 4, "options": [],
				})
		game._transport.send(&"equip", {"index": 0})
		game._toggle_bag()
		await process_frame
		game._pick_bag("bag", 3)  # 전설 건틀릿 (일반은 위에서 장비 칸으로 갔다)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://../logs/shot_%s.png" % which)
	print("logs/shot_%s.png" % which)
	quit(0)


## 차원문 소용돌이. 문 **밖**에 서야 한다 — 안에 서면 `gate` 이벤트가 창을 열어
## 화면을 덮는다. 문을 화면 가운데에 두려고 카메라 초점만 문 쪽으로 당겨 놓는다
func _portal(game: Node3D) -> void:
	var gate: Dictionary = game._transport.snapshot().get("gate", {})
	var pos: Array = gate.get("position", [0, 0])
	var at := Vector3(float(pos[0]), 0.0, float(pos[1]))
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["x"] = at.x
	player["z"] = at.z + PORTAL_STAND
	await process_frame
	await process_frame

	# **게임의 _process 를 멈춘다** — 안 그러면 카메라가 매 프레임 캐릭터를 다시 쫓아가
	# 문이 화면 구석으로 밀린다. 소용돌이는 제 노드에서 도니까 그대로 움직인다
	game.set_process(false)
	var focus := at + Vector3(0, PORTAL_LOOK, 0)
	var pitch := deg_to_rad(CameraRig.PITCH)
	var away := Vector3(cos(pitch) * sin(CameraRig.YAW), sin(pitch), cos(pitch) * cos(CameraRig.YAW))
	game._camera.position = focus + away * PORTAL_DISTANCE
	game._camera.look_at(focus, Vector3.UP)

	# 돌아가는 소용돌이라 **시간을 늦출 필요가 없다** — 한 바퀴를 고르게 나눠 찍는다
	var frame := 0
	var taken := 0
	while taken < PORTAL_SHOTS.size():
		await process_frame
		frame += 1
		if frame in PORTAL_SHOTS:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("res://../logs/shot_%02d.png" % frame)
			taken += 1
			print("logs/shot_%02d.png" % frame)
	quit(0)


## 다중 강화 한 바퀴를 늦춰서 찍는다 (`npm run shot:godot -- enhance`). +4(성공 50%) 장비 14개를
## 담아 두 결과가 다 나오게 하고, **담은 칸 둘레만 잘라 1.5배로** 여섯 장을 붙인다 —
## 화면 전체로 찍으면 칸이 작아 슬라이드·조각을 못 읽는다
const ENHANCE_TIMES := [0.06, 0.16, 0.3, 0.45, 0.62, 0.85]


func _enhance(game: Node3D) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player.bag.clear()
	for i in 14:
		player.bag.append({"id": Items.item_id(5, "weapon"), "grade": 5, "enhance": 4, "options": []})
	game._toggle_bag()
	await process_frame
	var pop: EnhancePopup = game._enhance
	pop.open({"where": "bag", "index": 0})
	pop.pick_mode("multi")
	pop.set_goal(9)
	pop.pick_all()
	for i in 4:
		await process_frame
	var box: Rect2 = pop.picked_grid.get_global_rect().grow(24)
	# `enhance real` 이면 제 속도로 — 늦춰서만 찍으면 제 속도에서 안 보이는 것을 놓친다
	if not (OS.get_cmdline_user_args().size() > 1 and str(OS.get_cmdline_user_args()[1]) == "real"):
		Engine.time_scale = SLOW
	pop.run_button.pressed.emit()
	# 시계는 **연출 노드 자신의 시간**(`_t`)이다 — 소프트웨어 렌더는 프레임이 느려서 게임 시간이
	# 벽시계 × SLOW 보다 다섯 배쯤 늦게 흐른다 (그렇게 찍었더니 "0.8초" 장이 실제로는 0.16초였다)
	var sheet: Image = null
	var taken := 0
	while taken < ENHANCE_TIMES.size():
		await process_frame
		var clocks: Array = pop.fx_layer.get_children().map(func(n: Node) -> float: return n._t)
		if clocks.is_empty():
			continue
		var at: float = clocks.max()
		if at < float(ENHANCE_TIMES[taken]):
			continue
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image().get_region(Rect2i(box))
		img.resize(int(box.size.x * 1.5), int(box.size.y * 1.5), Image.INTERPOLATE_BILINEAR)
		if sheet == null:
			sheet = Image.create(img.get_width() * 2, img.get_height() * 3, false, img.get_format())
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i((taken % 2) * img.get_width(), (taken / 2) * img.get_height()))
		print("  %d장 — 게임 시간 %.2f초" % [taken + 1, at])
		taken += 1
	sheet.save_png("res://../logs/shot_enhance.png")
	print("logs/shot_enhance.png  (2열 × 3줄, 시간 순)")
	quit(0)
