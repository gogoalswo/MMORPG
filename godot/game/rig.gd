class_name Rig
extends Node3D

## .glb 모델 하나를 씌우고 클립을 트는 껍데기.
##
## **파일이 없으면 만들지 않는다**(`create` 가 null 을 준다). 화면은 그때 기둥을
## 대신 그린다 — `npm run sync:godot` 을 안 돌린 사람도 게임은 돌아가야 한다.
## 웹 클라이언트가 모델 없는 look 에 절차적 리그를 쓰는 것과 같은 자리다.
##
## 모델은 높이 1 로 정규화돼 나온다. 얼마나 키울지는 **데이터가 정한다** —
## 사람은 1.8m, 짐승은 `monsters.json` 의 heights x kind.scale.

const DIR := "res://assets/models/"
const HUMAN_HEIGHT := 1.8

## 모델 파일이 있는 look 만 여기 있다. 나머지는 기둥이다
const FILES := {
	"varco_fighter": "varco_fighter.glb",
	"varco_ogre1": "varco_ogre1.glb",
	"varco_ogre2": "varco_ogre2.glb",
	"varco_ogre3": "varco_ogre3.glb",
	"varco_ogre4": "varco_ogre4.glb",
	"varco_ogre5": "varco_ogre5.glb",
}

var _anim: AnimationPlayer
var _clips: Array = []
var _playing := ""
## 틀라고 한 배속. 멈춰 있는 동안(`freeze`)에도 기억해 두었다가 풀 때 되돌린다
var _speed := 1.0
## 히트스톱이 남은 시간(초)
var _freeze := 0.0


## 없으면 null. 부르는 쪽이 기둥으로 대신한다
static func create(look: String, target_height: float) -> Rig:
	if not FILES.has(look):
		return null
	var path: String = DIR + FILES[look]
	if not ResourceLoader.exists(path):
		return null
	var packed: PackedScene = load(path)
	if packed == null:
		return null

	var rig := Rig.new()
	var model := packed.instantiate()
	rig.add_child(model)

	for child in model.find_children("*", "", true):
		if child is AnimationPlayer:
			rig._anim = child
			rig._clips = child.get_animation_list()
			break

	var height := rig._measure(model)
	if height > 0.0:
		model.scale = Vector3.ONE * (target_height / height)
	return rig


func _measure(model: Node) -> float:
	var box := AABB()
	var first := true
	for child in model.find_children("*", "", true):
		if child is MeshInstance3D:
			var mesh_box: AABB = child.get_aabb()
			box = mesh_box if first else box.merge(mesh_box)
			first = false
	return box.size.y


## 클립이 없으면 아무것도 하지 않는다 (모델마다 가진 클립이 다르다).
## `blend` 는 앞 자세에서 섞어 넘어가는 시간(초) — 음수면 뚝 바꾼다
func play(clip: String, speed: float = 1.0, from: float = 0.0, blend: float = -1.0) -> void:
	if _anim == null or not _clips.has(clip):
		return
	if _playing == clip and _anim.is_playing() and is_equal_approx(_speed, speed):
		return
	_start(clip, speed, from, blend)


## 같은 클립이 돌고 있어도 처음부터 다시 튼다 — 평타는 칠 때마다 주먹이 다시 나가야 한다
func restart(clip: String, speed: float = 1.0, blend: float = -1.0) -> void:
	if _anim == null or not _clips.has(clip):
		return
	_start(clip, speed, 0.0, blend)


func _start(clip: String, speed: float, from: float, blend: float) -> void:
	_playing = clip
	_speed = speed
	# 멈춰 있는 동안 클립이 바뀌어도 멈춘 채로 둔다 — 풀 때 `_speed` 로 돌아간다
	_anim.speed_scale = 0.0 if _freeze > 0.0 else speed
	# 같은 클립을 되감을 때는 섞을 앞 자세가 자기 자신이라 멈춰야 되감긴다
	if _anim.current_animation == clip:
		_anim.stop(true)
	_anim.play(clip, blend)
	if from > 0.0:
		_anim.seek(from, true)


## 클립 길이(초). 없으면 0
func clip_length(clip: String) -> float:
	if _anim == null or not _clips.has(clip):
		return 0.0
	return _anim.get_animation(clip).length


## 히트스톱 — 맞는 순간 동작을 잠깐 세운다. **애니메이션만 멈춘다.**
## `Engine.time_scale` 을 쓰면 판정(`World`) 시간까지 같이 멈춰서 공격 간격이
## 늘어난다. 겹치면 긴 쪽이 남는다 (더하면 연타에 멈춘 채로 굳는다)
func freeze(seconds: float) -> void:
	if _anim == null or seconds <= 0.0:
		return
	_freeze = maxf(_freeze, seconds)
	_anim.speed_scale = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if _freeze <= 0.0:
		set_process(false)
		return
	_freeze -= delta
	if _freeze <= 0.0:
		_freeze = 0.0
		_anim.speed_scale = _speed
		set_process(false)


func has_clip(clip: String) -> bool:
	return _clips.has(clip)


func clips() -> Array:
	return _clips
