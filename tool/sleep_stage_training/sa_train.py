# HR + wrist-motion sleep stager trained on PhysioNet sleep-accel (Walch 2019,
# ODC-By), evaluated by 5-fold leave-subjects-out. Features mirror what Engine
# has on a WHOOP 4.0: 1 Hz heart rate and a 1 Hz gravity vector.
import json, sys, numpy as np, warnings
warnings.filterwarnings('ignore')
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GroupKFold
from sklearn.metrics import cohen_kappa_score, confusion_matrix

SRC = sys.argv[1]
data = json.load(open(SRC))
STAGE = {0: 0, 1: 1, 2: 1, 3: 2, 4: 2, 5: 3}  # W, light, deep, REM


def roll(v, w, f):
    h = w // 2
    out = np.full(len(v), np.nan)
    for i in range(len(v)):
        s = v[max(0, i - h):i + h + 1]
        s = s[np.isfinite(s)]
        if len(s):
            out[i] = f(s)
    return out


def scale(v):
    ok = np.isfinite(v)
    if ok.sum() < 10:
        return np.full(len(v), np.nan)
    lo, med, hi = np.percentile(v[ok], [5, 50, 95])
    return (v - med) / max(hi - lo, 1e-9)


def night_features(labels, hr, acc):
    lab = np.array(labels, float)
    t0 = lab[0, 0]
    n = len(lab)
    hr = np.array(hr, float)
    acc = np.array(acc, float)
    # 1 Hz HR by interpolation inside 30 s of a sample (Engine's is native 1 Hz)
    sec = np.arange(t0, t0 + n * 30)
    hr1 = np.interp(sec, hr[:, 0], hr[:, 1], left=np.nan, right=np.nan)
    near = np.abs(sec - hr[np.clip(np.searchsorted(hr[:, 0], sec), 0, len(hr) - 1), 0]) < 30
    hr1[~near] = np.nan
    # gravity → z-angle per second
    amap = {int(r[0]): r[1:4] for r in acc}
    ang = np.full(len(sec), np.nan)
    for i, s in enumerate(sec.astype(int)):
        g = amap.get(s)
        if g is not None:
            x, y, z = g
            ang[i] = np.degrees(np.arctan2(z, np.hypot(x, y)))
    dang = np.abs(np.diff(ang, prepend=np.nan))
    E = lambda a, f: np.array([f(a[e * 30:(e + 1) * 30]) for e in range(n)])
    def nanf(f):
        return lambda s: f(s[np.isfinite(s)]) if np.isfinite(s).sum() >= 5 else np.nan
    mot = np.log1p(E(dang, nanf(np.sum)))
    hre = E(hr1, nanf(np.mean))
    hrsd = E(hr1, nanf(np.std))
    hrs = scale(hre)
    t = np.arange(n) / max(n - 1, 1)
    cols = [mot, roll(mot, 5, np.max), roll(mot, 11, np.mean), roll(mot, 21, np.mean),
            hrs, roll(hrs, 5, np.mean), roll(hrs, 11, np.mean), roll(hrs, 21, np.mean),
            scale(roll(hre, 11, np.std)), scale(roll(hre, 21, np.std)), scale(hrsd),
            scale(hre - roll(hre, 21, np.mean)),
            t, np.exp(np.log(0.01) * t), np.sin(np.pi * t)]
    X = np.vstack(cols).T
    y = np.array([STAGE.get(int(s), -1) for s in lab[:, 1]])
    return X, y


Xs, ys, gs = [], [], []
for sid, d in data.items():
    X, y = night_features(d['labels'], d['hr'], d['acc'])
    m = y >= 0
    Xs.append(X[m]); ys.append(y[m]); gs.append(np.full(m.sum(), int(sid)))
X = np.vstack(Xs); y = np.concatenate(ys); g = np.concatenate(gs)
X = np.nan_to_num(X, nan=0.0)
print('epochs', len(y), 'class share', np.bincount(y, minlength=4) / len(y))

for name, mk in [('LR', lambda: LogisticRegression(max_iter=2000, C=0.5)),
                 ('GBT', lambda: GradientBoostingClassifier(n_estimators=150, max_depth=3,
                                                            learning_rate=0.08, subsample=0.8,
                                                            random_state=0))]:
    pred = np.zeros(len(y), int)
    for tr, te in GroupKFold(5).split(X, y, g):
        m = mk().fit(X[tr], y[tr])
        pred[te] = m.predict(X[te])
    per = [cohen_kappa_score(y[g == s], pred[g == s]) for s in np.unique(g)]
    print(name, '4-class kappa pooled', round(cohen_kappa_score(y, pred), 3),
          'median per night', round(float(np.median(per)), 3),
          'sleep/wake', round(cohen_kappa_score(y == 0, pred == 0), 3))
    print(confusion_matrix(y, pred))
