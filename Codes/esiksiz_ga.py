import json
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
print(f"[{(time.time() - T_BAS) / 60:5.1f} dk] esiksiz metrik GA'lari bitti; satir {len(sonuc)}", flush=True)

KAL_SINIR = (0.2, 5.0)
KAL_TOL = 1e-10
KAL_PARCA = 1000
cocuk = te["n_cocuk"].values.astype(float)
yoksul = te["yoksul"].values.astype(float)
assert (yoksul == (te["goreli_esdeger_gelir"].values < 0.6)).all()
assert (yoksul == (te["gelir_bandi"].values == 1)).all()
kal_marj = {
    "hane_tipi": te["HB050"].astype(int).astype(str).values,
    "hane_buyuklugu": np.minimum(te["hane_buyuklugu"].values, 6).astype(int).astype(str),
    "ibbs1": te["HB030"].astype(str).values,
    "reis_yas": np.select([te["reis_yas"].values < 35, te["reis_yas"].values < 50, te["reis_yas"].values < 65], ["<35", "35-49", "50-64"], ">=65"),
    "mulkiyet": np.where(te["HH020"].values == 1, "sahibi", np.where(te["HH020"].values == 2, "kiraci", "lojman_kirasiz")),
    "gelir_bandi": te["gelir_bandi"].astype(int).astype(str).values,
}
for k, v in kal_marj.items():
    assert not pd.isna(v).any(), k
T_TOP = w.sum()
kal_A, kal_T, kal_kat = [], [], []
for k, v in kal_marj.items():
    u, inv = np.unique(v, return_inverse=True)
    A = sparse.csr_matrix((np.ones(n_te), (inv, np.arange(n_te))), shape=(len(u), n_te))
    kal_A.append(A[:, temiz])
    kal_T.append(A @ w)
    kal_kat.append((k, u))
    assert (kal_A[-1].sum(1) > 0).all(), k


def rake(W0):
    pozitif = W0 > 0
    W = W0.copy()
    for it in range(5000):
        for A, T in zip(kal_A, kal_T):
            S = np.asarray(A @ W)
            f = np.where(S > 0, T[:, None] / np.where(S > 0, S, 1), 1.0)
            W = W * np.asarray(A.T @ f)
        G = np.clip(np.where(pozitif, W / np.where(pozitif, W0, 1), 1.0), *KAL_SINIR)
        W = np.where(pozitif, W0 * G, 0.0)
        sapma = max(float(np.max(np.abs(np.asarray(A @ W) / T[:, None] - 1))) for A, T in zip(kal_A, kal_T))
        if sapma < KAL_TOL:
            break
    return W, it + 1, sapma


wt = w[temiz]
W0k = (wt * T_TOP / wt.sum())[:, None]
Wk0, kal_it, kal_sapma = rake(W0k)
assert kal_sapma < KAL_TOL, kal_sapma
oran = Wk0[:, 0] / W0k[:, 0]
pd.DataFrame({"hane_kimlik": te["hane_kimlik"].values[temiz], "w_kalibre": Wk0[:, 0], "w_ozgun": wt}).to_parquet(VERI / "ml" / "kalibre_agirlik_test_2025.parquet", index=False)
kal_ozet = {"n": int(temiz.sum()), "toplam_hedef": float(T_TOP), "toplam_test_ozgun": float(wt.sum()), "olcek": float(T_TOP / wt.sum()), "sinirlar": list(KAL_SINIR),
            "yineleme": kal_it, "en_buyuk_marj_sapmasi": kal_sapma,
            "oran": {"min": float(oran.min()), "p05": float(np.percentile(oran, 5)), "medyan": float(np.median(oran)), "p95": float(np.percentile(oran, 95)), "max": float(oran.max())},
            "sinirda_hane": {"alt": int(np.sum(oran <= KAL_SINIR[0] + 1e-12)), "ust": int(np.sum(oran >= KAL_SINIR[1] - 1e-12))},
            "kish_etkin_n_ozgun": float(wt.sum() ** 2 / np.sum(wt ** 2)), "kish_etkin_n_kalibre": float(Wk0[:, 0].sum() ** 2 / np.sum(Wk0[:, 0] ** 2)),
            "marjlar": [{"marj": k, "kategori": str(c), "hedef_pay": float(T[i] / T_TOP), "ozgun_pay": float((A @ wt)[i] / wt.sum()), "kalibre_pay": float((A @ Wk0[:, 0])[i] / T_TOP)}
                        for (k, u), A, T in zip(kal_kat, kal_A, kal_T) for i, c in enumerate(u)]}
print(f"[{(time.time() - T_BAS) / 60:5.1f} dk] kalibrasyon: {kal_it} yineleme, oran {oran.min():.3f}-{oran.max():.3f}, Kish n {kal_ozet['kish_etkin_n_ozgun']:.0f} -> {kal_ozet['kish_etkin_n_kalibre']:.0f}", flush=True)
kal_it_b, kal_sapma_b = 0, 0.0

H2_KOLLAR = ["gelir_sirasi", "cart_T2", "cart_T2idari", "l1_T2", "cart_T1T2", "l1_T1T2", "logit_lin_A1", "logit_A1", "lgb_A2i", "lgb_A2", "lgb_A1", "lgb_A3", "lgb_A4",
             "yoksul+cart_B_T2", "yoksul+lgb_B1", "mlp_A1", "mlp_A2", "logit_lin_A2"]
H2_MM = (("logit_lin_A1", "lgb_A1", "cocuk"), ("l1_T1T2", "lgb_A1", "cocuk"), ("lgb_A1", "lgb_A2", "duyarlilik"), ("logit_lin_A1", "logit_lin_A2", "duyarlilik"))


def skor_al(kol):
    if kol == "gelir_sirasi":
        return gelir_skor
    if kol.startswith("yoksul+"):
        return np.where(yoksul == 1, 10.0, skorlar[kol.split("+", 1)[1]].values)
    return skorlar[kol].values


def kapsam(A, yy, kk, Wb, c):
    Wg = A @ Wb
    W1g = A @ (Wb * yy[:, None])
    Kg = A @ (Wb * (kk * yy)[:, None])
    once = np.cumsum(Wg, axis=0) - Wg
    hedef = c * Wg.sum(0)
    with np.errstate(divide="ignore", invalid="ignore"):
        frac = np.where(Wg > 0, np.clip((hedef - once) / Wg, 0, 1), 0)
    sec = (frac * Wg).sum(0)
    secFI = (frac * W1g).sum(0)
    return {"kapsama": 100 * sec / Wg.sum(0), "duyarlilik": 100 * secFI / W1g.sum(0), "ppv": 100 * secFI / sec, "cocuk": 100 * (frac * Kg).sum(0) / Kg.sum(0)}


def bayrak(f, yy, kk, Wb):
    tot = Wb.sum(0)
    sec = (Wb * f[:, None]).sum(0)
    secFI = (Wb * (f * yy)[:, None]).sum(0)
    return {"kapsama": 100 * sec / tot, "duyarlilik": 100 * secFI / (Wb * yy[:, None]).sum(0), "ppv": 100 * secFI / sec, "cocuk": 100 * (Wb * (f * yy * kk)[:, None]).sum(0) / (Wb * (yy * kk)[:, None]).sum(0)}


def degerlendir(m, Wb, kollar, gm):
    yy, kk = y[m], cocuk[m]
    tot = Wb.sum(0)
    noktalar = {"yoksulluk_orani": (Wb * yoksul[m][:, None]).sum(0) / tot, "30": np.full(Wb.shape[1], 0.30), "FI_yayginligi": (Wb * yy[:, None]).sum(0) / tot}
    out = {("yoksul_60", "yoksulluk_orani"): bayrak(yoksul[m], yy, kk, Wb)}
    for kol in kollar:
        for nk, c in noktalar.items():
            out[(kol, nk)] = kapsam(gm[kol], yy, kk, Wb, c)
    for nk, c in noktalar.items():
        p_ = noktalar["FI_yayginligi"]
        out[("tavan", nk)] = {"kapsama": 100 * c, "duyarlilik": np.minimum(100, 100 * c / p_), "ppv": np.where(c <= p_, 100.0, 100 * p_ / c), "cocuk": np.full(Wb.shape[1], np.nan)}
    return out


def ozet_satirlari(v0, vb, etiket):
    sat = []
    for (kol, nk), d0 in v0.items():
        for metr in ("kapsama", "duyarlilik", "ppv", "cocuk"):
            x = vb[(kol, nk)][metr]
            if np.isnan(d0[metr][0]):
                continue
            sat.append({"test_seti": etiket, "tur": "metrik", "kol": kol, "karsilastirma": "", "kapsama_noktasi": nk, "metrik": metr, "deger": float(d0[metr][0]),
                        "alt": float(np.nanpercentile(x, 2.5)), "ust": float(np.nanpercentile(x, 97.5)), "se_boot": float(np.nanstd(x, ddof=1))})
    for (kol, nk), d0 in v0.items():
        if nk != "yoksulluk_orani" or kol in ("yoksul_60", "tavan"):
            continue
        for metr in ("duyarlilik", "ppv", "cocuk"):
            x = vb[(kol, nk)][metr] - vb[("yoksul_60", nk)][metr]
            sat.append({"test_seti": etiket, "tur": "fark", "kol": kol, "karsilastirma": "yoksul_60", "kapsama_noktasi": nk, "metrik": metr, "deger": float(d0[metr][0] - v0[("yoksul_60", nk)][metr][0]),
                        "alt": float(np.nanpercentile(x, 2.5)), "ust": float(np.nanpercentile(x, 97.5)), "se_boot": float(np.nanstd(x, ddof=1))})
    for kol, ref, metr in H2_MM:
        nk = "yoksulluk_orani"
        x = vb[(kol, nk)][metr] - vb[(ref, nk)][metr]
        sat.append({"test_seti": etiket, "tur": "fark", "kol": kol, "karsilastirma": ref, "kapsama_noktasi": nk, "metrik": metr, "deger": float(v0[(kol, nk)][metr][0] - v0[(ref, nk)][metr][0]),
                    "alt": float(np.nanpercentile(x, 2.5)), "ust": float(np.nanpercentile(x, 97.5)), "se_boot": float(np.nanstd(x, ddof=1))})
    return sat


def birlestir(parcalar):
    return {k: {metr: np.concatenate([p[k][metr] for p in parcalar]) for metr in parcalar[0][k]} for k in parcalar[0]}


def calistir(m, kalibre):
    kollar = [k for k in H2_KOLLAR if not np.isnan(skor_al(k)[m]).any()]
    gm = {k: grup_matris(skor_al(k)[m]) for k in kollar}
    global kal_it_b, kal_sapma_b
    if kalibre:
        v0 = degerlendir(m, Wk0, kollar, gm)
    else:
        v0 = degerlendir(m, w[m][:, None], kollar, gm)
    parcalar = []
    for j0 in range(0, B_BOOT, KAL_PARCA):
        Wb = WB[m, j0:j0 + KAL_PARCA]
        if kalibre:
            Wb, it_, sp_ = rake(Wb * (T_TOP / Wb.sum(0))[None, :])
            kal_it_b, kal_sapma_b = max(kal_it_b, it_), max(kal_sapma_b, sp_)
        parcalar.append(degerlendir(m, Wb, kollar, gm))
    return v0, birlestir(parcalar)


v0o, vbo = calistir(temiz, False)
ozgun = ozet_satirlari(v0o, vbo, "ana_test_ozgun_agirlik")
eski_m = pd.read_csv(SON / "H2_hedefleme_metrikleri.csv").query("sema == 'temiz' and nufus == 'A'")
eski_f = pd.read_csv(SON / "H2_eslesik_farklar.csv").query("sema == 'temiz' and nufus == 'A' and karsilastirma == 'yoksul_60'")
kontrol_n = 0
for r in ozgun:
    if r["tur"] == "metrik" and r["metrik"] != "kapsama":
        k_ = "kendi" if r["kol"] == "yoksul_60" else r["kapsama_noktasi"]
        e = eski_m[(eski_m["kol"] == r["kol"]) & (eski_m["kapsama_noktasi"] == k_)]
        if len(e):
            for c, c2 in (("deger", r["metrik"]), ("alt", r["metrik"] + "_alt"), ("ust", r["metrik"] + "_ust")):
                assert abs(r[c] - e.iloc[0][c2]) < 1e-9, (r["kol"], k_, r["metrik"], c, r[c], e.iloc[0][c2])
            kontrol_n += 1
    if r["tur"] == "fark" and r["karsilastirma"] == "yoksul_60":
        e = eski_f[(eski_f["kol"] == r["kol"]) & (eski_f["metrik"] == r["metrik"])]
        if len(e):
            for c in ("deger", "alt", "ust"):
                assert abs(r[c] - e.iloc[0]["fark" if c == "deger" else c]) < 1e-9, (r["kol"], r["metrik"], c)
            kontrol_n += 1
print(f"[{(time.time() - T_BAS) / 60:5.1f} dk] ozgun agirlikli yeniden hesap: {kontrol_n} satir mevcut H2 ciktilariyla ayni", flush=True)
pd.DataFrame([r for r in ozgun if r["tur"] == "fark"]).to_csv(SON / "H2_fark_bootstrap_sd.csv", index=False)

v0k, vbk = calistir(temiz, True)
kal_ozet["replikat_en_cok_yineleme"] = kal_it_b
kal_ozet["replikat_en_buyuk_marj_sapmasi"] = kal_sapma_b
assert kal_sapma_b < KAL_TOL, kal_sapma_b
kal_ozet["yoksulluk_orani_hedef"] = float(np.sum(w * yoksul) / T_TOP)
kal_ozet["FI_yayginligi_tum_2025"] = float(np.sum(w * y) / T_TOP)
kal_ozet["FI_hane_toplam_2025"] = float(np.sum(w * y))
kal_ozet["FI_hanelerde_cocuk_HB040"] = float(np.sum(w * y * cocuk))
kal_ozet["yoksul_hane_toplam_2025"] = float(np.sum(w * yoksul))
pd.DataFrame(ozgun + ozet_satirlari(v0k, vbk, "ana_test_kalibre")).to_csv(SON / "H2_kalibre_test.csv", index=False)
print(f"[{(time.time() - T_BAS) / 60:5.1f} dk] kalibre degerlendirme bitti; replikatlarda en cok {kal_it_b} yineleme", flush=True)

tr63 = temiz & (te["HB031"].astype(str).values != "TR63")
v0t, vbt = calistir(tr63, False)
pd.DataFrame(ozet_satirlari(v0t, vbt, "ana_test_tr63_haric")).to_csv(SON / "H2_tr63_haric.csv", index=False)
kal_ozet["tr63_haric_n"] = int(tr63.sum())
kal_ozet["tr63_ana_testte_n"] = int((temiz & ~tr63).sum())
(SON / "log" / "kalibrasyon_ozet.json").write_text(json.dumps(kal_ozet, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"esiksiz_ga.py bitti, {(time.time() - T_BAS) / 60:.1f} dk; satir {len(sonuc)}", flush=True)
