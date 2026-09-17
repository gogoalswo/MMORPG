#!/usr/bin/env python3
"""한글 폰트에서 쓰는 글자만 남긴다.

왜 — Noto Sans KR 원본은 5.9MB 다. 웹 빌드가 이미 51MB 라 통째로 넣으면
폰에서 받을 것만 늘어난다. 완성형(KS X 1001) 2350자에 ASCII 를 더하면
현대 한국어 문장은 사실상 전부 나오면서 300KB 대로 줄어든다.

**결과물은 커밋한다.** 그래서 보통은 이 스크립트를 돌릴 일이 없다 —
글꼴을 바꾸거나 없는 글자가 네모로 나올 때만 돌린다.

    pip install fonttools
    python3 scripts/build-korean-font.py 받아둔/NotoSansKR.ttf

출처와 약관은 docs/ASSETS.md 에 적는다 (Noto Sans KR, SIL OFL 1.1).
"""
import sys
from pathlib import Path
from fontTools import subset

OUT = Path(__file__).resolve().parent.parent / "public/assets/fonts/NotoSansKR-subset.ttf"


def wanted() -> str:
    # 완성형에 들어가는 음절 = EUC-KR 로 인코딩되는 음절 (2350자)
    hangul = [
        chr(c)
        for c in range(0xAC00, 0xD7A4)
        if _encodable(chr(c))
    ]
    ascii_printable = [chr(c) for c in range(0x20, 0x7F)]
    marks = list("·…—–‘’“”★☆♥→←↑↓×÷±°％①②③④⑤")
    return "".join(ascii_printable + hangul + marks)


def _encodable(ch: str) -> bool:
    """완성형(KS X 1001) 2350자인가.

    파이썬 euc-kr 코덱은 확장 영역까지 받아 주므로 그냥 인코딩되는지만 보면
    11172자가 전부 통과한다 (실제로 2.4MB 가 나왔다). 완성형 음절은 선두
    바이트가 0xB0 이상이라 그걸로 가른다.
    """
    try:
        encoded = ch.encode("euc-kr")
    except UnicodeEncodeError:
        return False
    return encoded[0] >= 0xB0


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("원본 ttf 경로를 넘겨라")
    text = wanted()
    subset.main([
        sys.argv[1],
        f"--text={text}",
        "--layout-features=*",
        f"--output-file={OUT}",
    ])
    print(f"{OUT.name}: {OUT.stat().st_size / 1024:.0f}KB, 글자 {len(text)}자")


if __name__ == "__main__":
    main()
