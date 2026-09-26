class_name LoadingScreen
extends CanvasLayer

## 시작 화면에서 모드를 고른 뒤 **게임이 다 지어질 때까지 덮는 막** (2026-09-26 요청:
## "로딩 화면 만들어서 보여주다가 로딩 끝나면 페이드 아웃으로 게임 스르륵 보이게").
##
## 1. 막을 **한 번 그린 뒤에** 장면을 넘긴다 — `game.gd` 의 `_ready` 가 한 프레임 안에서
##    다 짓느라 그동안 화면이 굳는다. 먼저 안 그리면 누른 시작 화면이 멈춘 채로 보인다
## 2. 새 장면의 `_ready` 가 끝나도 첫 몇 프레임은 셰이더를 굽느라 끊긴다 — 프레임이
##    가라앉을 때까지(`SETTLE_FRAMES` 연속 `SETTLE_DELTA` 이하) 더 덮어 둔다
## 3. `FADE_SEC` 동안 투명해지며 게임이 드러나고, 다 걷히면 스스로 지운다
##
## 웹 빌드는 스레드를 껐으므로(`export_presets.cfg`) 백그라운드 로딩은 못 쓴다. 그래서
## 진행률 대신 흐르는 띠를 둔다. 루트에 달아서 장면을 바꿔도 남는다.
## 색은 `start_screen.gd` 와 같다 (ui-art-style.md 의 판·금테·상아 글자).
##
## → docs/features/play-mode.md

signal finished

const BG := Color("#0e100f")
const GOLD := Color("#b9a46c")
const GOLD_HI := Color("#e3d092")
const DIM := Color("#948c7a")

const FADE_SEC := 0.8
const SETTLE_DELTA := 1.0 / 20.0
const SETTLE_FRAMES := 4
## 끊김이 안 가라앉아도(느린 기기) 이만큼 지나면 걷는다
const SETTLE_MAX_MS := 4000
const BAR_W := 320.0
const GLEAM_W := 90.0

var _root: Control
var _gleam: ColorRect
var _t := 0.0


func _init(note: String = "") -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 덮는 동안에는 뒤의 단추·게임이 눌리지 않게 막는다
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	var path := "res://assets/fonts/NotoSansKR-subset.ttf"
	_root.theme = Theme.new()
	if ResourceLoader.exists(path):
		_root.theme.default_font = load(path)
	add_child(_root)

	var back := ColorRect.new()
	back.color = BG
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(column)

	var title := Label.new()
	title.text = "불러오는 중"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", GOLD_HI)
	column.add_child(title)

	# 얇은 금줄 위로 밝은 조각이 흐른다 — 진행률이 아니라 "멈추지 않았다" 는 표시
	var track := ColorRect.new()
	track.color = GOLD.darkened(0.55)
	track.custom_minimum_size = Vector2(BAR_W, 2)
	track.clip_contents = true
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(track)
	_gleam = ColorRect.new()
	_gleam.color = GOLD_HI
	_gleam.size = Vector2(GLEAM_W, 2)
	_gleam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_gleam)

	if note != "":
		var sub := Label.new()
		sub.text = note
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 20)
		sub.add_theme_color_override("font_color", DIM)
		column.add_child(sub)


func _process(delta: float) -> void:
	_t = fmod(_t + delta * 0.8, 1.0)
	_gleam.position.x = lerpf(-GLEAM_W, BAR_W, _t)


## 막을 그린 다음 `path` 로 장면을 넘기고, 새 장면이 자리 잡으면 걷힌다
func load_scene(path: String) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	# 막이 화면에 한 번 나간 뒤에 무거운 일을 시작한다 — process_frame 두 번 사이에 한 번
	# 그려진다. `RenderingServer.frame_post_draw` 는 헤드리스(테스트)에서 오지 않아 안 쓴다
	await tree.process_frame
	await tree.process_frame
	tree.change_scene_to_file(path)
	while tree.current_scene == null or tree.current_scene == old \
			or not tree.current_scene.is_node_ready():
		await tree.process_frame
	await _settle(tree)
	await fade_out()


## 프레임이 `SETTLE_FRAMES` 번 연속으로 빨리 돌 때까지 기다린다 (최대 `SETTLE_MAX_MS`)
func _settle(tree: SceneTree) -> void:
	var start := Time.get_ticks_msec()
	var calm := 0
	while calm < SETTLE_FRAMES and Time.get_ticks_msec() - start < SETTLE_MAX_MS:
		await tree.process_frame
		calm = calm + 1 if get_process_delta_time() <= SETTLE_DELTA else 0


## 서서히 투명해진다. 걷히기 시작하면 뒤의 게임을 바로 누를 수 있다
func fade_out() -> void:
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_root, "modulate:a", 0.0, FADE_SEC)
	await tween.finished
	finished.emit()
	queue_free()
