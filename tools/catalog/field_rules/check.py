"""상품 필드 규칙 점검기.

로컬 작업본(manual-import/fill-work/rows.sqlite3)의 상품과 감각 행을 다섯 묶음의
규칙에 대어 보고, 어기는 행을 세고 목록으로 남긴다. 규칙은 RULES 표가 정본이다.

    python -m tools.catalog.field_rules.check                 # 요약 표
    python -m tools.catalog.field_rules.check --rule I2       # 한 규칙의 행 목록
    python -m tools.catalog.field_rules.check --write         # 보고서와 CSV 저장
    python -m tools.catalog.field_rules.check --candidates    # 통일표에 없는 표기 후보

검색은 이름(name_ko·name_en)의 부분 일치와 별칭·검색어의 전체 일치만 본다
(soolgyul_search_alcohol_catalog). 그래서 이름 표기가 흔들리면 검색이 바로 흔들린다.
"""
from __future__ import annotations

import argparse
import collections
import csv
import datetime
import json
import re
import sqlite3
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from tools.catalog.dictionary import project as dictionary

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DB = ROOT / "manual-import/fill-work/rows.sqlite3"
DEFAULT_OUT = ROOT / "manual-import/fill-work/field-rules"
SPELLINGS = Path(__file__).with_name("spellings.json")

LEVELS = (
    "sweetness", "acidity", "bitterness", "astringency", "body", "carbonation",
    "aroma_intensity", "finish_length", "finish_cleanliness",
)
TAG_FIELDS = ("aroma_tags", "palate_tags", "finish_tags")
KEY_FIELDS = ("ingredient_keys", "production_process_keys", "grape_variety_keys")
# 주종별로 있을 법한 도수 범위. 밖이면 자료 오류나 주종 오류를 의심한다.
ABV_MAX = 80  # 주종별 범위는 두지 않는다 (2026-10-26 결정): 무알코올 0도, 모주 1.5도, 아이스복 32도, 75도 증류 소주가 다 정상이다
SPARKLING_STYLES = {"sparkling_wine"}


@dataclass(frozen=True)
class Rule:
    id: str
    group: str
    kind: str  # 위반 | 보강 | 결정
    title: str
    fix: str


RULES = [
    # 식별·검색
    Rule("I1", "식별·검색", "위반", "이름은 앞뒤·겹친 공백이 없고 한글이 있고 NFKC 정규형이다",
         "공백을 정리하고, 한글 이름이 없으면 한글 표기를 붙인다"),
    Rule("I2", "식별·검색", "위반", "이름에 쉼표가 없다 ('생산자, 제품' 꼴 금지)",
         "쉼표를 빈칸으로 바꾼다. 쉼표가 있으면 '생산자 제품'으로 친 검색이 이름에 닿지 않는다"),
    Rule("I3", "식별·검색", "위반", "이름에 용량·도수가 들어가지 않는다 (전통주·중국술처럼 도수가 이름인 주종, 같은 생산자의 다른 도수 제품을 가르는 '56도', 무알코올 '0%'는 예외)",
         "용량은 이름에서 빼고, 도수는 abv_percent로 옮기고 이름에서 뺀다"),
    Rule("I4", "식별·검색", "위반", "이름의 외래어 표기는 통일표(spellings.json)의 정본, 곧 시장에서 가장 흔한 표기를 쓴다 (2026-10-26 결정)",
         "이름을 정본 표기로 바꾼다 (검색은 소리 접기로 옛 표기를 찾는다)"),
    Rule("I5", "식별·검색", "위반", "영문 이름은 글자열이고 한글이 없고 공백이 정리돼 있다",
         "한글이 든 영문 이름은 비우거나 영문 표기를 찾아 넣는다"),
    Rule("I8", "식별·검색", "위반", "같은 생산자·같은 정규화 이름·같은 빈티지·같은 용량인 상품은 하나다",
         "같은 병이면 합치고, 다른 병이면 이름에 구분자를 넣는다"),
    Rule("I13", "식별·검색", "위반", "영문 이름은 쉼표 없이 낱말 첫 글자 대문자다 (전부 대문자·전부 소문자 금지, 약자 XO·IPA는 예외)", "쉼표를 빼고 Title Case로 맞춘다 (2026-10-26 결정)"),
    Rule("I10", "식별·검색", "위반", "머리글자 뒤에는 띄어 쓴다 ('제임스 E. 페퍼', 'E.페퍼' 금지)", "점 뒤에 빈칸을 넣는다"),
    Rule("I11", "식별·검색", "위반", "같은 생산자의 같은 줄 상품은 앞부분 띄어쓰기가 같다 ('264 청포도 와인 꽃'과 '264청포도와인 광야' 금지)", "다수 표기로 맞춘다"),
    Rule("I12", "식별·검색", "위반", "영문 이름에 없는 '에디션'·'X향'을 덧붙이지 않는다 ('1715 보드카 애플', 'Seri Long Distance'에 에디션 없음)", "군더더기를 뺀다 (2026-10-26 결정)"),
    Rule("I9", "식별·검색", "위반", "이름 속 빈티지·연산은 vintage_year·age_statement_years와 같다",
         "이름의 숫자를 필드에 옮기거나, 필드가 맞으면 이름을 고친다"),
    # 분류
    Rule("C1", "분류", "위반", "style_key는 사전에 있고 주종과 맞는다", "사전의 키로 바꾼다"),
    Rule("C2", "분류", "위반", "원료·공정·분류 키는 사전에 있다",
         "사전에 없는 키는 사전의 키로 바꾸거나 지운다 (과일은 apple_fruit·berry_fruit·tropical_fruit_material 같은 사전 키로; 감·오미자 키는 추가 예정, 2026-10-26 결정)"),
    Rule("C3", "분류", "위반", "키 배열 안에 같은 키가 두 번 없다", "겹친 키를 지운다"),
    # 숫자
    Rule("N1", "숫자", "위반", "도수는 0~80 사이다 (주종별 범위는 두지 않는다, 2026-10-26 결정)", "자료를 다시 보고 도수를 고친다"),
    Rule("N2", "숫자", "보강", "도수가 있으면 출처(abv_source)가 있다", "출처를 적는다"),
    Rule("N3", "숫자", "위반", "빈티지 1900~올해, 연산 1~100 정수", "값을 다시 본다"),
    Rule("N4", "숫자", "위반", "국가는 ISO 두 글자 대문자다", "국가를 채우거나 형식을 맞춘다"),
    Rule("N5", "숫자", "위반", "생산자 키가 있다", "생산자를 찾아 넣는다"),
    Rule("N6", "숫자", "위반", "산지는 사전 산지 표(type region, 부모 연결)의 key다; 산지 문자열은 없다",
         "산지 문자열을 지우고 사전의 산지 행 key를 넣는다. 행이 없으면 사전에 부모와 함께 추가한다"),
    # 감각
    Rule("S1", "감각", "위반", "9축 숫자와 level_sources의 출처가 짝을 이룬다", "출처 없는 숫자는 지우거나 출처를 적는다"),
    Rule("S2", "감각", "위반", "향·맛·끝맛·질감 태그는 향 나무(catalog.json)의 키다",
         "어휘 밖 태그(한글, 빈값, 옛 키)는 어휘의 키로 바꾸거나 지운다"),
    Rule("S3", "감각", "위반", "탄산 숫자는 스파클링 계열에만 있다", "스틸 와인의 탄산 숫자를 지운다"),
]
RULE_BY_ID = {r.id: r for r in RULES}

# 위반이 아니라 수집으로 채울 빈칸. 4번(수집 우선순위)의 입력이다.
GAPS = [
    ("abv_percent", "도수"), ("country_code", "국가"),
    ("name_en", "영문 이름"), ("region_key", "산지"), ("grape_variety_keys", "포도 품종(와인)"),
    ("aroma_tags", "향 태그"),
]


def norm(text: str | None) -> str:
    text = unicodedata.normalize("NFKC", text or "").lower()
    return re.sub(r"[^0-9a-z가-힣]+", "", text)


@dataclass
class Vocab:
    styles: dict[str, str]
    categories: set[str]
    ingredients: set[str]
    processes: set[str]
    descriptors: set[str]
    regions: set[str]
    spellings: dict[str, list[str]]
    ignored_tokens: set[str]
    _variant_patterns: list[tuple[str, str, re.Pattern[str]]] | None = field(default=None, init=False, repr=False, compare=False)

    def variant_patterns(self) -> list[tuple[str, str, re.Pattern[str]]]:
        """(정본, 변형, 패턴). 낱말 경계에서만 본다: '샤도네'가 '샤도네이' 안에서, '카레'가 '카레라' 안에서 걸리지 않게.
        check()가 호출될 때마다 다시 컴파일하지 않도록 한 번만 만든다."""
        if self._variant_patterns is None:
            self._variant_patterns = [
                (canon, v, re.compile(r"(?<![가-힣])" + re.escape(v) + r"(?![가-힣])"))
                for canon, vs in self.spellings.items() for v in vs
            ]
        return self._variant_patterns

    @classmethod
    def load(cls) -> "Vocab":
        t = dictionary.view("taxonomy")
        tree = dictionary.view("catalog")
        spellings = json.loads(SPELLINGS.read_text(encoding="utf-8"))
        return cls(
            styles={s["style_key"]: s["category_key"] for s in t["primary_styles"]},
            categories={c["category_key"] for c in t["categories"]},
            ingredients={x["ingredient_key"] for x in t["ingredients"]["terms"]},
            processes={x["term_key"] for x in t["production"]["process_terms"]}
            | {x["term_key"] for x in t["production"]["maturation_terms"]},
            descriptors={d["key"] for d in tree["descriptors"]}
            | {f["key"] for f in tree["families"]}
            | {x["key"] for x in tree["textures"]}
            | {x["key"] for x in tree["finish_characters"]},
            regions={t["key"] for t in dictionary.load()["terms"] if t["type"] == "region"},
            spellings={k: v for k, v in spellings.items() if not k.startswith("_")},
            ignored_tokens=set(spellings.get("_ignore", [])),
        )


@dataclass
class Report:
    rows: int = 0
    hits: dict[str, list[tuple[str, str, str]]] = field(default_factory=lambda: collections.defaultdict(list))
    gaps: collections.Counter = field(default_factory=collections.Counter)
    gap_base: collections.Counter = field(default_factory=collections.Counter)
    spelling: collections.Counter = field(default_factory=collections.Counter)

    def hit(self, rule: str, item: dict, detail: str = "") -> None:
        self.hits[rule].append((item["id"], item.get("name_ko") or "", detail))

    def count(self, rule: str) -> int:
        return len({i for i, _, _ in self.hits.get(rule, [])})


def load_rows(db: Path):
    conn = sqlite3.connect(db)
    for (current,) in conn.execute("select current from products"):
        yield json.loads(current)


# 전통주는 도수가 이름의 일부다 (화요 41, 밀담 24도). 무알코올 '0%'도 이름이다. (2026-10-26)
ABV_IN_NAME_KINDS = {"korean_traditional"}
ABV_IN_NAME_COUNTRIES = {"KR", "CN", "TW"}  # 한국·중국 술은 분류와 관계없이 도수가 이름의 일부다
FLAVOR_WORDS = {"사과": "apple", "청사과": "(green )?apple", "배": "pear", "페어": "pear", "매실": "plum", "피치": "peach", "복숭아": "peach", "애플": "apple",
                "라즈베리": "raspberr", "망고": "mango", "시트론": "citron", "라무네": "ramune", "상그리아": "sangria", "멜론": "melon", "블루베리": "blueberr", "레몬": "lemon",
                "자몽": "grapefruit", "포도": "grape", "딸기": "strawberr", "라임": "lime", "오렌지": "orange", "체리": "cherr", "바닐라": "vanilla", "유자": "yuja|yuzu|citron"}
ABV_SUFFIX = re.compile(r"\s*(?<![\d.])\d{1,2}(\.\d)?\s*(%|도)(?=\s|$)")


def abv_siblings(rows) -> collections.Counter:
    """(생산자, 도수를 뗀 이름)별 상품 수. 2 이상이면 '홍성 이과두주 56도/42도'처럼 도수가 이름의 구분자다."""
    c: collections.Counter = collections.Counter()
    for row in rows:
        it = row["item"]
        if it.get("publish_status") != "published":
            continue
        c[(it.get("producer_key"), norm(ABV_SUFFIX.sub("", it.get("name_ko") or "")))] += 1
    return c


def check(rows, vocab: Vocab, this_year: int | None = None) -> Report:
    if this_year is None:
        this_year = datetime.date.today().year  # N3: 빈티지는 올해를 넘지 못한다
    rows = list(rows)  # load_rows는 제너레이터라 두 번 돌려면 담아 둬야 한다
    siblings = abv_siblings(rows)
    line_names: dict = collections.defaultdict(list)  # 생산자별 (상품, 이름): I11 같은 줄 띄어쓰기
    rep = Report()
    identity: dict[tuple, list[str]] = collections.defaultdict(list)
    variant_patterns = vocab.variant_patterns()
    for row in rows:
        it = row["item"]
        if it.get("publish_status") != "published":
            continue  # 내린 상품은 아무 데도 안 보이니 세지 않는다
        rep.rows += 1
        ck = it["category"]["category_key"]
        sk = it.get("style_key")
        name = it.get("name_ko") or ""
        # --- 식별·검색
        if name != name.strip() or "  " in name:
            rep.hit("I1", it, "공백")
        if not re.search(r"[가-힣]", name) and not all(
            re.fullmatch(r"[A-Z0-9][A-Z0-9&!.+/-]{0,5}|\d+|[+&]", tok) for tok in name.split()
        ):  # 'DVO', 'DDD 19' 같은 머리글자 상표는 라틴 문자로 둔다 (2026-10-26 표기 정책)
            rep.hit("I1", it, "한글 없음")
        if unicodedata.normalize("NFKC", name) != name:
            rep.hit("I1", it, "전각 문자")
        if re.search(r"(?<!\d),|,(?!\d)", name):  # 숫자 사이 쉼표(듀벨 6,66)는 이름의 일부
            rep.hit("I2", it, name)
        if re.search(r"\d+(\.\d+)?\s*(ml|mL|ML|L)\b", name):
            rep.hit("I3", it, "용량")
        if (ABV_SUFFIX.search(name) and not re.search(r"%\s*오프", name)
                and ck not in ABV_IN_NAME_KINDS and not (it.get("country_code") in ABV_IN_NAME_COUNTRIES and ck != "wine")
                and not re.search(r"(?<![\d.])0\s*%", name)
                and siblings[(it.get("producer_key"), norm(ABV_SUFFIX.sub("", name)))] < 2):
            rep.hit("I3", it, "도수")
        for canon, variant, pat in variant_patterns:
            if pat.search(name):
                rep.hit("I4", it, f"{variant} → {canon}")
                rep.spelling[(canon, variant)] += 1
        en = it.get("name_en")
        if en is not None and not isinstance(en, str):
            rep.hit("I5", it, f"글자열 아님: {en!r}")
        elif isinstance(en, str):
            if re.search(r"[가-힣]", en):
                rep.hit("I5", it, f"한글: {en}")
            if en != en.strip() or "  " in en:
                rep.hit("I5", it, "공백")
        n_name = norm(name)
        identity[(it.get("producer_key"), n_name, it.get("vintage_year"))].append(it["id"])
        # 1950~2029만 빈티지로 본다. '구이디 1929' 같은 창립 연도는 걸러진다.
        year = re.search(r"(?<!\d)(19[5-9]\d|20[0-2]\d)(?!\d)", name)
        vintage = it.get("vintage_year")
        if ck != "wine":  # 위스키·사케의 네 자리 수는 출시·증류 연도이지 빈티지가 아니다
            year = None
        if year and vintage is None and int(year.group(0)) < 1990:  # 상점 목록에 1990년 전 빈티지는 드물다. '신스 1974', '산 파트리냐뇨 1978'은 상표다
            year = None
        if year and not name.endswith(year.group(0)):  # '맥기건 빈 2000 쉬라즈', '구이디 1929 …'처럼 이름 가운데 수는 상표다
            year = None
        if year and vintage is None:
            rep.hit("I9", it, f"이름 빈티지 {year.group(0)}, 필드 없음")
        elif year and vintage is not None and int(year.group(0)) != vintage:
            rep.hit("I9", it, f"이름 {year.group(0)} ≠ 필드 {vintage}")
        age = re.search(r"(?<!\d)(\d{1,2})\s*년(?![산\d])", name)
        if age and not re.fullmatch(r".*\d{1,2}\s*년\s*(올드)?", name):  # '70년 올드 바인'처럼 가운데 수는 연산이 아니다
            age = None
        years = it.get("age_statement_years")
        if age and years is None:
            rep.hit("I9", it, f"이름 연산 {age.group(1)}년, 필드 없음")
        elif age and years is not None and int(age.group(1)) != int(years):
            rep.hit("I9", it, f"이름 {age.group(1)}년 ≠ 필드 {years}")
        if re.search(r"\b[A-Z]\.[가-힣]", name):
            rep.hit("I10", it, name)
        en_raw = it.get("name_en")
        if isinstance(en_raw, str) and en_raw:
            en_letters = re.sub(r"[^A-Za-z]", "", en_raw)
            all_short = all(len(re.sub(r"[^A-Za-z]", "", tok)) <= 4 for tok in en_raw.split())  # 'B3 GSM', 'BLK + BLU' 같은 약자 상표
            one_word = len(en_raw.split()) == 1  # '4elementa' 같은 한 낱말 상표
            if "," in en_raw or (len(en_letters) >= 4 and not all_short and not one_word and (en_letters.isupper() or en_letters.islower())):
                rep.hit("I13", it, en_raw)
        en_name = str(it.get("name_en") or "")
        if en_name:
            if "에디션" in name and not re.search(r"edi|addition|release|limit|ed\.", en_name, re.I):
                rep.hit("I12", it, "에디션")
            m_fl = re.search(r"(?<![가-힣])([가-힣]+)향(?![가-힣])", name)
            if m_fl and m_fl.group(1) in FLAVOR_WORDS and re.search(FLAVOR_WORDS[m_fl.group(1)], en_name, re.I) and not re.search(r"flavou?r|aroma|scent", en_name, re.I):
                rep.hit("I12", it, f"{m_fl.group(0)}")
        line_names[it.get("producer_key")].append((it, name))
        # --- 분류
        if sk not in vocab.styles:
            rep.hit("C1", it, f"모르는 style_key {sk}")
        elif vocab.styles[sk] != ck:
            rep.hit("C1", it, f"{sk}는 {vocab.styles[sk]}인데 주종이 {ck}")
        for f_, allowed in (("ingredient_keys", vocab.ingredients), ("production_process_keys", vocab.processes)):
            for k in it.get(f_) or []:
                if k not in allowed:
                    rep.hit("C2", it, f"{f_}: {k}")
        for f_ in KEY_FIELDS:
            v = it.get(f_) or []
            if len(v) != len(set(v)):
                rep.hit("C3", it, f_)
        # --- 숫자
        abv = it.get("abv_percent")
        if abv is not None:
            if not 0 <= float(abv) <= ABV_MAX:
                rep.hit("N1", it, f"{ck} {abv}")
            if not it.get("abv_source"):
                rep.hit("N2", it, str(abv))
        if vintage is not None and not 1900 <= vintage <= this_year:
            rep.hit("N3", it, f"빈티지 {vintage}")
        if years is not None and (not 0 < years <= 100 or float(years) != int(years)):
            rep.hit("N3", it, f"연산 {years}")
        cc = it.get("country_code")
        if not cc:
            rep.hit("N4", it, "없음")
        elif not re.fullmatch(r"[A-Z]{2}", cc):
            rep.hit("N4", it, cc)
        if not it.get("producer_key"):
            rep.hit("N5", it)
        if it.get("region"):
            rep.hit("N6", it, f"문자열 {it['region']}")
        elif it.get("region_key") and it["region_key"] not in vocab.regions:
            rep.hit("N6", it, it["region_key"])
        # --- 감각
        sources = row.get("level_sources") or {}
        for d in LEVELS:
            v = row.get(d)
            if v is not None and d not in sources:
                rep.hit("S1", it, f"{d} 출처 없음")
            if v is None and d in sources:
                rep.hit("S1", it, f"{d} 숫자 없음")
        for f_ in TAG_FIELDS:
            for k in row.get(f_) or []:
                if k not in vocab.descriptors:
                    rep.hit("S2", it, f"{f_}: {k!r}")
        if row.get("carbonation") is not None and ck == "wine" and sk not in SPARKLING_STYLES:
            rep.hit("S3", it, f"{sk} carbonation={row['carbonation']}")
        # --- 빈칸
        for f_, _ in GAPS:
            if f_ == "grape_variety_keys" and ck != "wine":
                continue
            rep.gap_base[f_] += 1
            v = row.get(f_) if f_ == "aroma_tags" else it.get(f_)
            if v in (None, "", [], {}):
                rep.gaps[f_] += 1
    for key, ids in identity.items():
        if len(ids) > 1:
            for id_ in ids:
                rep.hits["I8"].append((id_, key[1], f"{len(ids)}개: " + ", ".join(ids)))
    for producer, members in line_names.items():
        if not producer or len(members) < 2:
            continue
        bare = {m[1]: re.sub(r"\s+", "", m[1]) for m in members}
        for i in range(len(members)):
            for j in range(i + 1, len(members)):
                a, b = members[i][1], members[j][1]
                if a == b:
                    continue
                ba, bb = bare[a], bare[b]
                k = 0
                while k < min(len(ba), len(bb)) and ba[k] == bb[k]:
                    k += 1
                if k < 5 or not re.search(r"[가-힣]", ba[:k]):
                    continue
                # 공백 뺀 앞부분 k글자까지의 '띄어쓰기 포함 꼴'이 서로 다르면 위반 (낱말 경계에서 끝나는 경우만)
                def spaced(nm):
                    acc = ""
                    for pos, ch in enumerate(nm):
                        if not ch.isspace():
                            acc += ch
                        if len(acc) == k:
                            return nm[:pos + 1] if pos + 1 == len(nm) or nm[pos + 1].isspace() else None
                    return None
                fa, fb = spaced(a), spaced(b)
                if fa and fb and fa != fb:
                    rep.hit("I11", members[i][0], f"{fa!r} vs {fb!r}")
                    break
    return rep


# --- 표기 후보 찾기: 된소리·예사소리, ㅐ/ㅔ, ㅛ/ㅗ 같은 모음 짝, '르'·'이' 삽입, 받침 차이를 접어 같은 낱말끼리 모은다.
_CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
_JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
_JONG = " ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"
_PLAIN = {"ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ", "ㅋ": "ㄱ", "ㅌ": "ㄷ", "ㅍ": "ㅂ", "ㅊ": "ㅈ"}
_VOWEL = {
    "ㅐ": "ㅔ", "ㅒ": "ㅔ", "ㅖ": "ㅔ", "ㅙ": "ㅔ", "ㅚ": "ㅔ", "ㅞ": "ㅔ",
    "ㅝ": "ㅓ", "ㅕ": "ㅓ", "ㅢ": "ㅣ", "ㅟ": "ㅣ", "ㅛ": "ㅗ", "ㅠ": "ㅜ",
}


def sound_key(token: str) -> str:
    out: list[str] = []
    for ch in token:
        o = ord(ch) - 0xAC00
        if not 0 <= o < 11172:
            out.append(ch)
            continue
        a, b, d = _CHO[o // 588], _JUNG[(o % 588) // 28], _JONG[o % 28].strip()
        a, b = _PLAIN.get(a, a), _VOWEL.get(b, b)
        if a == "ㄹ" and b == "ㅡ" and not d:
            continue  # 까베르네/까베네
        if a == "ㅇ" and b == "ㅣ" and not d and out:
            continue  # 도멘/도메인
        d = "" if d in ("ㅅ", "ㅆ", "ㅌ", "ㅍ", "ㅋ") else d
        out.append(a + b + d)
    return "".join(out)


def search_fold(text: str) -> str:
    """검색용 접기: 공백·문장부호를 빼고 소문자로 만든 뒤 소리 키를 만든다.

    DB의 soolgyul_fold_korean_sound와 글자 하나까지 같아야 한다
    (supabase/functions/_tests/fixtures/korean_sound_fold.json으로 맞춘다).
    """
    base = unicodedata.normalize("NFC", text or "").lower().translate(_LATIN_ACCENTS)
    # 일본어 가나·한자(와 々 〆 ー)는 라벨의 원어 브랜드명 검색을 위해 그대로 남긴다.
    base = re.sub(r"[^0-9a-z가-힣぀-ゟァ-ヺー一-鿿々〆]+", "", base)
    return sound_key(base)


# 라틴 악센트 접기 (DB 함수의 translate 표와 같은 순서·내용).
_LATIN_ACCENTS = str.maketrans(
    "àáâäãåçèéêëìíîïñòóôöõøùúûüýÿ",
    "aaaaaaceeeeiiiinoooooouuuuyy",
)


def spelling_candidates(rows, vocab: Vocab, min_total: int = 15, min_minor: int = 3) -> list[str]:
    """Token clusters that look like one word spelled differently and are not in spellings.json yet."""
    known = set(vocab.spellings) | {v for vs in vocab.spellings.values() for v in vs} | vocab.ignored_tokens
    words = [w for w in known if len(w) >= 3 and " " not in w]

    def covered(token: str) -> bool:
        # '까베르네쇼비뇽'처럼 표에 있는 낱말을 품은 토큰은 그 낱말의 규칙이 이미 잡는다.
        return token in known or any(w in token for w in words)
    counts: collections.Counter = collections.Counter()
    pairs: collections.Counter = collections.Counter()
    for row in rows:
        tokens = [t for t in re.split(r"[\s,()\[\]/·\-]+", row["item"].get("name_ko") or "") if re.fullmatch(r"[가-힣]{2,}", t)]
        for t in set(tokens):
            counts[t] += 1
        for a, b in set(zip(tokens, tokens[1:])):
            pairs[(a, b)] += 1
    groups: dict[str, dict[str, int]] = collections.defaultdict(dict)
    for t, n in counts.items():
        if n >= min_minor and not covered(t):
            groups[sound_key(t)][t] = n
    lines = ["== 같은 낱말로 보이는 표기 (표에 없는 것; 같은 낱말이 맞는지 보고 spellings.json에 넣는다)"]
    found = []
    for members in groups.values():
        if len(members) < 2:
            continue
        total, top = sum(members.values()), max(members.values())
        if total >= min_total and total - top >= min_minor:
            found.append((total, members))
    for total, members in sorted(found, key=lambda x: -x[0]):
        lines.append(f"{total:6d}  " + "  ".join(f"{t}({n})" for t, n in sorted(members.items(), key=lambda x: -x[1])))
    lines.append("== 띄어쓰기가 갈리는 두 낱말 (표에 없는 것)")
    for (a, b), n in sorted(pairs.items(), key=lambda x: -x[1]):
        joined = a + b
        m = counts.get(joined, 0)
        if m >= min_minor and n >= min_minor and n + m >= min_total and not covered(joined) and f"{a} {b}" not in known:
            lines.append(f"{n + m:6d}  '{a} {b}'({n})  vs  '{joined}'({m})")
    return lines


def summary_lines(rep: Report) -> list[str]:
    lines = ["| 규칙 | 묶음 | 성격 | 규칙 | 어기는 상품 | 고치는 법 |", "|---|---|---|---|---:|---|"]
    for r in RULES:
        lines.append(f"| {r.id} | {r.group} | {r.kind} | {r.title} | {rep.count(r.id):,} | {r.fix} |")
    lines += ["", "빈칸(위반이 아니라 수집 대상):", "", "| 필드 | 빈 상품 | 비율 |", "|---|---:|---:|"]
    for f_, label in GAPS:
        base = rep.gap_base[f_] or 1
        lines.append(f"| {label} | {rep.gaps[f_]:,} | {rep.gaps[f_] * 100 // base}% |")
    if rep.spelling:
        lines += ["", "표기 통일표에 걸린 이름:", "", "| 정본 | 지금 표기 | 상품 |", "|---|---|---:|"]
        for (canon, variant), n in sorted(rep.spelling.items(), key=lambda x: -x[1]):
            lines.append(f"| {canon} | {variant} | {n:,} |")
    return lines


SHEET_HEAD = """# 상품 필드 규칙과 점검 (2026-10-26)

상품 한 병이 가진 필드 40개를 다섯 묶음으로 나누고, 묶음마다 지켜야 할 규칙을 한 줄씩 적은 표예요.
규칙의 정본은 코드(`tools/catalog/field_rules/check.py`의 RULES)이고, 이 문서는 거기서 뽑은 거예요.
숫자는 로컬 작업본(`manual-import/fill-work/rows.sqlite3`)을 점검기로 센 값이에요.

**왜 이름 규칙이 검색 규칙인가.** 지금 라이브 검색(`soolgyul_search_alcohol_catalog`)은 딱 두 가지만 봐요.
한글·영문 이름의 **부분 일치**, 그리고 별칭·검색어의 **전체 일치**예요. 그래서 이름에 쉼표가 있으면
'생산자 제품'으로 친 검색이 닿지 않고, 같은 품종을 '까베르네'와 '카베르네'로 다르게 적으면 한쪽만 나와요.
2026-10-26에 만든 migration(20261026090000, 아직 로컬)은 질의와 이름을 같은 소리 규칙으로 접어서 비교하니
퀴숑/뀌숑처럼 사용자가 다르게 쳐도 찾아요. 그래도 이름 표기는 하나로 맞춰 두는 게 맞아요. 화면에 보이는 이름이고,
접기가 못 잡는 차이(ㅛ/ㅗ, 다른 낱말)도 있으니까요.

**성격 세 가지.** `위반`은 규칙을 어긴 것이라 고치면 돼요. `보강`은 출처처럼 있어야 하지만 자료를 더 봐야
채울 수 있는 것. `결정`은 어느 쪽으로 할지 사용자가 정해야 하는 것이에요.

## 다섯 묶음

| 묶음 | 들어가는 필드 | 한 줄 원칙 |
|---|---|---|
| 식별·검색 | name_ko, name_en, producer_key, vintage_year, age_statement_years | 검색이 보는 이름 둘은 한 표기법으로, 같은 병은 하나로 |
| 분류 | category, style_key, ingredient_keys, production_process_keys, grape_variety_keys | 값은 사전(`catalog/dictionary/terms.json`, catalog_taxonomy)에 있는 키만 |
| 숫자 | abv_percent(+source, range), price, country_code, region | 값·출처·범위가 한 세트, 주종의 있을 법한 범위 안 |
| 감각 | 9축 숫자, level_sources, 세 태그 | 읽은 값만, 태그는 향 나무 안에서 |
| 출처·작업 메모 | source_ids, identity_notes, price_observations, official_note, *_source, *_url | 서빙 표에 올리지 않고 로컬에만 둠 |

## 규칙과 지금 상태

"""

SHEET_WORK = """

## 결정이 필요한 것

- ~~I4 표기 정본~~ **정해짐(2026-10-26): 시장에서 가장 흔한 표기.** 우리 카탈로그의 다수 표기로 확인했어요(예: 까베르네·쉬라즈·샤또·꼬뜨·뀌베·키안티·피노 누아·싱글몰트). 통일표는 품종·산지·등급·생산자 낱말 830개 남짓이에요. 이름 전체를 소리 기준으로 묶어 1,500여 묶음을 하나씩 판정해서 만든 표라, 2026-10-26 기준으로 남은 후보는 없어요. 이름을 바꾸고 원래 표기는 별칭에 남겨요. 표에 없는 새 묶음은 `--candidates`로 뽑아 같은 낱말인지 사람이 보고 넣어요. 소리는 같아도 다른 낱말(피노/비노, 보데가/보테가, 마고/마르코)은 넣지 않아요.
- ~~N6 산지~~ **정해짐(2026-10-29): 산지는 사전의 산지 표 행(부모 연결)을 key로 가리킨다.** 나라 행이 뿌리이고 단계 수는 주종마다 다르다(와인 나라>광역>세부, 위스키 나라>스코틀랜드>지역, 사케 일본>도도부현, 전통주 한국>시도>시군구). 섬 이름은 '섬' 없이 적는다.
- ~~P2 감각 행의 publish_status~~ **정해짐(2026-10-26): 열을 없앤다.** 읽는 곳이 없었고 공개 여부는 상품의 publish_status 하나로만 본다 (마이그레이션 20261026120000).
- ~~C2 과일 원료~~ **정해짐(2026-10-26): 사전에 이미 있는 과일 키(apple_fruit·berry_fruit·cherry_fruit·tropical_fruit_material)로 바꿔 끼운다.** 감·오미자는 새 키를 넣고(사전 파일은 수집 세션 작업 뒤), 양파는 키 없이 비운다.

## 반복 작업 순서 (다른 세션)

1. `python3 -m tools.catalog.field_rules.check --write` 로 `manual-import/fill-work/field-rules/violations.csv`를 뽑아요. 표기(I4)는 `--candidates`로 표에 없는 묶음을 먼저 보고, 같은 낱말이 맞으면 `spellings.json`에 다수 표기를 정본으로 넣은 뒤 돌려요.
2. 영향이 큰 순서로 고쳐요: I2 쉼표 → I3 이름 속 용량·도수 → I9 이름 속 숫자와 필드 → I4 표기 통일(5,751) → I5·I1 공백·한글 → S2·S3 태그·탄산 → N1·N4·N5 숫자 → C2 사전 밖 키 → I8 중복.
3. 바꾸기 전 백업(`rows.before-field-rules-<날짜>.sqlite3`), 로컬에만 적용, 원격은 사용자가 말할 때.
4. 한 묶음 끝날 때마다 점검기를 다시 돌려 그 줄이 0이 되는지 봐요. 결정 항목은 2026-10-26에 모두 정해졌어요 (N1 느슨한 범위, N6 산지 표 key, C2 사전 키, P2 열 삭제).
"""


def write_sheet(rep: Report, path: Path) -> None:
    path.write_text(SHEET_HEAD + "\n".join(summary_lines(rep)) + SHEET_WORK, encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--db", type=Path, default=DEFAULT_DB)
    p.add_argument("--rule", help="한 규칙의 행 목록만 본다 (예: I2)")
    p.add_argument("--limit", type=int, default=30)
    p.add_argument("--write", action="store_true", help="보고서(report.md)와 위반 목록(violations.csv)을 저장한다")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT)
    p.add_argument("--sheet", type=Path, help="규칙 한 장(설명+현황)을 이 경로에 쓴다")
    p.add_argument("--candidates", action="store_true", help="통일표에 아직 없는 표기 후보 묶음을 보여 준다")
    a = p.parse_args(argv)
    vocab = Vocab.load()
    if a.candidates:
        print("\n".join(spelling_candidates(load_rows(a.db), vocab)))
        return 0
    rep = check(load_rows(a.db), vocab)
    if a.rule:
        r = RULE_BY_ID[a.rule.upper()]
        print(f"{r.id} {r.title} — {rep.count(r.id):,}개")
        for id_, name, detail in rep.hits.get(r.id, [])[: a.limit]:
            print(f"  {id_}  {name}  {detail}")
        return 0
    print(f"상품 {rep.rows:,}개 점검")
    print("\n".join(summary_lines(rep)))
    if a.write:
        a.out.mkdir(parents=True, exist_ok=True)
        (a.out / "report.md").write_text(
            f"# 상품 필드 규칙 점검 결과\n\n상품 {rep.rows:,}개, 로컬 작업본 기준.\n\n" + "\n".join(summary_lines(rep)) + "\n",
            encoding="utf-8",
        )
        with (a.out / "violations.csv").open("w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["rule", "group", "kind", "id", "name_ko", "detail"])
            for r in RULES:
                for id_, name, detail in rep.hits.get(r.id, []):
                    w.writerow([r.id, r.group, r.kind, id_, name, detail])
        print(f"\n저장: {a.out / 'report.md'}, {a.out / 'violations.csv'}")
    if a.sheet:
        write_sheet(rep, a.sheet)
        print(f"규칙 한 장: {a.sheet}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
