# balance_sim.py - 스탯 밸런스 시뮬레이터 (docs/features/stat-balance.md 의 공식을 그대로 계산)
# 사용: python tools/balance_sim.py             → 사냥터별 TTK/TTD 매칭표 (기본)
#       python tools/balance_sim.py --grades    → 등비수열 등급표 + 등급업 체감
#       python tools/balance_sim.py --items     → 등급별 슬롯 옵션 수치
#       python tools/balance_sim.py --enh       → 강화 단계별 배수·확률·도달률
#       python tools/balance_sim.py --exp       → 경험치·사냥 효율 곡선
#       python tools/balance_sim.py --growth    → 성장 곡선 (만렙까지 걸리는 시간)
#       python tools/balance_sim.py --drops     → 드랍 확률 (강화 목표에서 역산)
#       python tools/balance_sim.py --class     → 직업별 전투력 비교
#       python tools/balance_sim.py --levels    → 레벨 단위 상세표
# 목적: "몬스터 몇 대에 죽는지 / 내가 몇 대 맞으면 죽는지" 가 200레벨 전 구간에서 목표 범위에 머무는지 확인.
# 설계: 기본 스탯은 레벨당 복리. 장비는 등급별 공격력% 합산(등비수열) + 강화 배수.
#       치명타·공속은 별도 곱산 버킷. 몬스터는 "그 레벨의 기준 장비"(등급 보간)에서 역산.
import math
import sys

P = dict(
    MAX_LEVEL=200,
    FIELD_SPAN=10,        # 사냥터 1개가 담당하는 레벨 폭 → 사냥터 20개
    # --- 기본 스탯: 레벨당 복리 성장 (장비 없음, 직업 배수 1.0) ---
    HP_BASE=100, ATK_BASE=10, DEF_BASE=10,
    GROWTH=0.02,          # 레벨당 +2% → Lv200 에서 약 51배
    # --- 장비: 등급별 "풀세트 합계 %" 를 등비수열로. 슬롯 가중치로 쪼갠다 ---
    GRADE_COUNT=7,        # 등급 수. 사냥터와 1:1 매칭하지 않는다
    GRADE_LV_SPAN=30,     # 착용 레벨 간격 → 등급 1,2,..7 = Lv 1,31,61,91,121,151,181
    GRADE_SUM_START=35.0, # 등급 1 풀세트 합계 (%)
    GRADE_SUM_END=856.0,  # 등급 7 풀세트 합계 (%). 치명타·공속 버킷을 뺀 나머지 예산
    GEAR_ATK_FACTOR=1.00, # 장비 % 가 공격력에 적용되는 비율
    GEAR_DEF_FACTOR=0.60, # 방어력에는 60% 만
    GEAR_HP_FACTOR=0.35,  # HP 에는 35% 만 (생존은 레벨 쪽에 묶는다)
    GEAR_INTERP=True,     # 몬스터 역산 기준 등급을 등급 사이에서 보간 (해금 절벽 제거)
    START_GEAR_SLOTS=1,   # 시작 장비 슬롯 수 (무기 1개). 등급1 무강.
                          # 등급1 은 사냥터 2 에서야 나오므로, 그 전 구간의 몬스터 기준을
                          # "풀셋" 이 아니라 이 상태로 낮춘다 (안 그러면 첫 구간이 제일 느리다)
    DROP_FIELD_OFFSET=1,  # 등급 g 아이템은 "착용 레벨이 속한 사냥터 + 이 값" 에서 나온다.
                          # 1 = 한 구간(10레벨) 위 → 착용 레벨에 도달해도 바로는 못 얻고,
                          # 한 구간 더 올라가 이전 등급으로 뚫어야 한다. 상향 압력의 정체.
    # --- 치명타·공속: 공격력% 와 다른 버킷이라 곱으로 붙는다. 등급에 비례해 커진다 ---
    CRIT_RATE_MAX=0.50,   # 등급 7 에서의 치명타 확률
    CRIT_DMG_MAX=1.00,    # 등급 7 에서의 치명타 추가 피해
    ASPD_MAX=0.20,        # 등급 7 에서의 공격 속도 증가 (장갑 전담)
    MOVE_SPD_MAX=0.25,    # 등급 7 에서의 이동 속도 증가 (신발 전담).
                          # 전투 스탯은 아니지만 사냥 효율(이동 시간)을 줄인다
    # --- 강화: 장비 % 합계에 곱한다. 10단계 = 9번, 실패 시 파괴(재료 없음) ---
    ENH_MAX=10,
    ENH_TOTAL=6.0,        # 1단 -> 10단 총 배수
    ENH_ACCEL=7.0,        # 마지막 구간 증가율 / 첫 구간 증가율
    ENH_REF_STEP=4,       # 몬스터 역산에 쓰는 기준 강화 단계 (사냥터 구간별로 올라간다,
                          # ENH_REF_BY_FIELD 참고. 이 값은 초반 구간용 기본값)
    # --- 데미지 공식: dmg = ATK * K / (K + DEF) ---
    TARGET_REDUCE=0.30,   # 기준 플레이어의 피해 감소율. K 를 여기서 역산
    # --- 목표 체감: 범위 스킬로 무리를 정리하는 사냥 ---
    # 적정 사냥터에서 한 그룹 SPAWN_COUNT 마리를 CLEAR_TIME 초에 정리한다.
    #   50마리 x TTK 6타 = 300 타격 = 범위 20마리 x 15회 시전 → 15초
    # 타수를 3타로 두면 너무 거칠어서 장비 한 등급 갱신(DPS +36%)이 정리 시간을
    # 전혀 줄이지 못한다(3타->2타 에는 +50% 필요). 6타면 계단이 절반으로 촘촘해진다.
    TTK_HITS=6,           # 범위 스킬이 몬스터 한 마리에 들어가는 타격 횟수
    TTK_MARGIN=0.005,     # 몬스터 HP 를 정확히 TTK_HITS 타분으로 잡으면 기준과 같은 장비가
                          # 늘 올림 경계에 얹힌다 — 0.4% 만 모자라도 한 타가 더 든다
                          # (풀세트에서 슬롯 하나가 덜 찬 상태가 바로 그것이다).
                          # HP 를 이만큼 깎아 경계에서 떨어뜨린다. 0.5% 면 그 한 슬롯을 흡수하고,
                          # 그 이상(2%)은 다른 구간의 천장을 대신 무너뜨린다 — 계단은 없앨 수
                          # 없고 옮길 수만 있으므로, 흡수에 필요한 최소값을 쓴다
    CLEAR_TIME=15.0,      # 한 그룹을 정리하는 목표 시간(초)
    # 스폰 수 / 범위 타격 수 / 동시 피격 수는 스킬 해금 단계에 따라 달라진다 (SKILL_STAGES)
    HP_LOSS_PER_CLEAR=0.5,  # 한 그룹 정리하는 동안 잃는 HP 비율.
                          # 잡몹 1마리는 위협이 아니고 무리가 위협인 구조가 된다
    GROUP_GAP=3.0,        # 그룹 간 대기(리스폰·이동) 초
    MON_DEF_RATIO=0.5,    # 몬스터 방어력 = 기준 플레이어 총방어력 x 0.5
    MON_ATTACK_INTERVAL=1.5,
    PLAYER_ATTACK_INTERVAL=1.0,
    # --- 경험치: 몬스터 HP 에 정비례 ---
    # 그룹 사냥에서는 위쪽 한계를 경험치가 아니라 "사망"(HP 손실)이 정한다.
    # 따라서 경험치는 아래 사냥터만 막으면 되고, 지수 1.0 이 그 조건을 만족한다.
    #   1.00 → 아래 0.65~0.87 로 손해, 적정 1.00, +10레벨 1.09(위험 감수), +20 사망  <- 지금 값
    #   0.85 → 아래가 1.00 까지 붙어 저레벨 사냥이 이득이 된다
    EXP_COEF=0.20,
    EXP_HP_POW=1.00,
    # --- 성장 곡선: 만렙까지 걸리는 시간을 먼저 정하고 필요 킬 수를 역산 ---
    TARGET_HOURS=2880.0,  # 1 -> MAX_LEVEL 총 사냥 시간 (24시간 x 120일 = 4개월)
    KILLS_FIELD_MULT=1.5, # 사냥터가 하나 올라갈 때마다 "레벨당 필요 킬 수" x 이 값.
                          # 위로 갈수록 가파르게 만드는 손잡이. 1.0 이면 평평하다
    # 초반(Lv1~30, 스킬 3개가 다 열리기 전)은 스킬이 모자라 사냥 속도가 1/3 이다.
    # 그래서 배수로 잡지 않고 "레벨당 목표 시간" 을 직접 정한다.
    EARLY_FIELDS=3,             # 이 사냥터까지가 초반 (Lv1~30)
    EARLY_LEVEL_MIN=2.0,        # 사냥터 1 의 레벨당 목표 시간(분)
    EARLY_TIME_MULT=1.5,        # 초반 사냥터마다 레벨당 시간 x 이 값 (후반 배수와 같게)
)

# 직업 배수: 공격력/체력/방어/공격간격. DPS x EHP 가 서로 비슷해야 한다 (--class 로 확인)
CLASSES = {
    'knight':  dict(atk=0.85, hp=1.20, df=1.15, interval=1.0),
    'mage':    dict(atk=1.35, hp=0.80, df=0.75, interval=1.0),
    'archer':  dict(atk=1.35, hp=0.90, df=0.85, interval=1.2),
    'fighter': dict(atk=1.00, hp=1.00, df=1.00, interval=0.9),
}
# 역할 배수. 일반 몬스터는 "무리" 기준으로 역산되므로 1마리 공격력이 작다.
# 정예는 무리에 섞여 나오니 그대로 두고, 보스는 1:1 이라 공격력을 크게 올려야 위협이 된다.
# 보스는 아직 설계 전이다(보류). 아래 배수는 자리만 잡아둔 임시값이고,
# "해당 레벨에 꼭 잡을 필요 없다" 는 전제이므로 TTK/TTD 목표도 정해지지 않았다.
# HP 배수는 TTK_HITS 를 바꾸면 같이 조정해야 한다 (TTK_HITS x hp = 목표 타수)
ROLES = {
    'normal': dict(hp=1.0, atk=1.0),
    'elite':  dict(hp=3.0, atk=2.0),
    'boss':   dict(hp=7.0, atk=5.0),
}
# 슬롯 6개. 가중치는 균등이 아니라 SLOT_STATS 배분이다 (무기가 공격력 예산의 60%)
SLOT_ORDER = ['weapon', 'chest', 'helm', 'boots', 'necklace', 'ring']
SLOT_KR = dict(weapon='무기', chest='갑옷', helm='투구', boots='신발',
               necklace='목걸이', ring='반지')
# 슬롯별 스탯 배분: 각 스탯 "예산" 의 몇 %를 그 슬롯이 담당하는가. 스탯별 열 합계 = 1.0
#   atk/df/hp      = 공격력/방어력/HP % 예산의 지분
#   crit/aspd/move = 치명타·공격속도·이동속도 최대치의 지분
# HP 는 방어력과 같은 배분을 쓴다(둘 다 생존 스탯). 치명타는 목걸이, 공속은 반지 전담.
SLOT_STATS = {
    'weapon':   dict(atk=0.60),
    'chest':    dict(df=0.40, hp=0.40),
    'helm':     dict(df=0.20, hp=0.20),
    'boots':    dict(df=0.20, hp=0.20, move=1.00),
    'necklace': dict(atk=0.20, df=0.10, hp=0.10, crit=1.00),
    'ring':     dict(atk=0.20, df=0.10, hp=0.10, aspd=1.00),
}
STAT_ORDER = ['atk', 'df', 'hp', 'crit', 'aspd', 'move']
SLOT_TOTAL = float(len(SLOT_ORDER))
# 스킬 해금 단계. 스킬이 늘면 범위가 넓어지므로 그룹(스폰 수)도 같이 커진다.
# 그래야 "한 그룹을 15초에 정리한다" 는 목표가 초반에도 성립한다.
SKILL_STAGES = [
    dict(level=1,  skills=1, spawn=15, aoe=8,  melee=3),
    dict(level=10, skills=2, spawn=30, aoe=14, melee=4),
    dict(level=30, skills=3, spawn=50, aoe=20, melee=6),
]
# 전직: 레벨과 스킬 해금 지점. 스킬 계수는 확정 후 반영(현재 스탯에는 미적용)
JOB_ADVANCES = [(1, '1차'), (41, '2차'), (81, '3차'), (121, '4차'), (161, '5차')]
# 강화 성공률 (1->2, 2->3, ... 9->10). 실패하면 아이템 파괴
ENH_PR = [0.90, 0.80, 0.70, 0.60, 0.50, 0.40, 0.30, 0.20, 0.10]
# 기준 강화 단계는 사냥터 구간별로 올라간다. (사냥터 시작, 단계)
# 후반 사냥터는 체류 시간이 수백 시간이라 드랍이 훨씬 많이 쌓이므로,
# 4단 고정으로 두면 드랍 간격이 38시간까지 벌어진다. 기준을 올려 드랍을 후하게 한다.
ENH_REF_BY_FIELD = [(1, 4), (7, 5), (13, 6), (18, 7)]
# 드랍 최소 간격(초). 초반 사냥터는 체류가 30분뿐이라 역산하면 1.2분 간격이 나오는데
# 그건 너무 후하다. 간격을 이 값으로 묶으면 목표 개수를 그 구간에서 못 채우고
# 다음 구간까지 이어서 모으게 된다 (초반은 구간이 짧아 자연스럽다).
DROP_MIN_GAP = 180.0


# ---------------------------------------------------------------- 기본
def growth(L):
    return (1 + P['GROWTH']) ** (L - 1)


def base(L):
    g = growth(L)
    return dict(hp=P['HP_BASE'] * g, atk=P['ATK_BASE'] * g, df=P['DEF_BASE'] * g)


def grade_ratio():
    return (P['GRADE_SUM_END'] / P['GRADE_SUM_START']) ** (1.0 / (P['GRADE_COUNT'] - 1))


def grade_sum(g):
    """등급 g 풀세트의 공격력% 합계. g<=0 이면 맨몸. 소수 등급이면 등비 보간된다"""
    if g <= 0:
        return 0.0
    g = min(g, P['GRADE_COUNT'])
    return P['GRADE_SUM_START'] * grade_ratio() ** (g - 1)


def equip_level(g):
    """등급 g 착용 레벨. 등급 간격(GRADE_LV_SPAN)은 사냥터 폭과 독립"""
    return 1 + P['GRADE_LV_SPAN'] * (g - 1)


def field_count():
    return int(math.ceil(P['MAX_LEVEL'] / float(P['FIELD_SPAN'])))


def field_of(L):
    return max(1, min(field_count(), int(math.ceil(L / float(P['FIELD_SPAN'])))))


def grade_of(L):
    """레벨 L 에서 착용 가능한 최고 등급"""
    g = 1 + int((L - 1) // P['GRADE_LV_SPAN'])
    return max(1, min(P['GRADE_COUNT'], g))


def ref_grade(L):
    """몬스터 역산에 쓰는 '기준 장비 등급'. 보간을 켜면 해금 직후엔 이전 등급 수준에서
    시작해 다음 해금 직전에 현재 등급에 도달한다 → 해금 지점의 난이도 절벽이 사라진다."""
    g = grade_of(L)
    if not P['GEAR_INTERP'] or g <= 1:
        return float(g)
    t = min(1.0, (L - equip_level(g)) / float(P['GRADE_LV_SPAN']))
    return (g - 1) + t


def drop_field(g):
    """등급 g 아이템이 나오는 사냥터 번호"""
    return min(field_count(), field_of(equip_level(g)) + P['DROP_FIELD_OFFSET'])


def drop_levels(g):
    f = drop_field(g)
    return P['FIELD_SPAN'] * (f - 1) + 1, P['FIELD_SPAN'] * f


def unlocks_grade(lo, hi):
    for g in range(1, P['GRADE_COUNT'] + 1):
        if lo <= equip_level(g) <= hi:
            return g
    return 0


def skill_stage(L):
    """그 레벨의 스킬 해금 단계"""
    cur = SKILL_STAGES[0]
    for st in SKILL_STAGES:
        if L >= st['level']:
            cur = st
    return cur


def spawn_count(L):
    return skill_stage(L)['spawn']


def aoe_targets(L):
    return skill_stage(L)['aoe']


def melee_attackers(L):
    return skill_stage(L)['melee']


def job_of(L):
    cur = ''
    for lv, name in JOB_ADVANCES:
        if L >= lv:
            cur = name
    return cur


def job_in(lo, hi):
    for lv, name in JOB_ADVANCES:
        if lo <= lv <= hi:
            return name
    return ''


# ---------------------------------------------------------------- 강화
def _enh_gains():
    """단계별 증가율. 첫 구간 : 마지막 구간 = 1 : ENH_ACCEL 이고, 전체 곱이 ENH_TOTAL"""
    n = P['ENH_MAX'] - 1
    k = P['ENH_ACCEL'] ** (1.0 / (n - 1))
    lo, hi = 1e-5, 1.0
    for _ in range(200):
        mid = (lo + hi) / 2
        t = 1.0
        for i in range(n):
            t *= 1 + mid * k ** i
        if t < P['ENH_TOTAL']:
            lo = mid
        else:
            hi = mid
    return [lo * k ** i for i in range(n)]


def enh_mult(step):
    """강화 단계(1~ENH_MAX)의 배수. 1단 = x1.0"""
    step = max(1, min(int(step), P['ENH_MAX']))
    m = 1.0
    for g in _enh_gains()[:step - 1]:
        m *= 1 + g
    return m


def enh_ref_step(L):
    """그 레벨에서 몬스터 역산에 쓰는 기준 강화 단계"""
    f = field_of(L)
    cur = P['ENH_REF_STEP']
    for start, step in ENH_REF_BY_FIELD:
        if f >= start:
            cur = step
    return cur


def coupon_draws(n, m):
    """n 종류가 무작위로 떨어질 때 "모든 종류를 m개 이상" 모으는 기대 드랍 수.
    E = n * integral(1 - (1 - P(Poisson(t) < m))^n) dt  (포아소나이제이션, 정확)"""
    if m <= 0:
        return 0.0
    steps, hi = 4000, 40.0 + 6.0 * m
    h = hi / steps
    total = 0.0
    for i in range(steps + 1):
        t = i * h
        # P(Poisson(t) < m)
        term, ssum = math.exp(-t), math.exp(-t)
        for k in range(1, m):
            term *= t / k
            ssum += term
        val = 1.0 - (1.0 - ssum) ** n
        w = 1.0 if i in (0, steps) else (4.0 if i % 2 else 2.0)
        total += w * val
    return n * total * h / 3.0


def enh_reach(step):
    """아이템 1개를 굴려 그 단계에 도달할 확률 (실패 시 파괴이므로 성공률의 곱)"""
    p = 1.0
    for i in range(min(int(step), P['ENH_MAX']) - 1):
        p *= ENH_PR[i]
    return p


# ---------------------------------------------------------------- 치명타·공속
def grade_ratio_linear(grade):
    """보조 스탯용 등급 진행도. 등급 1 = 0, 등급 GRADE_COUNT = 1 (선형)"""
    if P['GRADE_COUNT'] <= 1:
        return 0.0
    return max(0.0, (min(grade, P['GRADE_COUNT']) - 1.0) / (P['GRADE_COUNT'] - 1.0))


def stat_budget(grade):
    """등급 g 풀세트가 주는 스탯별 총량. %는 기본 스탯 대비, 나머지는 절대 배수"""
    s = grade_sum(grade)
    r = grade_ratio_linear(grade)
    return dict(atk=s * P['GEAR_ATK_FACTOR'], df=s * P['GEAR_DEF_FACTOR'],
                hp=s * P['GEAR_HP_FACTOR'],
                crit=r, aspd=P['ASPD_MAX'] * r, move=P['MOVE_SPD_MAX'] * r)


def slot_stats(slot, grade, enh=1):
    """슬롯 하나가 주는 스탯. 강화는 %스탯(atk/df/hp)에만 곱한다"""
    share = SLOT_STATS[slot]
    bud = stat_budget(grade)
    out = {}
    for st in STAT_ORDER:
        v = bud[st] * share.get(st, 0.0)
        if st in ('atk', 'df', 'hp'):
            v *= enh_mult(enh)
        out[st] = v
    return out


def gear_totals(worn):
    """worn: {슬롯: (등급, 강화단계)}. 착용 중인 슬롯들의 스탯 합계"""
    tot = dict((st, 0.0) for st in STAT_ORDER)
    for slot, (g, e) in worn.items():
        sv = slot_stats(slot, g, e)
        for st in STAT_ORDER:
            tot[st] += sv[st]
    return tot


def dps_mult(grade, enh=None):
    """등급 g 풀세트(강화 enh)의 총 DPS 배수 = (1+공격력%) x 치명타 x 공속"""
    enh = P['ENH_REF_STEP'] if enh is None else enh
    tot = gear_totals(dict((slot, (grade, enh)) for slot in SLOT_ORDER))
    return (1 + tot['atk'] / 100.0) * crit_mult_of(tot) * (1 + tot['aspd'])


def crit_mult_of(tot):
    """평균 피해 배수. 치명타 지분 r 에 최대 확률·피해를 곱한다"""
    r = tot['crit']
    return 1 + (P['CRIT_RATE_MAX'] * r) * (P['CRIT_DMG_MAX'] * r)


# ---------------------------------------------------------------- 플레이어
def _build(L, cls, grade, gear, enh, worn=None):
    """worn 을 주면 슬롯별 착용 상태로 계산. 없으면 전 슬롯 같은 등급·강화(gear=완성도)"""
    b = base(L)
    if worn is None:
        if gear <= 0:
            tot = dict((st, 0.0) for st in STAT_ORDER)
        else:
            tot = gear_totals(dict((slot, (grade, enh)) for slot in SLOT_ORDER))
            if gear < 1.0:
                tot = dict((st, v * gear) for st, v in tot.items())
    else:
        tot = gear_totals(worn)
    m = CLASSES.get(cls, dict(atk=1, hp=1, df=1, interval=P['PLAYER_ATTACK_INTERVAL']))
    return dict(
        hp=b['hp'] * (1 + tot['hp'] / 100.0) * m['hp'],
        atk=b['atk'] * (1 + tot['atk'] / 100.0) * m['atk'],
        df=b['df'] * (1 + tot['df'] / 100.0) * m['df'],
        interval=m['interval'] / (1 + tot['aspd']),
        move_spd=tot['move'],
        level=L, grade=grade, enh=enh, tot=tot, crit=crit_mult_of(tot))


def player(L, cls='ref', grade=None, gear=1.0, enh=None):
    """grade: 착용 등급(기본=그 레벨 착용 가능 최고 등급), gear: 풀세트 완성도, enh: 강화 단계"""
    return _build(L, cls, grade_of(L) if grade is None else grade, gear,
                  enh_ref_step(L) if enh is None else enh)


def ref_gear(L):
    """그 레벨에서 현실적으로 갖고 있는 (착용 슬롯, 강화 단계). 풀세트면 worn=None.
    등급1 드랍 사냥터에 들어가기 전에는 시작 장비(무기 START_GEAR_SLOTS개, 무강) 뿐이다.
    이때 "풀셋 완성도 1/6" 같은 스칼라로 두면 안 된다 — 무기 한 자루가 방어력·HP 까지
    주게 된다. 슬롯별 착용(worn)으로 계산해야 SLOT_STATS 배분이 그대로 걸려서
    무기는 공격력 예산의 60% 만 준다(방어력·HP 0)."""
    if L < drop_levels(1)[0]:
        worn = dict((s, (1, 1)) for s in SLOT_ORDER[:P['START_GEAR_SLOTS']])
        return worn, 1
    return None, enh_ref_step(L)


def ref_player(L):
    """몬스터 역산의 기준. 기준 등급(보간) + 그 레벨에서 현실적인 장비 상태"""
    worn, enh = ref_gear(L)
    return _build(L, 'ref', ref_grade(L), 1.0, enh, worn=worn)


# ---------------------------------------------------------------- 전투
def K(attacker_level):
    """기준 플레이어의 감소율이 TARGET_REDUCE 가 되도록 역산.
    공격자 레벨이 높을수록 K 가 커져 내 방어력 효율이 떨어진다(레벨차 페널티 내장)."""
    t = P['TARGET_REDUCE']
    return ref_player(attacker_level)['df'] * (1 - t) / t


def damage(atk, attacker_level, df):
    k = K(attacker_level)
    return max(1.0, atk * k / (k + df))


def monster(L, role='normal'):
    """그 레벨의 기준 플레이어에서 역산. 몬스터에게 치명타는 없다.
    HP  : 범위 스킬 TTK_HITS 타에 죽도록
    공격: 한 그룹(CLEAR_TIME 초) 정리하는 동안 HP_LOSS_PER_CLEAR 만큼 잃도록.
          MELEE_ATTACKERS 마리가 동시에 때린다고 보므로 1마리 공격력은 그만큼 작아진다"""
    ref = ref_player(L)
    df = ref['df'] * P['MON_DEF_RATIO']
    hp = P['TTK_HITS'] * (1 - P['TTK_MARGIN']) * damage(ref['atk'], L, df) * ref['crit']
    # 받아야 하는 총 피해 / 초
    dps_in = ref['hp'] * P['HP_LOSS_PER_CLEAR'] / P['CLEAR_TIME']
    want = dps_in * P['MON_ATTACK_INTERVAL'] / melee_attackers(L)   # 1마리 1타 피해
    k = K(L)
    atk = want * (k + ref['df']) / k
    r = ROLES[role]
    return dict(hp=hp * r['hp'], atk=atk * r['atk'], df=df,
                interval=P['MON_ATTACK_INTERVAL'], level=L, role=role)


def group_clear(pl, mo):
    """(그룹 정리에 필요한 시전 횟수, 정리 시간, 몬스터 1마리 필요 타격수)"""
    d = damage(pl['atk'], pl['level'], mo['df']) * pl['crit']
    hits = int(math.ceil(mo['hp'] / d))
    L = pl['level']
    casts = int(math.ceil(spawn_count(L) * hits / float(aoe_targets(L))))
    return casts, casts * pl['interval'], hits


def hp_loss(pl, mo, seconds):
    """seconds 동안 잃는 HP 비율. MELEE_ATTACKERS 마리가 동시에 때린다"""
    d2 = damage(mo['atk'], mo['level'], pl['df'])
    taken = melee_attackers(pl['level']) * d2 * (seconds / mo['interval'])
    return taken / pl['hp']


def fight(pl, mo):
    """(TTK 타수, TTK 초, TTD 타수, TTD 초, 내 평균피해, 몬스터 피해)"""
    d = damage(pl['atk'], pl['level'], mo['df']) * pl['crit']
    hits = int(math.ceil(mo['hp'] / d))
    d2 = damage(mo['atk'], mo['level'], pl['df'])
    hits2 = int(math.ceil(pl['hp'] / d2))
    return hits, hits * pl['interval'], hits2, hits2 * mo['interval'], d, d2


def mon_exp(mo):
    return P['EXP_COEF'] * mo['hp'] ** P['EXP_HP_POW']


_KILL_BASE = [None]


def kill_rate(L):
    """그 레벨 기준 플레이어의 사냥 속도 (마리/초)"""
    pl = player(L)
    mo = monster(L)
    return spawn_count(L) / group_time(pl, mo)


def _kills_base():
    """사냥터 1 의 레벨당 킬 수. 목표 총 시간(TARGET_HOURS)에서 역산한다"""
    if _KILL_BASE[0] is None:
        early = 0.0
        for L in range(1, min(P['EARLY_FIELDS'] * P['FIELD_SPAN'], P['MAX_LEVEL'] - 1) + 1):
            early += P['EARLY_LEVEL_MIN'] * 60.0 * P['EARLY_TIME_MULT'] ** (field_of(L) - 1)
        acc = 0.0
        for L in range(P['EARLY_FIELDS'] * P['FIELD_SPAN'] + 1, P['MAX_LEVEL']):
            acc += P['KILLS_FIELD_MULT'] ** (field_of(L) - P['EARLY_FIELDS'] - 1) / kill_rate(L)
        _KILL_BASE[0] = (P['TARGET_HOURS'] * 3600.0 - early) / acc
    return _KILL_BASE[0]


def kills_per_level(L):
    """L -> L+1 에 필요한 킬 수.
    초반(EARLY_FIELDS 까지)은 레벨당 목표 시간에서 직접 뽑고,
    그 뒤는 사냥터마다 KILLS_FIELD_MULT 배로 늘려 총 시간을 TARGET_HOURS 에 맞춘다"""
    f = field_of(L)
    if f <= P['EARLY_FIELDS']:
        target_sec = P['EARLY_LEVEL_MIN'] * 60.0 * P['EARLY_TIME_MULT'] ** (f - 1)
        return target_sec * kill_rate(L)
    return _kills_base() * P['KILLS_FIELD_MULT'] ** (f - P['EARLY_FIELDS'] - 1)


def level_seconds(L):
    """L -> L+1 에 걸리는 시간(초)"""
    return kills_per_level(L) / kill_rate(L)


def level_exp(L):
    """L -> L+1 에 필요한 경험치"""
    return kills_per_level(L) * mon_exp(monster(L))


def exp_pow_ideal():
    """효율이 목표 TTK 에서 최대가 되는 경험치 지수.
    그룹 사냥에서는 (정리 시간) / (정리 시간 + 그룹 간 대기)"""
    return P['CLEAR_TIME'] / (P['CLEAR_TIME'] + P['GROUP_GAP'])


def group_time(pl, mo):
    """한 그룹을 처리하는 데 드는 총 시간 = 정리 시간 + 그룹 간 대기"""
    return group_clear(pl, mo)[1] + P['GROUP_GAP']


def efficiency(pl, mo):
    """경험치/초 (그룹 단위)"""
    return spawn_count(pl['level']) * mon_exp(mo) / group_time(pl, mo)


def fmt(n):
    return format(int(round(n)), ',')


# ---------------------------------------------------------------- 등급표
def grades():
    print('등비수열 등급표: 등급마다 풀세트 합계 %% 가 x%.4f.  등급 1 = %.0f%%  ->  등급 %d = %.0f%%'
          % (grade_ratio(), P['GRADE_SUM_START'], P['GRADE_COUNT'], P['GRADE_SUM_END']))
    print('DPS배수 = (1 + 공격력%% x 강화%d단) x 치명타 x 공속.  1칸갱신 = 무기만 다음 등급으로'
          % P['ENH_REF_STEP'])
    hdr = '%4s %7s %8s %8s %7s %6s %6s %6s %9s %9s %9s' % (
        '등급', '착용Lv', '공격예산', '무기%', '방어예산', '치확', '치피', '공속', 'DPS배수',
        '1칸갱신', '레벨환산')
    print(hdr)
    print('-' * len(hdr))
    e = enh_mult(P['ENH_REF_STEP'])
    for g in range(1, P['GRADE_COUNT'] + 1):
        bud = stat_budget(g)
        w = slot_stats('weapon', g, 1)   # 무강 기준 표시
        dps = dps_mult(g)
        if g < P['GRADE_COUNT']:
            worn = dict((slot, (g, P['ENH_REF_STEP'])) for slot in SLOT_ORDER)
            worn['weapon'] = (g + 1, P['ENH_REF_STEP'])
            t1 = gear_totals(worn)
            d1 = (1 + t1['atk'] / 100.0) * crit_mult_of(t1) * (1 + t1['aspd'])
            one = '%8.1f%%' % ((d1 / dps - 1) * 100)
            lvq = '%6.1f레벨' % (math.log(dps_mult(g + 1) / dps) / math.log(1 + P['GROWTH']))
        else:
            one, lvq = '%9s' % '-', '%9s' % '-'
        print('%4d %7d %7.0f%% %7.0f%% %6.0f%% %5.0f%% %5.0f%% %5.0f%% %8.1fx %s %s'
              % (g, equip_level(g), grade_sum(g), w['atk'], bud['df'],
                 P['CRIT_RATE_MAX'] * bud['crit'] * 100, P['CRIT_DMG_MAX'] * bud['crit'] * 100,
                 bud['aspd'] * 100, dps, one, lvq))

    print()
    print('스탯 예산 (등급7 풀세트 무강 기준): ' +
          '  '.join('%s %.0f%%' % (k, stat_budget(P['GRADE_COUNT'])[k])
                    for k in ['atk', 'df', 'hp']) +
          '   치확 %.0f%% 치피 %.0f%% 공속 %.0f%% 이동 %.0f%%'
          % (P['CRIT_RATE_MAX'] * 100, P['CRIT_DMG_MAX'] * 100,
             P['ASPD_MAX'] * 100, P['MOVE_SPD_MAX'] * 100))


# ---------------------------------------------------------------- 슬롯 옵션
def items():
    print('슬롯별 스탯 배분 — 각 스탯 예산의 몇 %를 그 슬롯이 담당하는가 (열 합계 = 100%)')
    hdr = '%8s ' % '슬롯' + ' '.join('%8s' % k for k in ['공격력', '방어력', 'HP', '치명타', '공속', '이동속도'])
    print(hdr)
    print('-' * len(hdr))
    for slot in SLOT_ORDER:
        sh = SLOT_STATS[slot]
        cells = ['%7s' % (('%.0f%%' % (sh[st] * 100)) if st in sh else '-')
                 for st in STAT_ORDER]
        print('%8s ' % SLOT_KR[slot] + ' '.join('%8s' % c for c in cells))
    print('%8s ' % '합계' + ' '.join('%8s' % ('%.0f%%' % (sum(SLOT_STATS[x].get(st, 0) for x in SLOT_ORDER) * 100))
                                     for st in STAT_ORDER))
    print()
    print('무기 = 공격력 %.0f%%. 목걸이·반지가 공격력 %.0f%% 씩 나눠 가져 무기 독점을 막는다.'
          % (SLOT_STATS['weapon']['atk'] * 100, SLOT_STATS['necklace']['atk'] * 100))
    print('방어력·HP 는 갑옷 %.0f%% / 투구 %.0f%% / 신발 %.0f%% / 목걸이 %.0f%% / 반지 %.0f%%.'
          % tuple(SLOT_STATS[k]['df'] * 100 for k in ['chest', 'helm', 'boots', 'necklace', 'ring']))
    print('치명타는 목걸이, 공격속도는 반지, 이동속도는 신발 전담 — 슬롯마다 성격이 갈린다.')

    print()
    print('=== 등급별 슬롯 실제 수치 (무강 / 강화 %d단) ===' % P['ENH_REF_STEP'])
    for g in [1, 4, 7]:
        print('  등급 %d (착용 Lv%d)' % (g, equip_level(g)))
        for slot in SLOT_ORDER:
            a = slot_stats(slot, g, 1)
            b = slot_stats(slot, g, P['ENH_REF_STEP'])
            parts = []
            for st, label in [('atk', '공격력'), ('df', '방어력'), ('hp', 'HP')]:
                if a[st] > 0:
                    parts.append('%s +%.0f%%(→%.0f%%)' % (label, a[st], b[st]))
            for st, label, mx in [('crit', '치확', P['CRIT_RATE_MAX']),
                                  ('aspd', '공속', 1.0), ('move', '이동', 1.0)]:
                if a[st] > 0:
                    v = a[st] * (mx if st == 'crit' else 1.0)
                    parts.append('%s +%.0f%%' % (label, v * 100))
            print('    %-4s %s' % (SLOT_KR[slot], ', '.join(parts)))
        print()

    lo1 = drop_levels(1)[0]
    print('시작 장비: %s %d개(등급1 무강). Lv1~%d 은 이 상태이므로 그 구간 몬스터도 여기 맞춰 역산한다.'
          % (SLOT_KR['weapon'], P['START_GEAR_SLOTS'], lo1 - 1))
    print('드랍은 착용 레벨보다 %d구간(%d레벨) 위 → 착용 레벨에 도달해도 바로 못 얻는다.'
          % (P['DROP_FIELD_OFFSET'], P['DROP_FIELD_OFFSET'] * P['FIELD_SPAN']))
    print('그 사냥터를 "이전 등급" 으로 뚫어야 하고, 맞추면 편해진다. 이게 상향 압력의 정체.')
    print()
    hdr2 = '%4s %14s %20s %20s' % ('등급', '드랍 사냥터', '진입 시', '맞춘 직후')
    print(hdr2)
    print('-' * len(hdr2))
    for g in range(1, P['GRADE_COUNT'] + 1):
        lo, hi = drop_levels(g)
        mo = monster(lo)
        if g == 1:
            a = fight(_build(lo, 'ref', 1, 1.0, 1,
                             worn={'weapon': (1, 1)}), mo)
        else:
            a = fight(player(lo, grade=g - 1), mo)
        b = fight(player(lo, grade=g), mo)
        print('%4d %8d Lv%-3d %13d타/%3d타 %13d타/%3d타'
              % (g, drop_field(g), lo, a[0], a[2], b[0], b[2]))


# ---------------------------------------------------------------- 강화
def enhance():
    gs = _enh_gains()
    print('강화 %d단계 = %d번의 강화. 실패하면 아이템 파괴(재료 없음). 1단 -> %d단 총 x%.1f'
          % (P['ENH_MAX'], P['ENH_MAX'] - 1, P['ENH_MAX'], P['ENH_TOTAL']))
    print('증가율은 고강화일수록 크다 (첫 구간 : 마지막 구간 = 1 : %.0f)' % P['ENH_ACCEL'])
    print('공짜라 무한 재시도 가능 → 실질 비용은 "아이템 몇 개"')
    print()
    hdr = '%5s %9s %9s %10s %14s %s' % ('단계', '성공률', '증가율', '배수', '도달률', '아이템 몇 개당 1개')
    print(hdr)
    print('-' * len(hdr))
    for step in range(1, P['ENH_MAX'] + 1):
        pr = '%8.0f%%' % (ENH_PR[step - 2] * 100) if step >= 2 else '%9s' % '-'
        gn = '%8.0f%%' % (gs[step - 2] * 100) if step >= 2 else '%9s' % '-'
        r = enh_reach(step)
        mark = ' <- 기준' if step == P['ENH_REF_STEP'] else ''
        print('%5d %s %s %9.2fx %13.4f%% %14s%s'
              % (step, pr, gn, enh_mult(step), r * 100, fmt(1 / r), mark))

    print()
    print('기준 %d단(x%.2f) 대비 — 몬스터는 기준 단계에 맞춰 역산된다 (Lv100 동레벨 몬스터)'
          % (P['ENH_REF_STEP'], enh_mult(P['ENH_REF_STEP'])))
    L = 100
    mo = monster(L)
    for step in [1, 2, P['ENH_REF_STEP'], 6, 8, P['ENH_MAX']]:
        h, _, h2, _, _, _ = fight(player(L, enh=step), mo)
        print('  %2d단 (x%.2f): TTK %3d타 / TTD %3d타' % (step, enh_mult(step), h, h2))

    print()
    print('공짜이므로 도달 단계는 드랍률이 정한다 — 슬롯당 아이템 N 개로 갈 수 있는 곳')
    print('%10s ' % '슬롯당 N개' + ' '.join('%7s' % ('%d단' % st) for st in range(4, P['ENH_MAX'] + 1)))
    for n in [2, 3, 10, 30, 100, 300]:
        cells = ['%6.0f%%' % ((1 - (1 - enh_reach(st)) ** n) * 100)
                 for st in range(4, P['ENH_MAX'] + 1)]
        print('%10d ' % n + ' '.join('%7s' % c for c in cells))
    print()
    print('=> 기준 %d단 유지에는 사냥터 수명(%d레벨) 동안 슬롯당 아이템 %.1f 개 수준이 필요하다.'
          % (P['ENH_REF_STEP'], P['GRADE_LV_SPAN'], 1 / enh_reach(P['ENH_REF_STEP'])))


# ---------------------------------------------------------------- 경험치·효율
def expcurve():
    print('경험치 = %.2f x 몬스터HP^%.2f.  레벨업 필요 킬 수는 사냥터마다 x%.2f (--growth)'
          % (P['EXP_COEF'], P['EXP_HP_POW'], P['KILLS_FIELD_MULT']))
    print('그룹 사냥: 한 그룹을 정리하고 %.0f초 대기(리스폰·이동). 스폰/범위/동시피격은 스킬 단계별.'
          % P['GROUP_GAP'])
    print('  ' + '  |  '.join('Lv%d~ 스킬%d: %d마리 스폰, 범위 %d, 동시피격 %d'
                              % (st['level'], st['skills'], st['spawn'], st['aoe'], st['melee'])
                              for st in SKILL_STAGES))
    print('상향 압력은 드랍(상위 등급은 상위 사냥터에서만)이 담당하므로, 경험치는 중립이어야 한다.')
    print('  지수 %.2f (지금 값) → 아래 사냥터가 손해. 위쪽 한계는 경험치가 아니라 사망이 정한다.'
          % P['EXP_HP_POW'])
    print('  지수를 낮추면(0.85) 아래 사냥터 효율이 적정까지 붙어 저레벨 사냥이 이득이 된다.')
    print()
    hdr = '%3s %9s %5s %9s %9s %8s %8s %13s %s' % (
        '#', '레벨', '등급', '몬스터HP', '1마리exp', '1마리타수', '시전횟수',
        '그룹 정리(초)', '레벨업(분)')
    print(hdr)
    print('-' * len(hdr))
    for f in range(1, field_count() + 1, 2):
        L = P['FIELD_SPAN'] * f
        mo = monster(L)
        pl = player(L)
        casts, ct, hits = group_clear(pl, mo)
        need = level_exp(L)
        groups = need / (spawn_count(L) * mon_exp(mo))
        print('%3d %4d~%-4d %5d %9s %9s %7d타 %8d회 %13.1f %11.1f'
              % (f, L - P['FIELD_SPAN'] + 1, L, grade_of(L), fmt(mo['hp']),
                 fmt(mon_exp(mo)), hits, casts, ct,
                 groups * group_time(pl, mo) / 60.0))

    print()
    print('=== 그룹 정리 중 HP 손실 (목표 %.0f%%) ===' % (P['HP_LOSS_PER_CLEAR'] * 100))
    print('%3s %6s %14s %12s %14s' % ('#', '레벨', '정리 시간(초)', 'HP 손실', '버틸 수 있는 시간'))
    for f in [1, 5, 10, 15, 20]:
        L = P['FIELD_SPAN'] * f
        mo = monster(L)
        pl = player(L)
        _, ct, _ = group_clear(pl, mo)
        loss = hp_loss(pl, mo, ct)
        surv = ct / loss if loss > 0 else 0
        print('%3d %6d %14.1f %11.0f%% %13.1f초' % (f, L, ct, loss * 100, surv))

    print()
    print('=== 효율 곡선: Lv100 기준 플레이어가 각 사냥터를 돌 때 (동레벨 = 1.00) ===')
    pl = player(100)
    rows = []
    ref = None
    for ML in range(60, 141, 10):
        mo = monster(ML)
        casts, ct, hits = group_clear(pl, mo)
        eff = efficiency(pl, mo)
        rows.append((ML, hits, ct, hp_loss(pl, mo, ct), eff))
        if ML == 100:
            ref = eff
    print('%8s %8s %14s %11s %10s' % ('몬스터Lv', '1마리타수', '그룹 정리(초)', 'HP 손실', '상대효율'))
    for ML, hits, ct, loss, eff in rows:
        mark = '  <- 적정' if ML == 100 else ('  (사망)' if loss >= 1.0 else '')
        print('%8d %7d타 %14.1f %10.0f%% %9.2f  %s%s'
              % (ML, hits, ct, loss * 100, eff / ref,
                 '#' * int(round(eff / ref * 30)), mark))
    print()
    print('경험치 = 몬스터 HP x %.2f (정비례). 아래 사냥터는 손해, 위는 사망이 막는다.' % P['EXP_COEF'])
    print('상위 사냥터로 올라갈 동기는 드랍(그 등급 장비)으로 준다.')
    print('타수가 정수라 반올림 때문에 효율 곡선에 약간의 톱니가 생긴다(Lv70/Lv80 동률).')
    print()
    print('=== 장비가 밀린 채 레벨만 올랐을 때 (레벨은 쉬운 곳에서, 아이템은 그 다음) ===')
    print('%6s %8s %10s %18s' % ('레벨', '착용등급', '기준등급', '자기 레벨 사냥터'))
    for L in [100, 140, 180]:
        proper = grade_of(L)
        for g in range(max(1, proper - 2), proper + 1):
            pl = player(L, grade=g)
            mo = monster(L)
            _, ct, _ = group_clear(pl, mo)
            loss = hp_loss(pl, mo, ct)
            tag = ' <- 정상' if g == proper else ' (%d등급 밀림)' % (proper - g)
            cell = '%5.0f초/사망' % ct if loss >= 1.0 else '%5.0f초/%3.0f%%' % (ct, loss * 100)
            print('%6d %8d %10.2f %18s%s' % (L, g, ref_grade(L), cell, tag))
    print()
    print('밀린 장비를 따라잡는 경로: 레벨이 앞서면 아래 사냥터가 쉬워져 그 등급을 주울 수 있다.')
    print('등급4 가 나오는 사냥터(Lv%d)를 등급3 장비로 돌 때:' % 120)
    for L in [91, 120, 140, 160]:
        pl = player(L, grade=3)
        mo = monster(120)
        _, ct, _ = group_clear(pl, mo)
        loss = hp_loss(pl, mo, ct)
        print('  내 레벨 %3d → %5.1f초 / HP %3.0f%%%s'
              % (L, ct, loss * 100, '  (사망)' if loss >= 1.0 else ''))


# ---------------------------------------------------------------- 드랍 확률
def drop_need(step):
    """기준 강화 단계 step 을 전 슬롯에서 달성하는 데 필요한 기대 드랍 수.
    (슬롯당 필요 개수 x 쿠폰 수집 보정 — 슬롯이 무작위로 떨어지므로)"""
    per_slot = 1.0 / enh_reach(step)
    m = max(1, int(round(per_slot)))
    return coupon_draws(len(SLOT_ORDER), m), per_slot, m


def field_stay(f):
    """사냥터 f 체류 중의 (킬 수, 초)"""
    lo = P['FIELD_SPAN'] * (f - 1) + 1
    hi = min(P['FIELD_SPAN'] * f, P['MAX_LEVEL'] - 1)
    kills = sum(kills_per_level(L) for L in range(lo, hi + 1))
    secs = sum(level_seconds(L) for L in range(lo, hi + 1))
    return kills, secs


def drop_plan(g):
    """등급 g 의 드랍 계획. (사냥터, lo, hi, 체류킬, 체류초, 기준단계, 슬롯당,
    목표개수, 그 구간에서 실제 나오는 개수, 드랍률, 간격초, 목표 채우는 데 걸리는 초)"""
    f = drop_field(g)
    lo, hi = drop_levels(g)
    kills, secs = field_stay(f)
    step = enh_ref_step(hi)
    need, per_slot, m = drop_need(step)
    got = min(need, secs / DROP_MIN_GAP)      # 최소 간격으로 묶는다
    rate = got / kills
    gap = secs / got
    return dict(field=f, lo=lo, hi=hi, kills=kills, secs=secs, step=step,
                per_slot=per_slot, need=need, got=got, rate=rate, gap=gap,
                full_secs=need * gap)


def drops():
    print('드랍 확률: "그 사냥터에 머무는 동안 강화 기준 단계를 달성할 만큼" 에서 역산한다.')
    print('강화 재료가 없으므로 아이템 자체가 연료다 — 파괴되며 단계를 올린다.')
    print('슬롯이 무작위로 떨어지므로 쿠폰 수집 보정이 붙는다 (슬롯당 2개 = 12개가 아니라 24개).')
    print('드랍 간격은 최소 %.0f분으로 묶는다 — 초반 사냥터는 체류가 짧아 역산값이 너무 후하다.'
          % (DROP_MIN_GAP / 60.0))
    print()
    hdr = '%4s %6s %10s %11s %9s %7s %8s %9s %10s' % (
        '등급', '사냥터', '레벨', '체류 킬 수', '체류 시간', '기준강화',
        '목표 개수', '구간 내', '드랍률')
    print(hdr)
    print('-' * len(hdr))
    plans = []
    for g in range(1, P['GRADE_COUNT'] + 1):
        d = drop_plan(g)
        plans.append((g, d))
        tstr = ('%.1f시간' % (d['secs'] / 3600.0)) if d['secs'] < 86400 * 2             else ('%.0f일' % (d['secs'] / 86400.0))
        cap = '*' if d['got'] < d['need'] - 0.5 else ' '
        print('%4d %6d %5d~%-4d %11s %9s %6d단 %8.0f %8.0f%s %9.4f%%'
              % (g, d['field'], d['lo'], d['hi'], fmt(d['kills']), tstr, d['step'],
                 d['need'], d['got'], cap, d['rate'] * 100))
    print('* = 최소 간격에 묶여 그 구간에서 목표를 못 채운다 → 다음 구간까지 이어서 모은다')

    print()
    print('플레이어가 느끼는 값 — 슬롯별 확률 = 전체 / %d' % len(SLOT_ORDER))
    hdr2 = '%4s %12s %14s %16s %20s' % (
        '등급', '드랍 간격', '슬롯별 확률', '하루(24h) 드랍', '목표 개수 채우는 시간')
    print(hdr2)
    print('-' * len(hdr2))
    for g, d in plans:
        gstr = ('%.1f분' % (d['gap'] / 60.0)) if d['gap'] < 3600             else ('%.1f시간' % (d['gap'] / 3600.0))
        fstr = ('%.0f분' % (d['full_secs'] / 60.0)) if d['full_secs'] < 7200             else (('%.1f시간' % (d['full_secs'] / 3600.0)) if d['full_secs'] < 86400 * 2
                  else ('%.0f일' % (d['full_secs'] / 86400.0)))
        note = ''
        if d['full_secs'] > d['secs'] * 1.05:
            note = '  (체류 %s 초과)' % (('%.0f분' % (d['secs'] / 60.0))
                                      if d['secs'] < 7200 else '%.0f시간' % (d['secs'] / 3600.0))
        print('%4d %12s %13.5f%% %16.1f %20s%s'
              % (g, gstr, d['rate'] / len(SLOT_ORDER) * 100, 86400.0 / d['gap'], fstr, note))

    print()
    print('=== 기준 강화를 4단 고정으로 두면 (구간별로 올리지 않으면) ===')
    need4 = drop_need(4)[0]
    for g in [1, 4, 7]:
        f = drop_field(g)
        kills, secs = field_stay(f)
        gap = max(secs / need4, DROP_MIN_GAP)
        gstr = ('%.1f분' % (gap / 60.0)) if gap < 3600 else ('%.1f시간' % (gap / 3600.0))
        print('  등급%d: 목표 %.0f개, 간격 %s' % (g, need4, gstr))
    print('  → 후반 간격이 수십 시간으로 벌어진다. 그래서 기준 강화를 구간별로 올렸다.')


# ---------------------------------------------------------------- 성장 곡선
def growth_curve():
    print('성장 곡선: 만렙 %d 까지 %.0f시간 (24시간 기준 %.0f일) 이 되도록 역산.'
          % (P['MAX_LEVEL'], P['TARGET_HOURS'], P['TARGET_HOURS'] / 24.0))
    print('레벨당 필요 킬 수는 사냥터가 하나 올라갈 때마다 x%.2f — 위로 갈수록 가파르다.'
          % P['KILLS_FIELD_MULT'])
    print('사냥 속도는 그룹 단위(스폰 수 / 정리 시간 + 대기 %.0f초) 로 계산한다.'
          % P['GROUP_GAP'])
    print('Lv%d 까지는 스킬이 모자라 사냥이 느리므로 "레벨당 %.1f분 x%.2f" 로 직접 잡고,'
          % (P['EARLY_FIELDS'] * P['FIELD_SPAN'], P['EARLY_LEVEL_MIN'], P['EARLY_TIME_MULT']))
    print('그 뒤부터 사냥터마다 x%.2f 로 가팔라진다.' % P['KILLS_FIELD_MULT'])
    print()
    hdr = '%3s %9s %14s %12s %13s %12s %9s' % (
        '#', '레벨', '레벨당 킬 수', '레벨당 시간', '구간 소요', '누적(일)', '누적 비중')
    print(hdr)
    print('-' * len(hdr))
    total = sum(level_seconds(L) for L in range(1, P['MAX_LEVEL']))
    acc = 0.0
    for f in range(1, field_count() + 1):
        lo = P['FIELD_SPAN'] * (f - 1) + 1
        hi = P['FIELD_SPAN'] * f
        seg = sum(level_seconds(L) for L in range(lo, min(hi, P['MAX_LEVEL'] - 1) + 1))
        acc += seg
        per = level_seconds(lo)
        per_s = ('%.1f분' % (per / 60.0)) if per < 3600 else ('%.1f시간' % (per / 3600.0))
        seg_s = ('%.1f시간' % (seg / 3600.0)) if seg < 86400 else ('%.1f일' % (seg / 86400.0))
        print('%3d %4d~%-4d %14s %12s %13s %11.1f %8.0f%%'
              % (f, lo, hi, fmt(kills_per_level(lo)), per_s, seg_s,
                 acc / 86400.0, acc / total * 100))
    print()
    print('마지막 레벨(%d -> %d) 하나에 %.1f시간 = %.1f일.'
          % (P['MAX_LEVEL'] - 1, P['MAX_LEVEL'],
             level_seconds(P['MAX_LEVEL'] - 1) / 3600.0,
             level_seconds(P['MAX_LEVEL'] - 1) / 86400.0))
    print()
    print('주요 도달 시점')
    acc = 0.0
    marks = {}
    for L in range(1, P['MAX_LEVEL']):
        acc += level_seconds(L)
        marks[L + 1] = acc
    for L in [10, 50, 100, 150, 170, 180, 190, 200]:
        if L in marks:
            print('  Lv%-3d  %7.1f일  (전체의 %3.0f%%)'
                  % (L, marks[L] / 86400.0, marks[L] / total * 100))
    print()
    print('구간별 비중: Lv1~100 %.0f%%, 100~150 %.0f%%, 150~180 %.0f%%, 180~200 %.0f%%'
          % (marks[100] / total * 100,
             (marks[150] - marks[100]) / total * 100,
             (marks[180] - marks[150]) / total * 100,
             (marks[200] - marks[180]) / total * 100))


# ---------------------------------------------------------------- 사냥터 매칭
def _grp(pl, mo):
    """'정리초/HP손실%' 문자열. HP 손실 100% 이상이면 사망"""
    _, ct, _ = group_clear(pl, mo)
    loss = hp_loss(pl, mo, ct)
    if loss >= 1.0:
        return '%5.0fs/사망' % ct
    return '%5.0fs/%3.0f%%' % (ct, loss * 100)


def fields():
    print('사냥터 %d개 (레벨 %d 구간씩)  x  장비 등급 %d개 (착용 레벨 %d 간격). 등급 1개가 사냥터 %d개를 덮는다.'
          % (field_count(), P['FIELD_SPAN'], P['GRADE_COUNT'], P['GRADE_LV_SPAN'],
             P['GRADE_LV_SPAN'] // P['FIELD_SPAN']))
    print('몬스터는 "그 레벨의 기준 장비(등급 %s + 강화 %d단)" 에서 역산.'
          % ('보간' if P['GEAR_INTERP'] else '계단', P['ENH_REF_STEP']))
    print('목표: 한 그룹을 %.0f초에 정리하고 그동안 HP %.0f%% 를 잃는다 (몬스터 1마리에 %d타)'
          % (P['CLEAR_TIME'], P['HP_LOSS_PER_CLEAR'] * 100, P['TTK_HITS']))
    print('스킬 단계: ' + ' | '.join('Lv%d~ 스폰%d/범위%d/동시%d'
                                   % (st['level'], st['spawn'], st['aoe'], st['melee'])
                                   for st in SKILL_STAGES))
    print('각 칸 = 그룹 정리 시간 / 그동안의 HP 손실')
    print()
    hdr = ('%3s %9s %5s %5s %8s %5s | %-11s | %-11s | %-11s | %-11s'
           % ('#', '레벨', '등급', '해금', 'DPS배수', '전직',
              '이전등급', '기준등급', '다음등급', '맨몸'))
    print(hdr)
    print('-' * len(hdr))
    for f in range(1, field_count() + 1):
        lo = P['FIELD_SPAN'] * (f - 1) + 1
        hi = P['FIELD_SPAN'] * f
        mo = monster(hi)
        gr = grade_of(hi)
        cells = []
        for g in [gr - 1, gr, gr + 1, 0]:
            if g > P['GRADE_COUNT']:
                cells.append('%11s' % '-')
                continue
            pl = player(hi, grade=max(g, 1), gear=1.0 if g > 0 else 0.0)
            cells.append(_grp(pl, mo))
        u = unlocks_grade(lo, hi)
        print('%3d %4d~%-4d %5d %5s %7.1fx %5s | %s'
              % (f, lo, hi, gr, ('등급%d' % u) if u else '', dps_mult(gr),
                 job_in(lo, hi), ' | '.join(cells)))

    print()
    print('등급 해금 시점 (보간 %s): 해금 레벨에서 갈아입으면 몬스터는 아직 이전 등급 기준이라 확 강해지고,'
          % ('ON' if P['GEAR_INTERP'] else 'OFF'))
    print('구간 끝(다음 해금 직전)에 기준이 따라잡는다 → 30레벨에 걸친 사이클')
    for g in range(2, P['GRADE_COUNT'] + 1):
        L = equip_level(g)
        L2 = min(P['MAX_LEVEL'], L + P['GRADE_LV_SPAN'] - 1)
        print('  등급%d Lv%-3d  이전등급 %s   갈아입고 %s   ->  Lv%-3d %s'
              % (g, L, _grp(player(L, grade=g - 1), monster(L)),
                 _grp(player(L, grade=g), monster(L)), L2,
                 _grp(player(L2, grade=g), monster(L2))))

    print()
    print('정예/보스는 1:1 전투이므로 타수로 본다. 보스는 설계 보류 — 아래 값은 임시.')
    print('정예 HPx%.0f ATKx%.1f / 보스 HPx%.0f ATKx%.1f'
          % (ROLES['elite']['hp'], ROLES['elite']['atk'],
             ROLES['boss']['hp'], ROLES['boss']['atk']))
    hdr2 = '%3s %5s %12s %11s | %-22s | %-22s' % (
        '#', '레벨', '일반 HP', '일반 ATK', '정예 TTK/TTD', '보스 TTK/TTD')
    print(hdr2)
    print('-' * len(hdr2))
    for f in [1, 5, 10, 15, 20]:
        L = P['FIELD_SPAN'] * f
        pl = player(L)
        row = []
        for role in ['elite', 'boss']:
            mo = monster(L, role)
            h, s1, h2, s2, _, _ = fight(pl, mo)
            row.append('%3d타(%4.0fs)/%3d타(%4.0fs)' % (h, s1, h2, s2))
        mon = monster(L)
        print('%3d %5d %12s %11s | %s' % (f, L, fmt(mon['hp']), fmt(mon['atk']), ' | '.join(row)))

    print()
    print('레벨/등급 차이: Lv100 기준 플레이어(등급%d 강화%d단)가 다른 사냥터 그룹을 만났을 때'
          % (grade_of(100), P['ENH_REF_STEP']))
    pl = player(100)
    for dl in [-30, -20, -10, 0, 10, 20, 30]:
        ML = 100 + dl
        mo = monster(ML)
        _, ct, hits = group_clear(pl, mo)
        loss = hp_loss(pl, mo, ct)
        print('  몬스터 Lv%-3d (사냥터 %2d): 1마리 %2d타  그룹 정리 %5.1f초  HP 손실 %4.0f%%%s'
              % (ML, field_of(ML), hits, ct, loss * 100, '  <- 사망' if loss >= 1.0 else ''))


# ---------------------------------------------------------------- 레벨 상세
def levels():
    print('레벨별 상세 (그 레벨 착용 가능 최고 등급 풀세트 + 강화 %d단). 감소율 목표 %.0f%%'
          % (P['ENH_REF_STEP'], P['TARGET_REDUCE'] * 100))
    print('기준등급 = 몬스터 역산에 쓰이는 보간된 등급 (내 착용 등급보다 낮으면 그만큼 유리)')
    hdr = '%4s %5s %9s %10s %9s %9s %11s %10s %7s %14s %5s' % (
        'Lv', '등급', '기준등급', 'HP', 'ATK', 'DEF', '몬스터HP', '몬스터ATK',
        '감소율', '그룹정리/HP손실', '전직')
    print(hdr)
    print('-' * len(hdr))
    for L in [1, 10, 20, 31, 41, 60, 81, 91, 100, 121, 140, 161, 180, 200]:
        pl = player(L)
        mo = monster(L)
        k = K(L)
        red = pl['df'] / (k + pl['df'])
        print('%4d %5d %9.2f %10s %9s %9s %11s %10s %6.0f%% %14s %5s' % (
            L, pl['grade'], ref_grade(L), fmt(pl['hp']), fmt(pl['atk']), fmt(pl['df']),
            fmt(mo['hp']), fmt(mo['atk']), red * 100, _grp(pl, mo), job_of(L)))


# ---------------------------------------------------------------- 직업
def classes():
    L = 100
    print('직업별 전투력 (Lv%d, 등급 %d 풀세트 + 강화 %d단). power = DPS x 생존시간, 기준직업=1'
          % (L, grade_of(L), P['ENH_REF_STEP']))
    mo = monster(L)
    ref = player(L)
    _, _, _, _, d, d2 = fight(ref, mo)
    ref_power = (d / ref['interval']) * (ref['hp'] / d2)
    print('%-8s %10s %9s %9s %9s %9s %7s  %s' % (
        'class', 'HP', 'ATK', 'DEF', '공격간격', 'DPS', 'power', '그룹정리/HP손실'))
    for c in ['ref'] + list(CLASSES):
        pl = player(L, c)
        _, _, _, _, d, d2 = fight(pl, mo)
        print('%-8s %10s %9s %9s %8.2fs %9s %7.2f  %s' % (
            c, fmt(pl['hp']), fmt(pl['atk']), fmt(pl['df']), pl['interval'],
            fmt(d / pl['interval']), (d / pl['interval']) * (pl['hp'] / d2) / ref_power,
            _grp(pl, mo)))


if __name__ == '__main__':
    a = sys.argv
    if '--drops' in a:
        drops()
    elif '--growth' in a:
        growth_curve()
    elif '--enh' in a:
        enhance()
    elif '--exp' in a:
        expcurve()
    elif '--grades' in a:
        grades()
    elif '--items' in a:
        items()
    elif '--class' in a:
        classes()
    elif '--levels' in a:
        levels()
    else:
        fields()
