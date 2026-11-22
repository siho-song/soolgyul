"""Asks a catalog database's label word search for every unit, as the app
asks it: the words read (each two neighbours also joined, three letters or
more, not numbers) and the drinks the line search found. A tune unit also
asks for its own drink, so the models learn from it when the words missed it.
The answers are what the models are trained and graded on.

Usage: python3 ask_db.py <postgres connection string>
  e.g. postgresql://postgres@127.0.0.1:54329/lab (a copy of the catalog with
  the label word search migration applied). Writes .cache/rows.json.gz."""
import gzip, json, os, re, subprocess, sys, tempfile

from fold import words

HERE = os.path.dirname(os.path.abspath(__file__))
UNITS = f'{HERE}/../data/match_units.json.gz'
OUT = f'{HERE}/.cache/rows.json.gz'


def lit(s):
    return "'" + s.replace("'", "''") + "'"


def ids_named(names, each):
    """The listed drinks named so, years left off, at most `each` a name."""
    if not names: return 'array[]::uuid[]'
    return (f"array(select picked.id from unnest(array[{','.join(lit(n) for n in names)}]::text[]) as wanted(name) "
            f"cross join lateral (select item.id from public.alcohol_items as item "
            f"where item.publish_status = 'published' and regexp_replace(btrim(item.name_ko), '\\s+(?:19|20)\\d\\d$', '') = wanted.name "
            f"order by item.id limit {each}) as picked)")


def statement(u):
    tokens = []
    for line in u['lines']:
        ws = words(line[0])
        for j, w in enumerate(ws):
            tokens.append(w)
            if j + 1 < len(ws): tokens.append(w + ws[j + 1])
    asked = list(dict.fromkeys(t for t in tokens if len(t) >= 3 and not t.isdigit()))[:120]
    found = list(dict.fromkeys(n for x in u.get('app', []) for n in x['names']))
    own = u['truth'] if u['split'] == 'tune' else []
    also = f"({ids_named(found, 2)} || {ids_named(own, 3)})[1:40]"
    return (f"select jsonb_build_object('id', {lit(u['id'])}, 'rows', coalesce((select jsonb_agg(t) from "
            f"public.soolgyul_search_alcohol_catalog_by_label_words(array[{','.join(lit(w) for w in asked)}]::text[], "
            f"{also}, 300) t), '[]'::jsonb))::text;")


def main():
    units = json.load(gzip.open(UNITS, 'rt'))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write('\\set QUIET on\n' + '\n'.join(statement(u) for u in units) + '\n')
    lines = subprocess.run(['psql', '-At', '-v', 'ON_ERROR_STOP=1', '-f', f.name, sys.argv[1]],
                           check=True, capture_output=True, text=True).stdout.splitlines()
    os.unlink(f.name)
    rows = {}
    for line in lines:
        o = json.loads(line)
        rows[o['id']] = o['rows']
    json.dump(rows, gzip.open(OUT, 'wt'), ensure_ascii=False, separators=(',', ':'))
    print(len(rows), 'units,', sum(len(v) for v in rows.values()), 'rows')


if __name__ == '__main__':
    main()
