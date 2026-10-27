import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
from joblib import Parallel, delayed
from scipy.stats import norm

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data"
SIM = VERI / "simulasyon"
SON = KOK / "Results"
ISCI = 16
TOHUM0 = 20261101
T_BAS = time.time()
bilgi = json.loads((SIM / "simulasyon_bilgi.json").read_text(encoding="utf-8"))
S_S3, B_S3 = int(bilgi["S_S3"]), int(bilgi["B_S3"])


def expit(z):
    return 1 / (1 + np.exp(-z))


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def kesim_kalibre(p, y, w):
    a = 0.0
    z = logit(p)
    for _ in range(50):
        mu = expit(z + a)
        st = np.sum(w * (y - mu)) / np.sum(w * mu * (1 - mu))
        a += st
        if abs(st) < 1e-12:
            break
    return expit(z + a)


h = pd.read_parquet(VERI / "hane_2023_2025.parquet")
h25 = h[h["yil"] == 2025].reset_index(drop=True)
sk = pd.read_parquet(VERI / "ml" / "skorlar_2025.parquet")
te = h25.merge(sk, on="hane_kimlik", how="left")
y = te["FI"].values.astype(float)
w = te["HB040"].values.astype(float)
yoksul = te["yoksul"].values.astype(float)
p_gercek = kesim_kalibre(te["lgb_A1"].values, y, w)
cart = te["cart_T2"].values
cs = np.sort(np.unique(cart))[::-1]
pay_kum = np.array([np.sum(w[cart >= c]) / w.sum() for c in cs])
c_pov_hepsi = float(np.sum(w * yoksul) / w.sum())
kural_esik = cs[np.argmax(pay_kum >= c_pov_hepsi)]
assert abs(float(kural_esik) - bilgi["kural_esik_S3"]) < 1e-12
bayrak = (cart >= kural_esik).astype(float)
gercek = {"dislama_hatasi": np.sum(w * p_gercek * (1 - yoksul)) / np.sum(w * p_gercek), "kural_duyarlilik": np.sum(w * p_gercek * bayrak) / np.sum(w * p_gercek),
          "kural_ppv": np.sum(w * p_gercek * bayrak) / np.sum(w * bayrak)}
n = len(y)
z_ = norm.ppf([0.025, 0.975])


def s3_aralik(s):
    rng = np.random.default_rng(TOHUM0 + 500000 + s)
    ix = rng.integers(0, n, n)
    ww = w[ix]
    yy = (rng.uniform(size=n) < p_gercek[ix]).astype(float)
    pv = yoksul[ix]
    fl = bayrak[ix]
    M = np.zeros((n, B_S3), dtype=np.float32)
    for b in range(B_S3):
        M[:, b] = np.bincount(rng.integers(0, n, n - 1), minlength=n)
    M *= n / (n - 1)
    a1, a2, a3, a4 = ww * yy * (1 - pv), ww * yy, ww * yy * fl, ww * fl
    oranlar = {"dislama_hatasi": (a1, a2), "kural_duyarlilik": (a3, a2), "kural_ppv": (a3, a4)}
    out = []
    for k, (pay, payda) in oranlar.items():
        th = pay.sum() / payda.sum()
        bt = (pay @ M) / (payda @ M)
        tj = (pay.sum() - pay) / (payda.sum() - payda)
        dj = tj.mean() - tj
        a_ = np.sum(dj ** 3) / (6 * np.sum(dj ** 2) ** 1.5)
        z0 = norm.ppf((np.sum(bt < th) + 0.5 * np.sum(bt == th)) / len(bt))
        q = np.percentile(bt, [2.5, 97.5])
        qb = np.percentile(bt, 100 * norm.cdf(z0 + (z0 + z_) / (1 - a_ * (z0 + z_))))
        g = gercek[k]
        for yontem, (lo, hi) in (("yuzdelik", q), ("basic", (2 * th - q[1], 2 * th - q[0])), ("BCa", qb)):
            out.append({"s": s, "olcu": k, "yontem": yontem, "tahmin": 100 * th, "alt": 100 * lo, "ust": 100 * hi, "gercek": 100 * g, "kapsadi": int(lo <= g <= hi),
                        "gercek_altta": int(g < lo), "gercek_ustte": int(g > hi), "z0": z0, "ivme": a_})
    return out


ham = pd.DataFrame([x for o in Parallel(n_jobs=ISCI, backend="loky")(delayed(s3_aralik)(s) for s in range(S_S3)) for x in o])
eski = pd.read_csv(SIM / "S3_ham.csv").set_index(["s", "olcu"])
yz = ham[ham["yontem"] == "yuzdelik"].set_index(["s", "olcu"])
esit = float(np.max(np.abs(yz[["tahmin", "alt", "ust"]].values - eski.loc[yz.index, ["tahmin", "alt", "ust"]].values)))
assert esit < 1e-9, esit
ham.to_csv(SIM / "S3_aralik_ham.csv", index=False)
oz = ham.assign(genislik=ham["ust"] - ham["alt"]).groupby(["olcu", "yontem"], sort=False).agg(
    gercek=("gercek", "first"), kapsama=("kapsadi", "mean"), gercek_altta=("gercek_altta", "mean"), gercek_ustte=("gercek_ustte", "mean"),
    ortalama_genislik=("genislik", "mean"), ortalama_z0=("z0", "mean"), ortalama_ivme=("ivme", "mean"), S=("s", "nunique")).reset_index()
for k in ("kapsama", "gercek_altta", "gercek_ustte"):
    oz[k] = 100 * oz[k]
oz["kapsama_mcse"] = np.sqrt(oz["kapsama"] * (100 - oz["kapsama"]) / oz["S"])
oz["B"] = B_S3
oz.to_csv(SON / "S3_aralik_kapsamasi.csv", index=False)
print(f"yuzdelik sinirlar S3_ham.csv ile ayni (en buyuk fark {esit:.2e})")
print(oz.round(3).to_string())
print(f"sure (dk): {(time.time() - T_BAS) / 60:.2f}")
