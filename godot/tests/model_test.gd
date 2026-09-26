extends SceneTree

## 모델이 제대로 붙었는지, 없을 때 기둥으로 돌아가는지 본다.
##
##   godot --headless --path godot --script tests/model_test.gd

var _failed := 0


func _init() -> void:
	# 남아 있는 저장이 있으면 엉뚱한 존에서 시작한다 (LocalTransport 가 이어서 연다)
	Save.clear()
	_case_fighter()
	_case_ogre()
	_case_texture_size()
	_case_texture_lossy()
	_case_missing()
	_case_height_table()
	_case_every_kind()
	_case_npcs()
	_run_scene.call_deferred()


func _fail(text: String) -> void:
	print("  실패 " + text)
	_failed += 1


## 씌운 뒤 실제 높이 (모델은 1 로 정규화돼 오므로 배율이 곧 키다)
func _height(rig: Rig) -> float:
	var model: Node3D = rig.get_child(0)
	var box := AABB()
	var first := true
	for child in model.find_children("*", "", true):
		if child is MeshInstance3D:
			box = child.get_aabb() if first else box.merge(child.get_aabb())
			first = false
	return box.size.y * model.scale.y


func _case_fighter() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		_fail("격투가 모델을 못 만들었다 — npm run sync:godot 을 돌렸나")
		return
	for clip in ["Idle", "Run", "Attack", "Death"]:
		if not rig.has_clip(clip):
			_fail("격투가에 %s 클립이 없다" % clip)
	# 블렌더로 지은 평타·스킬 동작 (scripts/blender/fighter_moves.py → add-clips.mjs).
	# 트랙 수가 대기와 같아야 한다 — 한 동작만 가진 트랙은 대기로 돌아가도 아무도
	# 되돌리지 않아 그 자세로 굳는다
	var idle_tracks: int = rig._anim.get_animation("Idle").get_track_count()
	var moves: Array = load("res://game/game.gd").SWING_CLIPS.duplicate()
	moves.append_array(load("res://game/game.gd").SKILL_CLIPS.values())
	moves.append(load("res://game/game.gd").HIT_CLIP)
	for clip in moves:
		if not rig.has_clip(clip):
			_fail("격투가에 %s 동작이 없다 — add-clips.mjs 를 돌렸나" % clip)
			continue
		var anim: Animation = rig._anim.get_animation(clip)
		# 천붕각은 5.4m 를 뛰어올라 1.45초다
		if anim.length < 0.4 or anim.length > 1.6:
			_fail("%s 가 %.2f초 — 평타·스킬 동작은 1초 남짓이어야 한다" % [clip, anim.length])
		if anim.get_track_count() != idle_tracks:
			_fail("%s 트랙 %d 개, 대기는 %d 개" % [clip, anim.get_track_count(), idle_tracks])
	var h := _height(rig)
	if absf(h - 1.8) > 0.02:
		_fail("격투가 키가 1.8 이어야 하는데 %.2f" % h)
	else:
		print("  격투가: 키 %.2f m, 클립 %s" % [h, rig.clips()])


func _case_ogre() -> void:
	# 초원 들늑대는 scale 1.01 -> 2.2 x 1.01 = 2.22 m
	var target := GameData.beast_height("varco_ogre1", 1.01)
	var rig := Rig.create("varco_ogre1", target)
	if rig == null:
		_fail("오우거 모델을 못 만들었다")
		return
	var h := _height(rig)
	if absf(h - target) > 0.02:
		_fail("오우거 키가 %.2f 이어야 하는데 %.2f" % [target, h])
	else:
		print("  오우거: 키 %.2f m, 클립 %s" % [h, rig.clips()])


## 텍스처가 실제로 줄어 있나. 안 줄면 pck 가 13MB 로 돌아간다
## (scripts/shrink-glb-textures.mjs — npm run sync:godot 이 돌린다)
func _case_texture_size() -> void:
	var rig := Rig.create("varco_fighter", Rig.HUMAN_HEIGHT)
	if rig == null:
		return
	var biggest := 0
	for child in rig.get_child(0).find_children("*", "MeshInstance3D", true):
		var mesh: Mesh = child.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			if mat is BaseMaterial3D and mat.albedo_texture != null:
				biggest = maxi(biggest, maxi(mat.albedo_texture.get_width(), mat.albedo_texture.get_height()))
	if biggest == 0:
		_fail("텍스처를 못 찾았다")
	elif biggest > 512:
		_fail("텍스처가 %dpx 다 — 줄이기가 안 돌았다" % biggest)
	else:
		print("  텍스처 가장 큰 변 %dpx" % biggest)


## 모델 텍스처는 손실, UI 아이콘은 무손실로 굽나. 기본값(무손실)으로 돌아가면
## 90KB JPG 가 675KB 가 돼 pck 가 49MB 로 돌아간다 (2026-09-26)
func _case_texture_lossy() -> void:
	var defaults: Dictionary = ProjectSettings.get_setting("importer_defaults/texture", {})
	if int(defaults.get("compress/mode", 0)) != 1:
		_fail("project.godot 의 텍스처 기본값이 손실(compress/mode=1)이 아니다 — pck 가 49MB 로 돌아간다")
		return
	var cfg := ConfigFile.new()
	if cfg.load("res://assets/icons/weapon.png.import") != OK:
		return
	if int(cfg.get_value("params", "compress/mode", -1)) != 0:
		_fail("아이콘이 무손실이 아니다 — sync-godot-assets.mjs 의 LOSSLESS_IMPORT 가 안 써졌다")
	else:
		print("  텍스처: 모델은 손실 %.1f, 아이콘은 무손실" % float(defaults.get("compress/lossy_quality", 0.0)))


func _case_missing() -> void:
	# 파일이 없는 look 은 null 을 준다 — 화면이 기둥으로 대신한다.
	# 지금은 몬스터가 전부 오우거라 해당하는 게 없다. 옛 짐승 이름(trex)으로 본다
	if Rig.create("trex", 2.0) != null:
		_fail("파일도 없는 trex 로 리그가 만들어졌다")
	if Rig.create("없는이름", 1.0) != null:
		_fail("모르는 이름으로 리그가 만들어졌다")


func _case_height_table() -> void:
	# 키는 shared 에서 내보낸 표가 정한다
	var got := GameData.beast_height("varco_ogre1", 1.0)
	if absf(got - 2.2) > 1e-9:
		_fail("오우거 기본 키가 2.2 여야 하는데 %.2f" % got)
	var unknown := GameData.beast_height("없는짐승", 2.0)
	if absf(unknown - 1.8) > 1e-9:
		_fail("모르는 짐승은 기본 0.9 x 2.0 = 1.8 이어야 하는데 %.2f" % unknown)


## 사냥터 20곳의 잡몹·보스가 전부 모델로 선다 — 기둥으로 떨어지는 종이 없다
func _case_every_kind() -> void:
	var kinds: Dictionary = GameData.load_table("monsters").get("kinds", {})
	var looks := {}
	for id in kinds:
		var look := str(kinds[id].get("look", ""))
		looks[look] = int(looks.get(look, 0)) + 1
		if Rig.create(look, 2.0) == null:
			_fail("%s(%s) 의 look %s 가 모델로 안 만들어진다" % [id, kinds[id].get("name", ""), look])
	print("  몬스터 %d종 → 모델 %s" % [kinds.size(), looks])


## 마을 NPC 는 전부 제 모델이 있고 대기 동작으로 선다 — 기둥이 남으면 안 된다
func _case_npcs() -> void:
	var looks := []
	for npc in GameData.zone("village").get("npcs", []):
		var look := str(npc.get("look", ""))
		var rig := Rig.create(look, Rig.HUMAN_HEIGHT)
		if rig == null:
			_fail("NPC %s 의 look '%s' 가 모델로 안 만들어진다" % [npc.get("name", ""), look])
			continue
		if not rig.has_clip("Idle"):
			_fail("NPC %s 모델에 Idle 클립이 없다 %s" % [npc.get("name", ""), rig.clips()])
		if absf(_height(rig) - Rig.HUMAN_HEIGHT) > 0.02:
			_fail("NPC %s 키가 %.2f" % [npc.get("name", ""), _height(rig)])
		looks.append(look)
		rig.free()
	print("  NPC %d명 → 모델 %s" % [looks.size(), looks])


## 이벤트가 오면 그 동작을 틀고, 끝나면 대기로 돌아가는지 본다
func _check_moves(game: Node3D) -> void:
	var rig: Rig = game._player
	var me: String = game._transport.my_id()
	var cases := [
		[&"swing", {"id": me, "root_ms": 400}, "Cross"],
		[&"swing", {"id": me, "root_ms": 400}, "Jab"],
		[&"skill", {"id": me, "skill": "frost_pillar", "root_ms": 400}, "FrostStomp"],
		[&"skill", {"id": me, "skill": "thunder_fall", "root_ms": 400}, "Thunder"],
	]
	for c in cases:
		game._on_event(c[0], c[1])
		await process_frame
		await process_frame
		if rig._playing != c[2]:
			_fail("%s(%s) 뒤에 %s 가 아니라 %s 를 튼다" % [c[0], c[1].get("skill", ""), c[2], rig._playing])
	# 끝나면 대기로 돌아간다
	game._move_until = 0
	await process_frame
	await process_frame
	if rig._playing != "Idle":
		_fail("동작이 끝났는데 대기가 아니라 %s" % rig._playing)
	else:
		print("  동작: 평타 잽·스트레이트 번갈아, 스킬마다 제 동작, 끝나면 대기")

	# 맞으면 움찔한다 — 서 있을 때는 튼다
	var hit := {"target": me, "target_kind": "player", "amount": 5, "killed": false}
	game._on_event(&"hit", hit)
	await process_frame
	await process_frame
	if rig._playing != "Hit":
		_fail("서 있다 맞았는데 %s 를 튼다 (Hit 이어야 한다)" % rig._playing)
	# 스킬 동작은 맞아도 끊지 않는다
	game._on_event(&"skill", {"id": me, "skill": "frost_pillar", "root_ms": 400})
	await process_frame
	game._on_event(&"hit", hit)
	await process_frame
	await process_frame
	if rig._playing != "FrostStomp":
		_fail("스킬 동작 중에 맞았더니 %s 로 끊겼다" % rig._playing)
	# 평타 중에도 안 끊는다 — 막 냈을 때도, 한참 지나서도
	game._on_event(&"swing", {"id": me, "root_ms": 400})
	await process_frame
	var swing_clip: String = rig._playing
	for i in 2:
		game._on_event(&"hit", hit)
		for f in 6:
			await process_frame
		if rig._playing != swing_clip:
			_fail("평타(%s) 중에 맞았더니 %s 로 끊겼다" % [swing_clip, rig._playing])
	# 거꾸로 — 맞는 동작 중에 공격하면 공격 동작이 이긴다 (평타도 스킬도)
	for attack in [[&"swing", {"id": me, "root_ms": 400}], [&"skill", {"id": me, "skill": "thunder_fall", "root_ms": 400}]]:
		game._move_until = 0
		await process_frame
		game._on_event(&"hit", hit)
		await process_frame
		await process_frame
		if rig._playing != "Hit":
			_fail("서 있다 맞았는데 %s" % rig._playing)
		game._on_event(attack[0], attack[1])
		await process_frame
		await process_frame
		if rig._playing == "Hit":
			_fail("맞는 동작 중에 %s 를 했는데 공격 동작이 안 나왔다" % attack[0])
	if _failed == 0:
		print("  맞음: 서 있으면 움찔 · 공격(평타·스킬) 중엔 안 끊음 · 맞는 중에 공격하면 공격이 이김")


## 실제 화면에서 초원까지 걸어가 몬스터가 모델로 서 있는지 본다
func _run_scene() -> void:
	root.add_child(load("res://main.tscn").instantiate())
	await process_frame
	var game: Node3D = root.get_node("Game")
	await process_frame

	if not game._player is Rig:
		_fail("캐릭터가 모델이 아니다")

	# 사냥터를 골라 옮긴다
	game._transport.send(&"travel", {"zone": "meadow"})
	for i in 5:
		await process_frame

	if game._shown_zone != "meadow":
		_fail("차원문을 밟았는데 화면이 %s 그대로다" % game._shown_zone)
	else:
		var rigs := 0
		var posts := 0
		for id in game._mob_nodes:
			if game._mob_nodes[id] is Rig:
				rigs += 1
			else:
				posts += 1
		print("  초원: 모델 %d마리, 기둥 %d마리" % [rigs, posts])
		if rigs < 80:
			_fail("모델로 선 몬스터가 %d마리뿐이다" % rigs)
		if posts > 0:
			_fail("기둥으로 선 몬스터가 %d마리 있다 — 보스까지 모델이어야 한다" % posts)

	await _check_moves(game)

	if _failed == 0:
		print("모델: 전부 통과")
		quit(0)
	else:
		print("모델: %d개 실패" % _failed)
		quit(1)
