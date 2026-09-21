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


func _init() -> void:
	Save.clear()
	root.call_deferred("add_child", load("res://main.tscn").instantiate())
	_run.call_deferred()


func _run() -> void:
	var skill := "thunder_fall"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and str(args[0]) != "":
		skill = str(args[0])

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

	# 창은 열어 놓고 한 장만 찍는다 — 움직이는 것이 없다
	if skill == "bag" or skill == "skills":
		await _window(game, skill)
		return

	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	game._transport.send(&"learnSkill", {"skill": skill})
	game._transport.send(&"setSkillBar", {"bar": [skill]})
	await process_frame

	var me: Dictionary = game._transport.snapshot().get("players", {}).get(game._transport.my_id(), {})
	if not (skill in me.get("skill_bar", [])):
		print("액션바에 %s 를 못 올렸다 — 내 직업 스킬인가?" % skill)
		quit(1)
		return

	Engine.time_scale = SLOW
	game._transport.send(&"skill", {"skill": skill})

	var frame := 0
	var taken := 0
	while taken < SHOTS.size():
		await process_frame
		frame += 1
		if frame in SHOTS:
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("res://../logs/shot_%02d.png" % frame)
			taken += 1
			print("logs/shot_%02d.png  (%.2f초쯤)" % [frame, float(frame) * 0.15 * SLOW])
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


## 가방창·스킬창. 조각(판·칸·탭·단추)을 갈아 끼웠을 때 테가 뭉개지지 않는지
## 눈으로 본다 — 글자가 상자 밖으로 나오는 것은 수치로 안 잡힌다 (2026-09-19 경험)
func _window(game: Node3D, which: String) -> void:
	var player: Dictionary = game._transport._world._players[game._transport.my_id()]
	player["level"] = LEVEL
	player["skill_points"] = 99
	if which == "skills":
		for skill in Skills.for_job(str(player.get("job", "fighter"))).slice(0, 4):
			game._transport.send(&"learnSkill", {"skill": skill})
		game._toggle_skills()
	else:
		game._toggle_bag()
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
