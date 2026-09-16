extends Node3D

## 빌드 파이프라인 확인용 임시 화면.
## APK 가 폰에서 실제로 뜨는지, 3D 가 그려지는지만 본다.
## 게임 내용이 들어오면 통째로 버린다.
##
## 글자는 ASCII 만 쓴다 — 고도 기본 폰트에 한글 글리프가 없어서
## 한글을 넣으면 폰에서 네모로 나온다. 폰트는 나중에 따로 붙인다.

@onready var _label: Label = $Ui/Label
@onready var _cube: MeshInstance3D = $Cube

func _ready() -> void:
	_label.text = "MMORPG / Godot %s\n%s\n%dx%d" % [
		Engine.get_version_info().string,
		OS.get_name(),
		get_viewport().size.x,
		get_viewport().size.y,
	]

func _process(delta: float) -> void:
	_cube.rotate_y(delta)
