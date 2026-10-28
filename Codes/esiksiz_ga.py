import time
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import sparse

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data"
SON = KOK / "Results"
FV = VERI / "figur_verileri"
TOHUM = 20261026
B_BOOT = 8000
PARCA = 1000
T_BAS = time.time()

h = pd.read_parquet(VERI / "hane_2023_2025.parquet")
te = h[h["yil"] == 2025].copy().reset_index(drop=True)
skorlar = pd.read_parquet(VERI / "ml" / "skorlar_2025.parquet")
assert (skorlar["hane_kimlik"].values == te["hane_kimlik"].values).all()
mlp = pd.read_parquet(VERI / "ml" / "mlp_skorlar_2025.parquet").set_index("hane_kimlik")
for k in mlp.columns:
    skorlar[k] = te["hane_kimlik"].map(mlp[k]).values
y = te["FI"].values.astype(float)
w = te["HB040"].values.astype(float)
n_te = len(te)
rng = np.random.default_rng(TOHUM + 7)
M = np.zeros((n_te, B_BOOT), dtype=np.int16)
for b in range(B_BOOT):
    M[:, b] = np.bincount(rng.integers(0, n_te, n_te - 1), minlength=n_te)
WB = (w[:, None] * M * (n_te / (n_te - 1))).astype(np.float64)
del M
temiz = te["test_temiz"].values == 1
POP_M = {"A": np.ones(n_te, dtype=bool), "B": te["yoksul"].values == 0}
gelir_skor = -te["goreli_esdeger_gelir"].values.astype(float)


def expit(z):
    return 1 / (1 + np.exp(-z))


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def grup_matris(skor):
    u, inv = np.unique(-skor, return_inverse=True)
    return sparse.csr_matrix((np.ones(len(skor)), (inv, np.arange(len(skor)))), shape=(len(u), len(skor)))


def auc_b(skor, yy, Wb):
    u, inv = np.unique(skor, return_inverse=True)
    A = sparse.csr_matrix((np.ones(len(skor)), (inv, np.arange(len(skor)))), shape=(len(u), len(skor)))
    W1g = A @ (Wb * yy[:, None])
    W0g = A @ (Wb * (1 - yy)[:, None])
    c0 = np.cumsum(W0g, axis=0) - W0g
    return (W1g * (c0 + 0.5 * W0g)).sum(0) / (W1g.sum(0) * W0g.sum(0))


def ap_b(skor, yy, Wb):
    A = grup_matris(skor)
    Wg = A @ Wb
    W1g = A @ (Wb * yy[:, None])
    cw = np.cumsum(Wg, axis=0)
    prec = np.where(cw > 0, np.cumsum(W1g, axis=0) / np.where(cw > 0, cw, 1), 0)
    return (W1g / W1g.sum(0) * prec).sum(0)


def brier_b(p, yy, Wb):
    return ((p - yy) ** 2) @ Wb / Wb.sum(0)


def kal_b(p, yy, Wb):
    z = logit(p)
    kesim, egim, it_en = [], [], 0
    for j0 in range(0, Wb.shape[1], PARCA):
        W = Wb[:, j0:j0 + PARCA]
        a = np.zeros(W.shape[1])
        b = np.zeros(W.shape[1])
        for it in range(100):
            mu = expit(a[None, :] + z[:, None] * b[None, :])
            r = W * (yy[:, None] - mu)
            v = W * mu * (1 - mu)
            ga, gb = r.sum(0), z @ r
            haa, hab, hbb = v.sum(0), z @ v, (z ** 2) @ v
            det = haa * hbb - hab ** 2
            da, db = (hbb * ga - hab * gb) / det, (haa * gb - hab * ga) / det
            a += da
            b += db
            if max(np.abs(da).max(), np.abs(db).max()) < 1e-10:
                break
        it_en = max(it_en, it + 1)
        assert max(np.abs(da).max(), np.abs(db).max()) < 1e-10
        k = np.zeros(W.shape[1])
        for it in range(100):
            mu = expit(z[:, None] + k[None, :])
            st = (W * (yy[:, None] - mu)).sum(0) / (W * mu * (1 - mu)).sum(0)
            k += st
            if np.abs(st).max() < 1e-12:
                break
        it_en = max(it_en, it + 1)
        assert np.abs(st).max() < 1e-12
        kesim.append(k)
        egim.append(b)
    return np.concatenate(kesim), np.concatenate(egim), it_en


def kalibrasyon(p, yy, ww):
    z = logit(p)
    b = np.zeros(2)
    X = np.column_stack([np.ones_like(z), z])
    for _ in range(50):
        mu = 1 / (1 + np.exp(-(X @ b)))
        st = np.linalg.solve(X.T @ (X * (ww * mu * (1 - mu))[:, None]), X.T @ (ww * (yy - mu)))
        b += st
        if np.max(np.abs(st)) < 1e-10:
            break
    a = 0.0
    for _ in range(50):
        mu = 1 / (1 + np.exp(-(z + a)))
        st = np.sum(ww * (yy - mu)) / np.sum(ww * mu * (1 - mu))
        a += st
        if abs(st) < 1e-12:
            break
    return {"kalibrasyon_kesim": a, "kalibrasyon_egim": b[1], "OE": np.sum(ww * yy) / np.sum(ww * p)}


def kal_egri(p, yy, ww, k=10):
    o = np.argsort(p)
    cw = np.cumsum(ww[o]) / ww.sum()
    grp = np.minimum((cw * k).astype(int), k - 1)
    out = []
    for g in range(k):
        i = o[grp == g]
        out.append({"dilim": g + 1, "tahmin": np.sum(ww[i] * p[i]) / ww[i].sum(), "gozlenen": np.sum(ww[i] * yy[i]) / ww[i].sum(), "n": len(i)})
    return out


def ga(x):
    return float(np.percentile(x, 2.5)), float(np.percentile(x, 97.5))


eski = pd.read_csv(SON / "H2_esiksiz_metrikler.csv").query("sema == 'temiz'").set_index(["nufus", "kol"])
satir = []
bm = {}
for pop in ("A", "B"):
    m = temiz & POP_M[pop]
    yy, W, ww = y[m], WB[m], w[m]
    kollar = [k for k in skorlar.columns if k != "hane_kimlik" and ("B" if "_B" in k else "A") == pop and not k.endswith("_2023")]
    for kol in kollar:
        p = skorlar[kol].values[m]
        assert not np.isnan(p).any(), kol
        ab, apb, brb = auc_b(p, yy, W), ap_b(p, yy, W), brier_b(p, yy, W)
        kb, eb, it_en = kal_b(p, yy, W)
        nk = kalibrasyon(p, yy, ww)
        r = {"sema": "temiz", "nufus": pop, "kol": kol, "n": int(m.sum()), "olay": int(yy.sum()), "B": B_BOOT,
             "auc": float(auc_b(p, yy, ww[:, None])[0]), "pr_auc": float(ap_b(p, yy, ww[:, None])[0]), "brier": float(brier_b(p, yy, ww[:, None])[0]), **nk}
        r["auc_alt"], r["auc_ust"] = ga(ab)
        r["pr_auc_alt"], r["pr_auc_ust"] = ga(apb)
        r["brier_alt"], r["brier_ust"] = ga(brb)
        r["kalibrasyon_kesim_alt"], r["kalibrasyon_kesim_ust"] = ga(kb)
        r["kalibrasyon_egim_alt"], r["kalibrasyon_egim_ust"] = ga(eb)
        r["newton_en_cok_yineleme"] = it_en
        r["kaynak"] = "mlp.py tahminleri" if kol.startswith("mlp_") else "skorlar_2025 (ml.py)"
        if (pop, kol) in eski.index:
            e = eski.loc[(pop, kol)]
            for c in ("auc", "auc_alt", "auc_ust", "pr_auc", "pr_auc_alt", "pr_auc_ust", "brier", "brier_alt", "brier_ust", "kalibrasyon_kesim", "kalibrasyon_egim"):
                assert abs(r[c] - e[c]) < 1e-10, (pop, kol, c, r[c], e[c])
        satir.append(r)
        bm[(pop, kol)] = (kb, eb)
        print(f"[{(time.time() - T_BAS) / 60:5.1f} dk] {pop} {kol}: kesim {r['kalibrasyon_kesim']:.3f} ({r['kalibrasyon_kesim_alt']:.3f}, {r['kalibrasyon_kesim_ust']:.3f}), egim {r['kalibrasyon_egim']:.3f} ({r['kalibrasyon_egim_alt']:.3f}, {r['kalibrasyon_egim_ust']:.3f})", flush=True)
    if pop == "A":
        s = gelir_skor[m]
        r = {"sema": "temiz", "nufus": pop, "kol": "gelir_sirasi", "n": int(m.sum()), "olay": int(yy.sum()), "B": B_BOOT,
             "auc": float(auc_b(s, yy, ww[:, None])[0]), "pr_auc": float(ap_b(s, yy, ww[:, None])[0]), "kaynak": "goreli esdeger gelir"}
        r["auc_alt"], r["auc_ust"] = ga(auc_b(s, yy, W))
        r["pr_auc_alt"], r["pr_auc_ust"] = ga(ap_b(s, yy, W))
        satir.append(r)
sonuc = pd.DataFrame(satir)
mlp_eski = pd.read_csv(SON / "H2_mlp.csv").set_index("set")
for s in ("A1", "A2"):
    r = sonuc[sonuc["kol"] == f"mlp_{s}"].iloc[0]
    for c in ("auc", "brier", "OE", "kalibrasyon_egim"):
        assert abs(r[c] - mlp_eski.loc[s, c]) < 1e-6, (s, c)
sonuc.to_csv(SON / "H2_esiksiz_metrikler_GA.csv", index=False)

S2B = ("lgb_A1", "logit_lin_A1", "l1_T1T2", "lgb_A2")
m = temiz
egri = []
for kol in S2B:
    r = sonuc[(sonuc["nufus"] == "A") & (sonuc["kol"] == kol)].iloc[0]
    for d in kal_egri(skorlar[kol].values[m], y[m], w[m]):
        egri.append({"kol": kol, **d, "kalibrasyon_kesim": r["kalibrasyon_kesim"], "kalibrasyon_kesim_alt": r["kalibrasyon_kesim_alt"], "kalibrasyon_kesim_ust": r["kalibrasyon_kesim_ust"],
                     "kalibrasyon_egim": r["kalibrasyon_egim"], "kalibrasyon_egim_alt": r["kalibrasyon_egim_alt"], "kalibrasyon_egim_ust": r["kalibrasyon_egim_ust"]})
pd.DataFrame(egri).to_csv(FV / "figS2b_kalibrasyon_2025.csv", index=False)
print(f"esiksiz_ga.py bitti, {(time.time() - T_BAS) / 60:.1f} dk; satir {len(sonuc)}", flush=True)
