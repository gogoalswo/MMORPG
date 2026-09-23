class_name DungeonPanel
extends GatePanel

## 던전 창 — 가방 옆 "던전" 단추로 연다. **두 겹이다**:
##
##   종류 셋 ─(열린 종류를 누르면)─ 그 종류의 단계 목록 ─(단계를 누르면)─ travel
##
## 틀·줄·누름·끌기는 차원문 창(`GatePanel`)을 그대로 물려받는다 — 줄을 다는 것만
## 다르다(`_fill`). 닫힌 종류(`open: false`)는 흐리게 막혀 눌리지 않는다.
## 표는 `zones.json` 의 `dungeons` (shared 의 dungeons.ts) → docs/features/dungeons.md

const TYPE_KEY := "type:"
const BACK_KEY := "back"
## 닫힌 종류에 붙는 말
const LOCKED := "준비 중"
## 차원문 창(520)보다 넓다 — "20단계 · Lv.199 종말의 사자" 가 한 줄에 들어가야 한다
const DUNGEON_WIDTH := 680.0

## 지금 펼친 종류 id. 비었으면 종류 셋을 보여 준다
var _type := ""
var _here := ""


static func make(frame_box := Callable(), icon := Callable()) -> DungeonPanel:
	var panel := DungeonPanel.new()
	panel._frame_box = frame_box
	panel._icon = icon
	panel._build()
	panel.name = "DungeonPanel"
	panel.offset_left = -DUNGEON_WIDTH * 0.5
	panel.offset_right = DUNGEON_WIDTH * 0.5
	panel._title.text = "던전"
	return panel


## 열 때는 늘 종류 셋부터 — 지난번에 펼친 단계 목록이 남아 있으면 어디인지 헷갈린다
func open(current_zone: String) -> void:
	_type = ""
	_here = current_zone
	super.open(current_zone)


func _fill(_current_zone: String) -> void:
	_clear_rows()
	if _type == "":
		_title.text = "던전"
		for type in GameData.dungeons():
			var on := bool(type.get("open", false))
			var text := str(type.get("name", "")) if on else "%s  ·  %s" % [type.get("name", ""), LOCKED]
			_add_row(text, TYPE_KEY + str(type.get("id", "")), not on, _go_icon if on else _here_icon)
		return
	var picked := _find(_type)
	_title.text = str(picked.get("name", "던전"))
	_add_row("뒤로", BACK_KEY, false, _here_icon)
	for s in picked.get("stages", []):
		var zone_id := str(s.get("zone", ""))
		var boss := GameData.monster_kind(str(s.get("boss", "")))
		var text := "%d단계  ·  Lv.%d %s" % [int(s.get("stage", 0)), int(s.get("level", 0)), boss.get("name", "")]
		# 지금 들어와 있는 단계는 막는다 — 같은 존으로의 travel 은 World 가 버린다
		var here := zone_id == _here
		_add_row(text, zone_id, here, _here_icon if here else _go_icon)


func _find(type_id: String) -> Dictionary:
	for type in GameData.dungeons():
		if str(type.get("id", "")) == type_id:
			return type
	return {}


## 종류를 누르면 단계 목록으로, "뒤로" 면 종류 셋으로, 단계면 그 존으로 간다
func _on_pick(key: String) -> void:
	if key.begins_with(TYPE_KEY) or key == BACK_KEY:
		_type = key.substr(TYPE_KEY.length()) if key != BACK_KEY else ""
		_fill(_here)
		_scroll.scroll_vertical = 0
		return
	super._on_pick(key)
