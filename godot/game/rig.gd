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
}

var _anim: AnimationPlayer
var _clips: Array = []
var _playing := ""


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


## 클립이 없으면 아무것도 하지 않는다 (모델마다 가진 클립이 다르다)
func play(clip: String, speed: float = 1.0, from: float = 0.0) -> void:
	if _anim == null or not _clips.has(clip):
		return
	if _playing == clip and _anim.is_playing() and is_equal_approx(_anim.speed_scale, speed):
		return
	_playing = clip
	_anim.speed_scale = speed
	_anim.play(clip)
	if from > 0.0:
		_anim.seek(from, true)


func has_clip(clip: String) -> bool:
	return _clips.has(clip)


func clips() -> Array:
	return _clips
