import json
import time
from pathlib import Path

import numpy as np
import pandas as pd
import torch
from torch import nn

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data"
SON = KOK / "Results"
TOHUM = 20261026
T_BAS = time.time()
cihaz = torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")
setler = json.loads((VERI / "ml" / "ozellik_setleri.json").read_text(encoding="utf-8"))
NOMINAL = {"HB030", "HB031", "HB050", "reis_medeni", "reis_calisma7", "HH010", "HH020", "HH080", "HH100", "HH110"}
SIRALI = {"hane_gelir_dilim5", "reis_egitim", "egitim_max", "egitim_min", "reis_saglik", "reis_gali", "HH145"}
h = pd.read_parquet(VERI / "hane_2023_2025.parquet")
h["HB031"] = h["HB031"].astype(str)
h["w"] = h["HB040"] / h.groupby("yil")["HB040"].transform("mean")


def kodla(egit, digerleri, feats):
    sut_e, sut_d = [], [[] for _ in digerleri]
    for v in feats:
        if v in NOMINAL or v in SIRALI:
            kat = sorted(egit[v].dropna().unique().tolist(), key=lambda z: str(z))
            for k in kat + ["bos"]:
                f = (lambda d: d[v].isna()) if k == "bos" else (lambda d, k=k: d[v] == k)
                sut_e.append(f(egit).astype(float).values)
                for i, d in enumerate(digerleri):
                    sut_d[i].append(f(d).astype(float).values)
        else:
            x = egit[v].astype(float)
            med = float(np.nanmedian(x)) if x.notna().any() else 0.0
            ort, ss = float(x.fillna(med).mean()), float(x.fillna(med).std()) or 1.0
            sut_e += [(x.fillna(med).values - ort) / ss, x.isna().astype(float).values]
            for i, d in enumerate(digerleri):
                xd = d[v].astype(float)
                sut_d[i] += [(xd.fillna(med).values - ort) / ss, xd.isna().astype(float).values]
    return np.column_stack(sut_e).astype(np.float32), [np.column_stack(s).astype(np.float32) for s in sut_d]


def ag(p, gizli, birakma):
    katman, onceki = [], p
    for g in gizli:
        katman += [nn.Linear(onceki, g), nn.ReLU(), nn.Dropout(birakma)]
        onceki = g
    katman.append(nn.Linear(onceki, 1))
    return nn.Sequential(*katman)


def egit(X, y, w, konfig, tohum, epok, Xva=None, yva=None, wva=None):
    torch.manual_seed(tohum)
    np.random.seed(tohum)
    m = ag(X.shape[1], konfig["gizli"], konfig["birakma"]).to(cihaz)
    opt = torch.optim.AdamW(m.parameters(), lr=konfig["lr"], weight_decay=konfig["wd"])
    Xt, yt, wt = (torch.tensor(a, device=cihaz) for a in (X, y.astype(np.float32), w.astype(np.float32)))
    kayip = nn.BCEWithLogitsLoss(reduction="none")
    gecmis = []
    rng = np.random.default_rng(tohum)
    for e in range(epok):
        m.train()
        sira = torch.tensor(rng.permutation(len(X)), device=cihaz)
        for i in range(0, len(X), 512):
            ix = sira[i:i + 512]
            opt.zero_grad()
            l = (kayip(m(Xt[ix]).squeeze(1), yt[ix]) * wt[ix]).sum() / wt[ix].sum()
            l.backward()
            opt.step()
        if Xva is not None:
            p = tahmin(m, Xva)
            gecmis.append(float(-np.sum(wva * (yva * np.log(np.clip(p, 1e-6, 1)) + (1 - yva) * np.log(np.clip(1 - p, 1e-6, 1)))) / wva.sum()))
    return m, gecmis


def tahmin(m, X):
    m.eval()
    with torch.no_grad():
        return torch.sigmoid(m(torch.tensor(X, device=cihaz)).squeeze(1)).cpu().numpy()


def auc_w(s, y, w):
    u, inv = np.unique(s, return_inverse=True)
    w1 = np.bincount(inv, weights=w * y)
    w0 = np.bincount(inv, weights=w * (1 - y))
    c0 = np.cumsum(w0) - w0
    return float(np.sum(w1 * (c0 + 0.5 * w0)) / (w1.sum() * w0.sum()))


def ap_w(s, y, w):
    o = np.argsort(-s, kind="mergesort")
    tp = np.cumsum(w[o] * y[o])
    al = np.cumsum(w[o])
    return float(np.sum(w[o] * y[o] / np.sum(w * y) * tp / al))


konfigler = [{"gizli": g, "birakma": b, "wd": wd, "lr": 1e-3} for g in ((128, 64), (256, 128)) for b in (0.1, 0.3) for wd in (1e-5, 1e-3)]
sonuc = []
ayar = []
for s in ("A1", "A2"):
    feats = setler[s]
    katlar = [(h[h["yil"] == 2023], h[(h["yil"] == 2024) & (h["eslesen_onceki_yil"] == 0)]), (h[h["yil"] == 2024], h[(h["yil"] == 2023) & (h["eslesen_sonraki_yil"] == 0)])]
    en = None
    for ki, k in enumerate(konfigler):
        ll, ep = [], []
        for tr, va in katlar:
            Xtr, (Xva,) = kodla(tr, [va], feats)
            _, g = egit(Xtr, tr["FI"].values, tr["w"].values, k, TOHUM, 40, Xva, va["FI"].values.astype(float), va["w"].values)
            ll.append(min(g))
            ep.append(int(np.argmin(g)) + 1)
        ayar.append({"set": s, "konfig": ki, **{kk: str(vv) for kk, vv in k.items()}, "cv_logloss": float(np.mean(ll)), "epok": int(round(np.mean(ep)))})
        if en is None or np.mean(ll) < en[0]:
            en = (float(np.mean(ll)), k, int(round(np.mean(ep))))
    tr = h[h["yil"].isin([2023, 2024])]
    te = h[(h["yil"] == 2025) & (h["test_temiz"] == 1)]
    Xtr, (Xte,) = kodla(tr, [te], feats)
    p = np.mean([tahmin(egit(Xtr, tr["FI"].values, tr["w"].values, en[1], TOHUM + i, en[2])[0], Xte) for i in range(5)], axis=0)
    y, w = te["FI"].values.astype(float), te["HB040"].values.astype(float)
    sk = pd.read_parquet(VERI / "ml" / "skorlar_2025.parquet").set_index("hane_kimlik").loc[te["hane_kimlik"].values]
    rng = np.random.default_rng(TOHUM + 7)
    n = len(te)
    fark = []
    for b in range(1000):
        mb = np.bincount(rng.integers(0, n, n - 1), minlength=n) * n / (n - 1)
        fark.append(auc_w(p, y, w * mb) - auc_w(sk[f"lgb_{s}"].values, y, w * mb))
    z = np.log(np.clip(p, 1e-6, 1 - 1e-6) / np.clip(1 - p, 1e-6, 1))
    Xk = np.column_stack([np.ones_like(z), z])
    bk = np.zeros(2)
    for _ in range(50):
        mu = 1 / (1 + np.exp(-(Xk @ bk)))
        st = np.linalg.solve(Xk.T @ (Xk * (w * mu * (1 - mu))[:, None]), Xk.T @ (w * (y - mu)))
        bk += st
        if np.max(np.abs(st)) < 1e-10:
            break
    sonuc.append({"set": s, "model": "MLP", "cihaz": str(cihaz), "gizli": str(en[1]["gizli"]), "birakma": en[1]["birakma"], "wd": en[1]["wd"], "epok": en[2], "cv_logloss": en[0],
                  "auc": auc_w(p, y, w), "pr_auc": ap_w(p, y, w), "brier": float(np.sum(w * (p - y) ** 2) / w.sum()), "OE": float(np.sum(w * y) / np.sum(w * p)),
                  "auc_lgb": auc_w(sk[f"lgb_{s}"].values, y, w), "auc_fark_mlp_eksi_lgb": auc_w(p, y, w) - auc_w(sk[f"lgb_{s}"].values, y, w), "kalibrasyon_egim": float(bk[1]),
                  "auc_fark_alt": float(np.percentile(fark, 2.5)), "auc_fark_ust": float(np.percentile(fark, 97.5)), "n_test": n})
    print(sonuc[-1], flush=True)
pd.DataFrame(ayar).to_csv(SON / "log" / "H2_mlp_ayar.csv", index=False)
r = pd.DataFrame(sonuc)
r["sure_dk"] = round((time.time() - T_BAS) / 60, 2)
r.to_csv(SON / "H2_mlp.csv", index=False)
print("mlp.py bitti, dk:", round((time.time() - T_BAS) / 60, 2))
