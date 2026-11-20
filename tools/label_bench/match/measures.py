"""What the label match measures of each candidate drink, from the rows
the database's label word search answered (ask_db.py): the same measures,
computed the same way, as label_match.dart computes on the phone.

Usage: python3 measures.py  ->  .cache/measures.pkl
  {unit id: [(row, is the unit's drink, {measure: value})]}, one row a drink."""
import gzip, json, math, os, pickle, re
from multiprocessing import Pool

from rapidfuzz import fuzz
from rapidfuzz.distance import Levenshtein

from fold import YEAR, drink_of, fold, words

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
UNITS = f'{HERE}/../data/match_units.json.gz'
ROWS = f'{HERE}/.cache/rows.json.gz'
OUT = f'{HERE}/.cache/measures.pkl'
RAREST = 10.81  # what a word no other name holds says, if the answer lacks it


def _tables():
    """Kind words and grape names as label_match_tables.g.dart holds them."""
    text = open(f'{ROOT}/lib/src/features/taste_fit/data/label_match_tables.g.dart', encoding='utf-8').read()
    kind = text[text.index('labelMatchKindWords'):text.index('labelMatchGrapeNames')]
    grapes = text[text.index('labelMatchGrapeNames'):]
    unq = lambda s: s.encode('latin-1', 'backslashreplace').decode('unicode_escape') if '\\' in s else s
    kind_words = {unq(m) for m in re.findall(r"^  '((?:[^'\\]|\\.)*)',$", kind, re.M)}
    grape_names = {}
    for key, body in re.findall(r"^  '([^']*)': <String>\[(.*)\],$", grapes, re.M):
        grape_names[key] = re.findall(r"'((?:[^'\\]|\\.)*)'", body)
    return kind_words, grape_names


KIND_WORDS, GRAPE_NAMES = _tables()
GRAPE_PHRASES = sorted({p for names in GRAPE_NAMES.values() for p in names if len(p) > 3})
OCR = str.maketrans({'0': 'o', 'q': 'o', 'd': 'o', '1': 'i', 'l': 'i', 'j': 'i', '!': 'i', '|': 'i', '5': 's', '8': 'b',
                     '6': 'g', 'c': 'e', 'u': 'v', 'y': 'v', 'k': 'x', 'h': 'n', 'f': 't', 'z': '2'})
OCR_LEAST = 0.8
KIND_SAID = {
    'whisky': ['whisky', 'whiskey', 'scotch', 'bourbon', 'single malt', 'blended malt', 'rye whiskey', 'distillery', '위스키'],
    'wine': ['wine', 'vin', 'vino', 'wein', 'chateau', 'domaine', 'appellation', 'cuvee', 'vintage', 'doc', 'docg', 'aoc',
             'reserva', 'riserva', 'grand cru', 'champagne', 'brut', 'cabernet', 'merlot', 'chardonnay', 'pinot', 'sauvignon', '와인'],
    'sake': ['sake', 'junmai', 'ginjo', 'daiginjo', '純米', '吟醸', '日本酒', '清酒', '本醸造', '酒造', '사케'],
    'korean_traditional': ['소주', '막걸리', '약주', '탁주', '증류주', '전통주', '청주', 'soju', 'makgeolli'],
}
AGE_READ = re.compile(r'(?<!\d)(\d{1,2})\s*(?:years?|yrs?|yo|y o|ans|anos|anni|jahre|년)(?![0-9a-z぀-ヿ㐀-鿿가-힣])')
# Read off the lines as printed: folding drops the "%".
STRENGTH_READ = re.compile(r'(?<![\d.])(\d{1,2}(?:[.,]\d{1,2})?)\s*%')


def ocr_canon(w):
    return w.replace('rn', 'm').replace('vv', 'w').replace('cl', 'd').translate(OCR)


def height_key(h):
    return int(math.floor(h * 10000 + 0.5))  # as Dart's round()


def tokens(lines):
    out = []
    for line in lines:
        ws = words(line[0])
        for j, w in enumerate(ws):
            out.append((w, height_key(line[4])))
            if j + 1 < len(ws): out.append((w + ws[j + 1], height_key(line[4])))
    return out


def side_measures(names, rarity, read):
    weight = [rarity.get(w, RAREST) * (0.25 if w in KIND_WORDS else 1) for w in names]
    total = sum(weight)
    out = {}
    for way in ('exact', 'ocr'):
        seen = [read(w)[0 if way == 'exact' else 1] for w in names]
        mass = sum(x * s for x, s in zip(weight, seen))
        out[f'mass_{way}'] = mass
        out[f'cov_{way}'] = mass / total if total > 0 else 0
        out[f'miss_{way}'] = total - mass
        out[f'maxw_{way}'] = max((x for x, s in zip(weight, seen) if s > 0), default=0)
    out['big'] = sum(x for x, w in zip(weight, names) if read(w)[2]) / total if total > 0 else 0
    return out


EMPTY_SIDE = {f'{a}_{b}': 0 for a in ('mass', 'cov', 'miss', 'maxw') for b in ('exact', 'ocr')} | {'big': 0}


def unit_measures(u, rows):
    toks = tokens(u['lines'])
    if not toks or not rows: return []
    text = ' ' + ' '.join(fold(l[0]) for l in u['lines']) + ' '
    raw = ' '.join(l[0] for l in u['lines'])
    big = set(sorted({height_key(l[4]) for l in u['lines']}, reverse=True)[:2])
    read_ages = {int(m) for m in AGE_READ.findall(text)}
    read_strengths = [float(x.replace(',', '.')) for x in STRENGTH_READ.findall(raw)]
    read_grapes = {g for g in GRAPE_PHRASES if f' {g} ' in text}
    read_kinds = {k for k, ws in KIND_SAID.items()
                  if any(f' {w} ' in text or (len(w) > 1 and not w.isascii() and w in text) for w in ws)}
    rank, first, sure, tied = {}, set(), set(), set()
    for x in u.get('app', []):
        for r, n in enumerate(x['names']): rank[n] = min(rank.get(n, 9), r)
        if x['names']:
            if x['first']: first.add(x['names'][0])
            if x['sure']: sure.add(x['names'][0])
            if x['tied']: tied.update(x['names'])
    canon_toks = [ocr_canon(w) for w, _ in toks]
    cache = {}

    def read(word):
        if word not in cache:
            exact = ocr = 0.0; in_big = False; canon = ocr_canon(word)
            for (w, h), c in zip(toks, canon_toks):
                if w == word:
                    exact = 1; seen = 1
                elif len(word) > 3 and len(w) > 2:
                    like = Levenshtein.normalized_similarity(canon, c)
                    seen = like if like >= OCR_LEAST else 0
                else:
                    seen = 0
                ocr = max(ocr, seen)
                if seen > 0 and h in big: in_big = True
            cache[word] = (exact, ocr, in_big)
        return cache[word]

    truth = set(u['truth'])
    out = []
    for row in rows:
        facts = row.get('label_facts') or {}
        rarity = row.get('name_rarity') or {}
        best = None
        for name in (row.get('name_en'), row.get('name_ko')):
            ws = words(YEAR.sub('', name or ''))
            if not ws: continue
            side = side_measures(ws, rarity, read)
            if best is None or side['mass_ocr'] > best['mass_ocr']: best = side
        m = dict(best or EMPTY_SIDE)
        producer = sorted({fold(p) for p in facts.get('producer') or [] if fold(p)})
        m['producer'] = float(any(len(p) > 3 and (f' {p} ' in text or fuzz.partial_ratio(p, text) >= 92) for p in producer))
        m['place'] = max((0.5 ** depth for depth, names in enumerate(facts.get('regions') or [])
                          for n in names if len(fold(n)) > 3 and f' {fold(n)} ' in text), default=0)
        own = {p for key in facts.get('grapes') or [] for p in GRAPE_NAMES.get(key, [])}
        m['grape'] = float(bool(own & read_grapes))
        m['grape_other'] = float(bool(read_grapes) and not (own & read_grapes))
        abv = row.get('abv_percent')
        strength = abv is not None and any(abs(s - float(abv)) <= 0.5 for s in read_strengths)
        m['abv'] = float(strength)
        m['abv_other'] = float(abv is not None and bool(read_strengths) and not strength)
        age = facts.get('age')
        age = int(math.floor(age + 0.5)) if age is not None else None
        m['age'] = float(age is not None and age in read_ages)
        m['age_other'] = float(age is not None and bool(read_ages) and age not in read_ages)
        m['age_unread'] = float(age is not None and not read_ages)
        m['kind_read'] = float(row['category_key'] in read_kinds)
        m['kind_other'] = float(bool(read_kinds) and row['category_key'] not in read_kinds)
        m['known'] = float(bool(facts.get('known')))
        m['staple'] = float(bool(facts.get('staple')))
        m['pool'] = float(row.get('found') or 0)
        n = drink_of(row['name_ko'])
        m['app_in'] = float(n in rank)
        m['app_rank'] = 1 / (1 + rank[n]) if n in rank else 0
        m['app_first'] = float(n in first)
        m['app_sure'] = float(n in sure)
        m['app_tied'] = float(n in tied)
        out.append(({'id': row['id'], 'drink': n, 'producer': producer}, n in truth, m))
    # one row a drink: its years are the same drink
    best = {}
    for r in out:
        k = r[0]['drink']
        if k not in best or r[2]['mass_ocr'] + r[2]['abv'] > best[k][2]['mass_ocr'] + best[k][2]['abv']: best[k] = r
    return list(best.values())


def _one(args):
    u, rows = args
    return u['id'], unit_measures(u, rows)


def main():
    units = json.load(gzip.open(UNITS, 'rt'))
    rows = json.load(gzip.open(ROWS, 'rt'))
    with Pool(6) as pool:
        out = dict(pool.imap_unordered(_one, [(u, rows.get(u['id'], [])) for u in units], chunksize=8))
    pickle.dump(out, open(OUT, 'wb'))
    print(len(out), 'units measured')


if __name__ == '__main__':
    main()
