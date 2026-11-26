"""Trains the label match's two models and writes them for the app.

- The ranker: gradient-boosted trees on what measures.py measures of each
  candidate, plus each one's distance below the unit's best on four of them;
  learned from the tune units' drinks.
- The sure decision: logistic regression on the ranker's first drink (its
  score, its lead, how much of its name was read, ...), learned from ranker
  scores on photos the ranker did not learn from; its threshold is the
  least whose sure answers are right TARGET of the time on those photos.

Grades both on the check units beside the app's line search, then writes
lib/src/features/taste_fit/data/label_match_model.g.dart, the test fixture
test/fixtures/label_match.json, and .cache/python_out.json (each unit's
decision, for grade.py to set the app's port against).

The whole run, from a catalog database with the label word search:
  python3 label_match_tables.py      # when the dictionary changed
  python3 ask_db.py <connection>     # .cache/rows.json.gz
  python3 measures.py                # .cache/measures.pkl
  python3 train.py                   # models, fixture
  dart run tools/label_bench/match_stage.dart   # the app's port on the same rows
  python3 grade.py
Needs numpy, scikit-learn and rapidfuzz."""
import gzip, json, os, pickle, subprocess, zlib
import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.linear_model import LogisticRegression

from fold import fold

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
MODEL = f'{ROOT}/lib/src/features/taste_fit/data/label_match_model.g.dart'
FIXTURE = f'{ROOT}/test/fixtures/label_match.json'
FEATURES = ['mass_exact', 'cov_exact', 'miss_exact', 'maxw_exact', 'mass_ocr', 'cov_ocr', 'miss_ocr', 'maxw_ocr', 'big',
            'producer', 'place', 'grape', 'grape_other', 'abv', 'abv_other', 'age', 'age_other', 'age_unread', 'num', 'num_other', 'num_unread',
            'kind_read', 'kind_other', 'known', 'staple', 'pool', 'app_in', 'app_rank', 'app_first', 'app_sure', 'app_tied']
RELATIVE = ['mass_ocr', 'cov_ocr', 'mass_exact', 'pool']
SURE = ['score', 'lead', 'candidates', 'cut', 'app_sure', 'app_first', 'cov_ocr', 'maxw_ocr', 'producer', 'kind_other',
        'age_other']
TARGET = 0.87  # sure answers right this often: the balance chosen on 2026-11-20
FOLD_CASES = ["Château d'Arche", 'CHÂTEAU MOUTON ROTHSCHILD', 'Ｇｌｅｎ　Ｇｒａｎｔ １２', 'Grant’s', 'Moët & Chandon',
              '純米大吟醸 獺祭', 'がっさん', 'ばくれん', '샤또 마고 2015', 'Viña Errázuriz', 'Côte-Rôtie', 'Ⅻ ½',
              'Œil de Perdrix', 'Weingut Dr. Loosen Ürziger', 'MAÑANA', 'ﬁno', 'ÀÉÎÕÜ', 'Ｃａｙｍｕｓ', '吟醸　ｶﾞｯｻﾝ',
              'Ørsted', 'Straße']

units = {u['id']: u for u in json.load(gzip.open(f'{HERE}/../data/match_units.json.gz', 'rt'))}
measures = pickle.load(open(f'{HERE}/.cache/measures.pkl', 'rb'))
group = lambda uid: uid.split('/')[1].split('_')[0]
fold3 = lambda uid: zlib.crc32(group(uid).encode()) % 3
judged = lambda uid: units[uid]['answer'] in ('same', 'absent', 'sibling') and measures.get(uid)
tune = sorted(u for u in units if units[u]['split'] == 'tune' and judged(u))
check = sorted(u for u in units if units[u]['split'] == 'check' and judged(u))


def vec(rows):
    X = np.array([[m[k] for k in FEATURES] for _, _, m in rows], dtype=float)
    rel = [FEATURES.index(k) for k in RELATIVE]
    return np.hstack([X, X[:, rel] - X[:, rel].max(axis=0)])


def fit_ranker(uids):
    uids = [u for u in uids if units[u]['answer'] == 'same']
    X = np.vstack([vec(measures[u]) for u in uids])
    y = np.concatenate([[t for _, t, _ in measures[u]] for u in uids])
    return HistGradientBoostingClassifier(max_depth=4, max_iter=200, learning_rate=0.05, l2_regularization=1.0,
                                          random_state=0).fit(X, y)


def sure_input(uid, s, order):
    m = measures[uid][order[0]][2]
    return [s[order[0]], s[order[0]] - (s[order[1]] if len(order) > 1 else 0), len(measures[uid]),
            float(units[uid]['set'] == 'cut'), m['app_sure'], m['app_first'], m['cov_ocr'], m['maxw_ocr'], m['producer'],
            m['kind_other'], m['age_other']]


def right(uid, order):
    return units[uid]['answer'] == 'same' and bool(measures[uid][order[0]][1])


def threshold(p, y, target):
    o = np.argsort(-p); prec = np.cumsum(y[o]) / np.arange(1, len(o) + 1)
    ok = np.where(prec >= target)[0]
    return float(p[o][ok.max()]) if len(ok) else 1.0


# the decision learns from ranker scores on photos the ranker did not learn
Xd, yd = [], []
for k in range(3):
    r = fit_ranker([u for u in tune if fold3(u) != k])
    for u in tune:
        if fold3(u) != k: continue
        s = r.predict_proba(vec(measures[u]))[:, 1]; o = np.argsort(-s, kind='stable')
        Xd.append(sure_input(u, s, o)); yd.append(right(u, o))
Xd, yd = np.array(Xd), np.array(yd)
mu, sd = Xd.mean(0), Xd.std(0) + 1e-9
logistic = lambda: LogisticRegression(C=0.3, max_iter=3000)
oof = np.zeros(len(yd)); folds = np.array([fold3(u) for u in tune])
for k in range(3):
    oof[folds == k] = logistic().fit((Xd[folds != k] - mu) / sd, yd[folds != k]).predict_proba((Xd[folds == k] - mu) / sd)[:, 1]
tau = threshold(oof, yd, TARGET)
decision = logistic().fit((Xd - mu) / sd, yd)
ranker = fit_ranker(tune)


def decide(uid):
    s = ranker.predict_proba(vec(measures[uid]))[:, 1]; o = np.argsort(-s, kind='stable')
    x = sure_input(uid, s, o)
    p = float(decision.predict_proba((np.array([x]) - mu) / sd)[0, 1])
    top = [measures[uid][i][0] for i in o[:3]]
    one_maker = bool(top[0]['producer']) and all(t['producer'] == top[0]['producer'] for t in top)
    state = 'sure' if p >= tau else 'brand' if one_maker and measures[uid][o[0]][2]['producer'] == 1 else 'unsure'
    return {'state': state, 'sureness': p, 'drinks': [measures[uid][i][0]['drink'] for i in o[:5]]}, s, o, x


out = {u: decide(u)[0] for u in units if measures.get(u)}
json.dump(out, open(f'{HERE}/.cache/python_out.json', 'w'), ensure_ascii=False)
print(f'확실 기준 {tau:.3f} (학습 사진에서 확실 정확도 {TARGET:.0%}가 되는 값)')


def num(x):
    return repr(float(x))


def write_model():
    trees = [[[int(n['feature_idx']), float(n['num_threshold']), int(n['left']), int(n['right']), float(n['value']),
               int(n['is_leaf']), int(n['missing_go_to_left'])] for n in t[0].nodes] for t in ranker._predictors]
    names = lambda xs: '<String>[' + ', '.join(f"'{x}'" for x in xs) + ']'
    nums = lambda xs: '<double>[' + ', '.join(num(x) for x in xs) + ']'
    lines = ['// Written by tools/label_bench/match/train.py; not edited by hand.', '',
             '/// What the ranker reads of each candidate, in order; then, for each of',
             '/// [labelRankerRelative], how far the candidate is below the best.',
             f'const List<String> labelRankerFeatures = {names(FEATURES)};',
             f'const List<String> labelRankerRelative = {names(RELATIVE)};', '',
             '/// The trees start from this log-odds.',
             f'const double labelRankerBaseline = {num(ranker._baseline_prediction.ravel()[0])};', '',
             '/// Each tree, seven numbers a node: the feature read, the threshold (a',
             '/// value at most it goes left), the left and right node, the value of a',
             '/// leaf, 1 for a leaf, 1 when a missing value goes left.',
             'const List<List<double>> labelRankerTrees = <List<double>>[']
    lines += ['  ' + nums(x for node in t for x in node) + ',' for t in trees]
    lines += ['];', '', '/// The sure decision: logistic regression on these inputs, scaled.',
              f'const List<String> labelSureInputs = {names(SURE)};',
              f'const List<double> labelSureMean = {nums(mu)};',
              f'const List<double> labelSureScale = {nums(sd)};',
              f'const List<double> labelSureWeights = {nums(decision.coef_[0])};',
              f'const double labelSureBias = {num(decision.intercept_[0])};', '',
              f'/// The first drink is said sure from this probability up: sure answers',
              f'/// were right {TARGET:.0%} of the time from it on photos the models did not learn.',
              f'const double labelSureThreshold = {num(tau)};', '']
    open(MODEL, 'w').write('\n'.join(lines))
    subprocess.run(['dart', 'format', MODEL], check=True, capture_output=True)
    probes, sure = [], []
    for u in check[:8]:
        _, s, o, x = decide(u)
        X = vec(measures[u])
        probes += [{'input': X[i].tolist(), 'score': float(s[i])} for i in range(min(3, len(X)))]
        sure.append({'input': x, 'p': float(decision.predict_proba((np.array([x]) - mu) / sd)[0, 1])})
    json.dump({'folds': {c: fold(c) for c in FOLD_CASES}, 'ranker': probes, 'sure': sure},
              open(FIXTURE, 'w'), ensure_ascii=False, indent=1)


write_model()
print('written', os.path.relpath(MODEL, ROOT), 'and', os.path.relpath(FIXTURE, ROOT))
