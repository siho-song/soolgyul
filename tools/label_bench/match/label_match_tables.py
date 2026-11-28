"""Writes lib/src/features/taste_fit/data/label_match_tables.g.dart: what
the label match needs to compare text as the models learned it.

- How each character folds: Unicode compatibility decomposition, marks off,
  lower case (so "Ｃｈâｔｅａｕ" is "chateau" and "が" is "か"), for every
  character whose fold Dart's lower case alone does not give.
- The words that say what kind of drink a label is ("single", "brut"),
  which say little of which drink: the dictionary's label words and kinds.
- Each grape's names, by the grape key the catalog gives a drink.

Usage: python3 tools/label_bench/match/label_match_tables.py"""
import os, re, subprocess, sys

from fold import KEEP, fold, words

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, ROOT)
from tools.catalog.dictionary import project  # noqa: E402

OUT = f'{ROOT}/lib/src/features/taste_fit/data/label_match_tables.g.dart'
# Words the models were taught as kind words beside the dictionary's.
MORE_KIND_WORDS = ['single', 'malt', 'scotch', 'whisky', 'whiskey', 'bourbon', 'blended', 'aged', 'years', 'year', 'old',
                   'wine', 'red', 'white', 'the', 'de', 'di', 'la', 'le', 'du', 'and', 'of', 'y', 'et', '와인', '레드',
                   '화이트', '위스키']


DART_MARKS = [(0x300, 0x36f), (0x1ab0, 0x1aff), (0x1dc0, 0x1dff), (0x20d0, 0x20ff), (0xfe20, 0xfe2f), (0x3099, 0x309a)]


def dart_fold(s):
    """What label_match.dart makes of s without the table: marks of its
    few ranges off, lower case, then as fold() goes on."""
    s = ''.join('' if any(a <= ord(c) <= b for a, b in DART_MARKS) else c.lower() for c in s)
    s = s.replace('’', "'").replace("'", '')
    return KEEP.sub(' ', s).strip()


def char_folds():
    """Each character the table must give: what it folds to between two
    letters, where that differs from what Dart makes of it alone."""
    out = {}
    for code in range(0x80, 0x10000):
        if 0xD800 <= code <= 0xDFFF: continue
        c = chr(code)
        want = fold('a' + c + 'b')
        if want != dart_fold('a' + c + 'b'): out[code] = want[1:-1]
    return out


def dart_string(s):
    return "'" + s.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"


def dictionary_words():
    """The kind words, and each grape's folded names by grape key."""
    dic = project.load()['drinks']
    kind_words = set(MORE_KIND_WORDS)
    grapes = {}
    for k in project.DRINKS:
        for w in dic[k].get('label_words') or []:
            for x in [w.get('label'), w.get('ko'), *(w.get('find') or [])]:
                if x and not re.search(r'\d', x): kind_words.update(words(x))
        for kd in dic[k].get('kinds') or []:
            for x in [kd.get('en'), kd.get('ko'), kd.get('label')] if isinstance(kd, dict) else []:
                if x: kind_words.update(words(x))
        for g in dic[k].get('grapes') or []:
            grapes.setdefault(g['key'], set()).update(
                f for f in (fold(x) for x in [g.get('label'), g.get('ko'), *(g.get('find') or [])] if x) if f)
    return kind_words, grapes


def main():
    kind_words, grapes = dictionary_words()
    folds = char_folds()
    lines = ['// Written by tools/label_bench/match/label_match_tables.py; not edited by hand.', '',
             '/// Each character whose fold is more than its lower case: its letters', '/// once decomposed, marks off.',
             'const Map<int, String> labelMatchCharFolds = <int, String>{']
    lines += [f'  {code}: {dart_string(f)},' for code, f in sorted(folds.items())]
    lines += ['};', '', '/// Words that say what kind of drink a label is, not which.',
              'const Set<String> labelMatchKindWords = <String>{']
    lines += [f'  {dart_string(w)},' for w in sorted(kind_words)]
    lines += ['};', '', "/// Each grape's names, folded, by grape key.",
              'const Map<String, List<String>> labelMatchGrapeNames = <String, List<String>>{']
    lines += [f"  {dart_string(k)}: <String>[{', '.join(dart_string(x) for x in sorted(v))}]," for k, v in sorted(grapes.items())]
    lines += ['};', '']
    open(OUT, 'w').write('\n'.join(lines))
    subprocess.run(['dart', 'format', OUT], check=True, capture_output=True)
    print(len(folds), 'characters,', len(kind_words), 'kind words,', len(grapes), 'grapes')


if __name__ == '__main__':
    main()
