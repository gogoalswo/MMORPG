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
