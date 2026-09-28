class_name Names
extends RefCounted

## 캐릭터 이름 — 규칙 한 벌 (docs/features/play-mode.md "이름"). 시작 화면이 입력을 거르고,
## 서버(`LedgerServer._hello`)가 **같은 함수로 다시 거른다** — 기기가 보낸 이름을 그대로 믿지 않는다.
##
## 한글(완성형)·영문·숫자만, **2~8자**. 띄어쓰기·기호는 안 된다 — 채팅·랭킹 한 칸에 들어가고
## 남을 흉내 내는 꾸밈(`[운영자]`)을 막는다. 같은 이름은 막지 않는다 (2026-09-28 에는 요청에 없었다).
##
## 아무것도 안 넣고 들어가면 `random` 이 짓는다 — "푸른늑대37" 처럼 꾸밈말 + 이름 + 두 자리 숫자.

const MIN_LEN := 2
const MAX_LEN := 8

const _ADJ := ["푸른", "붉은", "검은", "흰", "용맹한", "고요한", "날랜", "빛나는", "거친", "은빛", "황금", "작은"]
const _NOUN := ["늑대", "매", "곰", "여우", "사자", "검객", "궁수", "방랑자", "기사", "까마귀", "호랑이", "용"]


## 앞뒤 공백만 자른다 — 걸러 내는 것은 `why_invalid` 가 한다(몰래 고쳐 주지 않는다)
static func clean(raw: String) -> String:
	return raw.strip_edges()


## 안 되는 까닭 — 되면 빈 글자
static func why_invalid(name: String) -> String:
	if name.length() < MIN_LEN or name.length() > MAX_LEN:
		return "이름은 %d~%d자입니다" % [MIN_LEN, MAX_LEN]
	for i in name.length():
		var code := name.unicode_at(i)
		var hangul := code >= 0xAC00 and code <= 0xD7A3
		var latin := (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A)
		var digit := code >= 0x30 and code <= 0x39
		if not (hangul or latin or digit):
			return "한글·영문·숫자만 쓸 수 있습니다"
	return ""


static func valid(name: String) -> bool:
	return why_invalid(name).is_empty()


## 무작위 이름. 길면(꾸밈말이 세 글자일 때) 숫자를 줄여 8자를 넘지 않게 한다
static func random(rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var base: String = _ADJ[rng.randi_range(0, _ADJ.size() - 1)] + _NOUN[rng.randi_range(0, _NOUN.size() - 1)]
	var room := MAX_LEN - base.length()
	if room >= 2:
		return base + str(rng.randi_range(10, 99))
	if room == 1:
		return base + str(rng.randi_range(1, 9))
	return base.left(MAX_LEN)
