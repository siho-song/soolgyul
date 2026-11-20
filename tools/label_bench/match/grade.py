"""Grades the label match on the check units beside the app's line search
as it is, and sets the app's port (match_stage.dart output) against the
Python models' decisions on the same rows.

Usage: python3 grade.py [.cache/dart_out.json]"""
import gzip, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
units = {u['id']: u for u in json.load(gzip.open(f'{HERE}/../data/match_units.json.gz', 'rt'))}
dart = json.load(open(sys.argv[1] if len(sys.argv) > 1 else f'{HERE}/.cache/dart_out.json'))
python = json.load(open(f'{HERE}/.cache/python_out.json'))


def line_first(u):
    found = [x for x in u['app'] if x['first'] and x['names']]
    return found[0] if found else None


def grade(st):
    us = [u for u in units.values() if u['split'] == 'check' and u['set'] == st and u['answer'] in ('same', 'absent', 'sibling')]
    known = [u for u in us if u['answer'] == 'same']; absent = [u for u in us if u['answer'] != 'same']
    def new(u):
        d = dart.get(u['id']) or {'drinks': [], 'state': 'none'}
        return (bool(d['drinks']) and d['drinks'][0] in u['truth']), d['state'] == 'sure'
    def old(u):
        f = line_first(u)
        return (bool(f) and f['names'][0] in u['truth']), bool(f and f['sure'])
    rows = []
    for way in (old, new):
        got = {u['id']: way(u) for u in us}
        sure = [u for u in us if got[u['id']][1]]
        hit = sum(u['answer'] == 'same' and got[u['id']][0] for u in sure)
        rows.append((sum(got[u['id']][0] for u in known) / len(known), hit / max(1, len(sure)), hit / len(known),
                     sum(u in absent for u in sure) / len(absent)))
    brand = sum((dart.get(u['id']) or {}).get('state') == 'brand' for u in us)
    return rows, brand, len(known), len(absent)


print('| | 한 병: 지금 | 한 병: 새 방식 | 여러 병: 지금 | 여러 병: 새 방식 |\n|---|---|---|---|---|')
one, cut = grade('one'), grade('cut')
for i, name in enumerate(['1등 정답', '확실 정확도', '확실로 맞힘', '없는 술을 확실이라고 함']):
    print(f'| {name} | {one[0][0][i]:.1%} | {one[0][1][i]:.1%} | {cut[0][0][i]:.1%} | {cut[0][1][i]:.1%} |')
print(f'| 브랜드만 확실 | - | {one[1]}장 | - | {cut[1]}장 |')
print(f'사진: 한 병 있는 술 {one[2]} · 없는 술 {one[3]}, 여러 병 있는 술 {cut[2]} · 없는 술 {cut[3]}')
both = [u for u in python if u in dart and python[u]['drinks'] and dart[u]['drinks']]
first = sum(python[u]['drinks'][0] == dart[u]['drinks'][0] for u in both) / len(both)
state = sum(python[u]['state'] == dart[u]['state'] for u in both) / len(both)
print(f'앱 코드와 학습 쪽이 같은 판단: 1등 {first:.1%}, 상태 {state:.1%} ({len(both)}장)')
