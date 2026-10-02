class_name Sandbag
extends RefCounted

## 샌드백 랭킹전 규칙 — 표는 shared 의 `sandbag.ts` 가 만들어 `zones.json` 의 `sandbag` 으로 내보낸다.
## 판(카운트 → 재는 시간)은 `World`, 기록·정산·지급은 `Ledger`, 순위는 로컬 `World` / 서버 `LedgerServer`
## → docs/features/sandbag.md


static func table() -> Dictionary:
	return GameData.zones().get("sandbag", {})


static func zone() -> String:
	return str(table().get("zone", "sandbag"))


static func countdown_ms() -> int:
	return int(float(table().get("countdown", 3)) * 1000.0)


static func play_ms() -> int:
	return int(float(table().get("seconds", 15)) * 1000.0)


## 이번 주 순위를 다시 세는 간격 — 1분 (2026-10-02 요청). 서버는 이만큼 지나야 다시 줄 세우고, 창은 열려 있는 동안 이만큼마다 다시 묻는다
static func rank_refresh_ms() -> int:
	return int(float(table().get("rankRefresh", 60)) * 1000.0)


## 창에 적는 갱신 간격 — "1분" · "30초"
static func rank_refresh_label() -> String:
	var seconds := rank_refresh_ms() / 1000
	return "%d분" % (seconds / 60) if seconds % 60 == 0 else "%d초" % seconds


## 주 번호 — 월요일 0시(한국 시각)에 하나 오른다. `sandbag.ts` 의 `sandbagWeek` 와 같은 식이다
static func week(unix_seconds: float) -> int:
	var t := table()
	return floori((unix_seconds + float(t.get("weekShift", 0))) / float(t.get("weekSeconds", 604800)))


## 그 주가 끝나는 시각(유닉스 초) — 입장 창의 "정산까지 N일" 에 쓴다
static func week_end(week_no: int) -> float:
	var t := table()
	return float(week_no + 1) * float(t.get("weekSeconds", 604800)) - float(t.get("weekShift", 0))


## 날 번호 — **한국 0시**에 하나 오른다. `sandbag.ts` 의 `sandbagDay` 와 같은 식이다 (날짜별 기록)
static func day(unix_seconds: float) -> int:
	var t := table()
	return floori((unix_seconds + float(t.get("dayShift", 32400))) / float(t.get("daySeconds", 86400)))


## 날짜별 기록을 며칠 두나 (오늘 포함) — 7
static func history_days() -> int:
	return int(table().get("historyDays", 7))


## 날짜별 기록 `[{day, best}]` 에 이 판을 얹는다 — 그날 최고보다 크면 갈아 끼우고, `today` 에서
## 보관 일수를 넘긴 날은 버린다. 새 날이 앞(최근 → 옛날)
static func add_day(days: Array, today: int, damage: int) -> Array:
	var best := damage
	for row in days:
		if int(row.get("day", -1)) == today:
			best = maxi(best, int(row.get("best", 0)))
	var out: Array = [{"day": today, "best": best}]
	for row in days:
		var d := int(row.get("day", -1))
		if d != today and d > today - history_days() and d < today:
			out.append({"day": d, "best": int(row.get("best", 0))})
	out.sort_custom(func(a, b): return int(a.day) > int(b.day))
	return out


## 날 번호 → "10월 2일 (목)". 날 번호 × 하루 = 그날 한국 날짜의 UTC 0시라 UTC 로 읽으면 그 날짜다
static func day_label(day_no: int) -> String:
	var date := Time.get_date_dict_from_unix_time(day_no * int(table().get("daySeconds", 86400)))
	return "%d월 %d일 (%s)" % [int(date.month), int(date.day), "일월화수목금토"[int(date.weekday)]]


## 순위 → 옐로우 크리스탈 개수. 순위가 없으면(0) 0
static func reward(rank: int) -> int:
	if rank < 1:
		return 0
	for row in table().get("rewards", []):
		var to: Variant = row.get("to")
		if rank >= int(row.from) and (to == null or rank <= int(to)):
			return int(row.yellowCrystals)
	return 0


## 보상 표 줄마다 글자 — "1위" · "4~10위" · "101위~"
static func reward_label(row: Dictionary) -> String:
	var to: Variant = row.get("to")
	if to == null:
		return "%d위~" % int(row.from)
	if int(to) == int(row.from):
		return "%d위" % int(row.from)
	return "%d~%d위" % [int(row.from), int(to)]
