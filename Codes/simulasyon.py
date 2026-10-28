import json
import sys
import time
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from joblib import Parallel, delayed
from scipy import sparse

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data"
SIM = VERI / "simulasyon"
FV = VERI / "figur_verileri"
SON = KOK / "Results"
for k in (SIM, FV):
    k.mkdir(parents=True, exist_ok=True)
MOD = sys.argv[1] if len(sys.argv) > 1 else "tam"
ISCI = 16
TOHUM0 = 20261101
R_S1 = 50 if MOD == "pilot" else 200
M_S2 = 50 if MOD == "pilot" else 200
S_S3 = 50 if MOD == "pilot" else 500
B_S3 = 200
T_BAS = time.time()
senaryolar = []


def yaz(*a):
    print(f"[{(time.time() - T_BAS) / 60:6.1f} dk]", *a, flush=True)
    (SIM / "ilerleme.txt").write_text(f"{time.strftime('%d.%m.%Y %H:%M')} {' '.join(str(x) for x in a)}\n", encoding="utf-8")


h = pd.read_parquet(VERI / "hane_2023_2025.parquet")
h["HB031"] = h["HB031"].astype(str)
h["w"] = h["HB040"] / h.groupby("yil")["HB040"].transform("mean")
FEATS = json.loads((VERI / "ml" / "ozellik_setleri.json").read_text(encoding="utf-8"))["A1"]
hp = pd.read_csv(SON / "H2_hiperparametreler.csv", float_precision="round_trip").set_index("set").loc["A1"]
PAR = {k: (int(hp[k]) if k in ("num_leaves", "min_data_in_leaf", "max_depth") else float(hp[k])) for k in ("num_leaves", "min_data_in_leaf", "learning_rate", "feature_fraction", "bagging_fraction", "lambda_l2", "max_depth", "lambda_l1", "min_gain_to_split", "cat_smooth")}
N_TUR = int(hp["n_tur_final"])
NOMINAL = {"HB031", "HB050", "reis_medeni", "reis_calisma7", "HH010", "HH020", "HH080", "HH100", "HH110"}
KAT = {v: sorted(h[v].dropna().unique().tolist(), key=lambda z: str(z)) for v in FEATS if v in NOMINAL}


def lgb_X(df):
    X = df[FEATS].copy()
    for v in FEATS:
        X[v] = pd.Categorical(X[v], categories=KAT[v]) if v in NOMINAL else X[v].astype(float)
    return X


def egit(X, y, w, tohum, n_tur=N_TUR, par=PAR, isci=1):
    p = {"objective": "binary", "verbosity": -1, "num_threads": isci, "seed": tohum, "bagging_freq": 1, "deterministic": True, "force_col_wise": True}
    p.update(par)
    return lgb.train(p, lgb.Dataset(X, y, weight=w, categorical_feature=[v for v in FEATS if v in NOMINAL]), num_boost_round=n_tur)


def expit(z):
    return 1 / (1 + np.exp(-z))


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def auc_w(s, y, w):
    u, inv = np.unique(s, return_inverse=True)
    w1 = np.bincount(inv, weights=w * y)
    w0 = np.bincount(inv, weights=w * (1 - y))
    c0 = np.cumsum(w0) - w0
    return float(np.sum(w1 * (c0 + 0.5 * w0)) / (w1.sum() * w0.sum()))


def duyarlilik(skor, y, w, c):
    o = np.argsort(-skor, kind="mergesort")
    u, inv = np.unique(-skor, return_inverse=True)
    Wg = np.bincount(inv, weights=w)
    W1g = np.bincount(inv, weights=w * y)
    once = np.cumsum(Wg) - Wg
    frac = np.clip((c * Wg.sum() - once) / np.where(Wg > 0, Wg, 1), 0, 1)
    return float(100 * np.sum(frac * W1g) / W1g.sum())


def kalibrasyon(p, y, w):
    z = logit(p)
    X = np.column_stack([np.ones_like(z), z])
    b = np.zeros(2)
    for _ in range(50):
        mu = expit(X @ b)
        st = np.linalg.solve(X.T @ (X * (w * mu * (1 - mu))[:, None]), X.T @ (w * (y - mu)))
        b += st
        if np.max(np.abs(st)) < 1e-10:
            break
    a = 0.0
    for _ in range(50):
        mu = expit(z + a)
        st = np.sum(w * (y - mu)) / np.sum(w * mu * (1 - mu))
        a += st
        if abs(st) < 1e-12:
            break
    return a, b[1]


t0 = time.time()
h24 = h[h["yil"] == 2024].reset_index(drop=True)
h25 = h[h["yil"] == 2025].reset_index(drop=True)
es = pd.read_csv(VERI / "ortusme_eslesmeleri.csv")
es = es[(es["yil_1"] == 2024) & (es["yil_2"] == 2025)]
i24 = pd.Series(np.arange(len(h24)), index=h24["hane_kimlik"].values)
i25 = pd.Series(np.arange(len(h25)), index=h25["hane_kimlik"].values)
cift = np.column_stack([i24.loc[es["hane_1"].values].values, i25.loc[es["hane_2"].values].values])
X24, X25 = lgb_X(h24), lgb_X(h25)
havuz = pd.concat([h24, h25], ignore_index=True)
gen = egit(lgb_X(havuz), havuz["FI"].values, havuz["w"].values, TOHUM0, n_tur=300, par={"num_leaves": 15, "min_data_in_leaf": 200, "learning_rate": 0.05, "feature_fraction": 0.8, "bagging_fraction": 0.8, "lambda_l2": 1.0, "max_depth": 6}, isci=ISCI)
eta24 = gen.predict(X24, raw_score=True)
eta25 = gen.predict(X25, raw_score=True)
hedef_prev = float(np.sum(havuz["w"] * havuz["FI"]) / havuz["w"].sum())
gh_x, gh_w = np.polynomial.hermite_e.hermegauss(40)
gh_w = gh_w / gh_w.sum()


def kesim_bul(eta, w, sigma, hedef):
    lo, hi = -10.0, 10.0
    for _ in range(80):
        orta = (lo + hi) / 2
        m = np.sum(w[:, None] * expit(eta[:, None] + orta + sigma * gh_x[None, :]) * gh_w[None, :]) / w.sum()
        lo, hi = (orta, hi) if m < hedef else (lo, orta)
    return (lo + hi) / 2


eta_hep = np.concatenate([eta24, eta25])
w_hep = havuz["w"].values
n24, n25 = len(h24), len(h25)
n_gercek = len(cift)
rng0 = np.random.default_rng(TOHUM0)
eslesmemis25 = np.setdiff1d(np.arange(n25), cift[:, 1])
eslesmemis24 = np.setdiff1d(np.arange(n24), cift[:, 0])
GIZLI = (0.10, 0.20, round(1 - float(h25["test_temiz"].sum()) / float(h25["test_temiz_imza"].sum()), 3))


def gizli_maskeler(bag, rng):
    temiz = bag < 0
    eslesen_i = np.flatnonzero(~temiz)
    out = {}
    for s in GIZLI:
        k = min(len(eslesen_i), int(round(s / (1 - s) * temiz.sum())))
        m = temiz.copy()
        m[rng.choice(eslesen_i, k, replace=False)] = True
        out[f"temiz_gizli_{100 * s:.1f}"] = m
    return out


def senaryo_kur(pay, rng):
    hedef = n_gercek if pay == "gercek" else int(round(pay * n25))
    bag = np.full(n25, -1)
    Xt = X25.copy()
    eta_t = eta25.copy()
    yok = h25["yoksul"].values.astype(float).copy()
    if hedef <= n_gercek:
        sec = rng.choice(n_gercek, hedef, replace=False)
        bag[cift[sec, 1]] = cift[sec, 0]
    else:
        bag[cift[:, 1]] = cift[:, 0]
        ek = hedef - n_gercek
        yerine = rng.choice(eslesmemis25, ek, replace=False)
        kaynak = rng.choice(eslesmemis24, ek, replace=False)
        ham = h25[FEATS].copy()
        for v in FEATS:
            sut = ham[v].to_numpy(copy=True)
            sut[yerine] = h24[v].to_numpy()[kaynak]
            ham[v] = sut
        Xt = lgb_X(ham)
        eta_t[yerine] = eta24[kaynak]
        yok[yerine] = h24["yoksul"].values[kaynak]
        bag[yerine] = kaynak
    return bag, Xt, eta_t, yok


def s1_tekrar(sid, r, sigma, delta, bag, Xt, eta_t, yok, w25, c_pov, gizli):
    rng = np.random.default_rng(TOHUM0 + 1000 * sid + r)
    u24 = rng.normal(0, sigma, n24)
    y24 = (rng.uniform(size=n24) < expit(eta24 + delta + u24)).astype(float)
    m = egit(X24, y24, h24["w"].values, TOHUM0 + r)
    p = m.predict(Xt)
    u_bag = np.where(bag >= 0, u24[np.maximum(bag, 0)], rng.normal(0, sigma, n25))
    u_bag_dis = rng.normal(0, sigma, n25)
    U = rng.uniform(size=n25)
    y_pay = (U < expit(eta_t + delta + u_bag)).astype(float)
    y_bag = (U < expit(eta_t + delta + u_bag_dis)).astype(float)
    out = []
    temiz = bag < 0
    for ad, yy in (("paylasilan", y_pay), ("bagimsiz", y_bag)):
        for sk, mk in [("tam", np.ones(n25, dtype=bool)), ("temiz", temiz), ("eslesen", ~temiz)] + list(gizli.items()):
            a, b = kalibrasyon(p[mk], yy[mk], w25[mk])
            out.append({"sid": sid, "r": r, "sonuc_uretimi": ad, "test_seti": sk, "auc": auc_w(p[mk], yy[mk], w25[mk]),
                        "duyarlilik": duyarlilik(p[mk], yy[mk], w25[mk], c_pov), "kalibrasyon_kesim": a, "kalibrasyon_egim": b, "FI": float(np.sum(w25[mk] * yy[mk]) / w25[mk].sum())})
    return out


s1_ham = []
sid = 0
w25 = h25["HB040"].values.astype(float)
for icc in (0.3, 0.6):
    sigma = float(np.sqrt(icc / (1 - icc) * np.pi ** 2 / 3))
    delta = kesim_bul(eta_hep, w_hep, sigma, hedef_prev)
    for pay in (0.3, "gercek", 0.6):
        sid += 1
        t1 = time.time()
        bag, Xt, eta_t, yok = senaryo_kur(pay, np.random.default_rng(TOHUM0 + 1000 * sid))
        gizli = gizli_maskeler(bag, np.random.default_rng(TOHUM0 + 1000 * sid + 999))
        c_pov = float(np.sum(w25 * yok) / w25.sum())
        f = SIM / f"S1_sid{sid}_R{R_S1}.parquet"
        if f.exists():
            res = pd.read_parquet(f)
        else:
            out = Parallel(n_jobs=ISCI, backend="loky")(delayed(s1_tekrar)(sid, r, sigma, delta, bag, Xt, eta_t, yok, w25, c_pov, gizli) for r in range(R_S1))
            res = pd.DataFrame([x for o in out for x in o])
            res.to_parquet(f, index=False)
        res["icc"] = icc
        res["ortusme_payi"] = pay if pay != "gercek" else round(n_gercek / n25, 3)
        res["ortusme_tanim"] = "gercek" if pay == "gercek" else "yapay"
        s1_ham.append(res)
        senaryolar.append({"sid": sid, "calisma": "S1", "icc": icc, "sigma_u": sigma, "kesim_kaymasi": delta, "ortusme": pay if pay != "gercek" else f"gercek ({n_gercek / n25:.3f})",
                           "baglanan_hane": int((bag >= 0).sum()), "gizli_ortusme_paylari": ";".join(f"{s:.3f}" for s in GIZLI), "tekrar": R_S1, "tohum": TOHUM0 + 1000 * sid, "sure_dk": round((time.time() - t1) / 60, 2),
                           "ogrenici": f"LightGBM A1 ayari, {N_TUR} agac, ogrenme hizi {PAR['learning_rate']:.4f} (sabit)"})
        yaz(f"S1 senaryo {sid} (ICC {icc}, ortusme {pay}) bitti, {(time.time() - t1) / 60:.1f} dk")
s1_ham = pd.concat(s1_ham, ignore_index=True)
s1_ham.to_csv(SIM / "S1_ham.csv", index=False)
gen_s = s1_ham.pivot_table(index=["sid", "r", "icc", "ortusme_payi", "ortusme_tanim", "test_seti"], columns="sonuc_uretimi", values=["auc", "duyarlilik", "kalibrasyon_egim", "kalibrasyon_kesim"]).reset_index()
gen_s.columns = ["_".join([c for c in col if c]) for col in gen_s.columns]
for mt in ("auc", "duyarlilik", "kalibrasyon_egim", "kalibrasyon_kesim"):
    gen_s[f"iyimserlik_{mt}"] = gen_s[f"{mt}_paylasilan"] - gen_s[f"{mt}_bagimsiz"]
s1_oz = gen_s.groupby(["sid", "icc", "ortusme_payi", "ortusme_tanim", "test_seti"]).agg(
    R=("r", "nunique"),
    auc_paylasilan=("auc_paylasilan", "mean"), auc_bagimsiz=("auc_bagimsiz", "mean"),
    iyimserlik_auc=("iyimserlik_auc", "mean"), iyimserlik_auc_mcse=("iyimserlik_auc", lambda x: x.std() / np.sqrt(len(x))),
    duyarlilik_paylasilan=("duyarlilik_paylasilan", "mean"), duyarlilik_bagimsiz=("duyarlilik_bagimsiz", "mean"),
    iyimserlik_duyarlilik=("iyimserlik_duyarlilik", "mean"), iyimserlik_duyarlilik_mcse=("iyimserlik_duyarlilik", lambda x: x.std() / np.sqrt(len(x))),
    egim_paylasilan=("kalibrasyon_egim_paylasilan", "mean"), egim_bagimsiz=("kalibrasyon_egim_bagimsiz", "mean"),
    iyimserlik_egim=("iyimserlik_kalibrasyon_egim", "mean"), kesim_paylasilan=("kalibrasyon_kesim_paylasilan", "mean"), kesim_bagimsiz=("kalibrasyon_kesim_bagimsiz", "mean")).reset_index()
s1_oz.to_csv(SIM / "S1_ozet.csv", index=False)
s1_oz.to_csv(FV / "fig6a_ortusme_iyimserligi.csv", index=False)
yaz("S1 ozet:\n" + s1_oz[["icc", "ortusme_payi", "test_seti", "iyimserlik_auc", "iyimserlik_duyarlilik", "iyimserlik_egim"]].round(4).to_string())

t0 = time.time()
sk = pd.read_parquet(VERI / "ml" / "skorlar_2025.parquet")
te = h25.merge(sk, on="hane_kimlik", how="left")
y = te["FI"].values.astype(float)
w = te["HB040"].values.astype(float)
yoksul = te["yoksul"].values.astype(float)
dusuk_gelir = (te["gelir_dilim5"].values <= 2).astype(float)
temiz = te["test_temiz"].values == 1
p_ham = te["lgb_A1"].values


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


p_obs = kesim_kalibre(p_ham, y, w)
c_pov_temiz = float(np.sum(w[temiz] * yoksul[temiz]) / w[temiz].sum())
cart = te["cart_T2"].values
lgbA1 = te["lgb_A1"].values


def olculer(T):
    out = {"dislama_hatasi": 100 * np.sum(w * T * (1 - yoksul)) / np.sum(w * T), "FI_yoksul_icinde": 100 * np.sum(w * T * yoksul) / np.sum(w * yoksul),
           "FI_yayginligi": 100 * np.sum(w * T) / w.sum()}
    tt, ww = T[temiz], w[temiz]
    out["kural_seti_duyarlilik"] = duyarlilik(cart[temiz], tt, ww, c_pov_temiz)
    out["lgb_A1_duyarlilik"] = duyarlilik(lgbA1[temiz], tt, ww, c_pov_temiz)
    out["yoksulluk_esigi_duyarlilik"] = 100 * np.sum(ww * tt * yoksul[temiz]) / np.sum(ww * tt)
    out["kural_eksi_esik"] = out["kural_seti_duyarlilik"] - out["yoksulluk_esigi_duyarlilik"]
    out["lgb_eksi_esik"] = out["lgb_A1_duyarlilik"] - out["yoksulluk_esigi_duyarlilik"]
    return out


gozlenen = olculer(y)
kisi_w = pd.read_parquet(VERI / "gyka_2023_2025.parquet", columns=["yil", "hane_kimlik", "FK050"])
kisi_w = kisi_w[kisi_w["yil"] == 2025].groupby("hane_kimlik")["FK050"].sum()
wk = te["hane_kimlik"].map(kisi_w).values.astype(float)
assert not np.isnan(wk).any()
hucre_kod = te["gelir_dilim5"].values.astype(int) * 10 + yoksul.astype(int)
HUC = np.unique(hucre_kod)
hix = np.searchsorted(HUC, hucre_kod)
huc_dusuk = HUC // 10 <= 2
huc_A = HUC % 10 == 0


def huc_top(v):
    return np.bincount(hix, weights=v, minlength=len(HUC))


W_c, O_c, WK_c, OK_c = huc_top(w), huc_top(w * y), huc_top(wk), huc_top(wk * y)
p_c = O_c / W_c
hucre_tablo = pd.DataFrame({"gelir_dilim5": HUC // 10, "yoksul": HUC % 10, "n": np.bincount(hix), "agirlik_payi": 100 * W_c / W_c.sum(), "gozlenen_FI": 100 * p_c})
uyum_sinir = {"ayrimci_degil": 1 - p_c.min(), "gelire_gore": max(1 - p_c[~huc_dusuk].min(), 1.05 - p_c[huc_dusuk].min()), "Se": p_c.max()}
risk_kod = pd.qcut(te["lgb_A1"].values, 10, labels=False) * 10 + dusuk_gelir.astype(int)
RSK = np.unique(risk_kod)
rix = np.searchsorted(RSK, risk_kod)
rsk_dusuk = RSK % 10 == 1
n_r = np.bincount(rix)
p_r = np.bincount(rix, weights=w * y) / np.bincount(rix, weights=w)
se_r = np.sqrt(p_r * (1 - p_r) / n_r)
risk_tablo = pd.DataFrame({"risk_ondaligi": RSK // 10 + 1, "gelir_Q12": RSK % 10, "n": n_r, "gozlenen_FI": 100 * p_r, "se": 100 * se_r, "denetimde": n_r >= 100})
rg = n_r >= 100
risk_sinir = {}
for ad, alt, ust in (("", p_r, p_r), ("_2se", p_r + 2 * se_r, p_r - 2 * se_r)):
    risk_sinir["ayrimci_degil" + ad] = 1 - alt[rg].min()
    risk_sinir["gelire_gore" + ad] = max(1 - alt[rg & ~rsk_dusuk].min(), 1.05 - alt[rg & rsk_dusuk].min())
    risk_sinir["Se" + ad] = ust[rg].max()


def sp_hucre(sp, tur):
    return np.where(huc_dusuk, sp - 0.05, sp) if tur == "gelire_gore" else np.full(len(HUC), sp)


def kapali_form(Wc, Oc, se, spc):
    t = Wc * (Oc / Wc - (1 - spc)) / (se + spc - 1)
    return {"dislama_hatasi": 100 * t[huc_A].sum() / t.sum(), "FI_yoksul_icinde": 100 * t[~huc_A].sum() / Wc[~huc_A].sum(), "FI_yayginligi": 100 * t.sum() / Wc.sum()}


def gerceklesen(pT, m):
    ww, yy, pp = w[m], y[m], pT[m]
    return float(np.sum(ww * yy * pp) / np.sum(ww * pp)), float(np.sum(ww * (1 - yy) * (1 - pp)) / np.sum(ww * (1 - pp)))


def sesp_satir(pT, onek):
    out = {}
    for ad, m in (("", np.ones(len(y), dtype=bool)), ("_Q12", dusuk_gelir == 1), ("_Q35", dusuk_gelir == 0)):
        out[f"{onek}Se{ad}"], out[f"{onek}Sp{ad}"] = gerceklesen(pT, m)
    return out


S2_OLCU = ("dislama_hatasi", "FI_yoksul_icinde", "FI_yayginligi", "kural_seti_duyarlilik", "lgb_A1_duyarlilik", "yoksulluk_esigi_duyarlilik", "kural_eksi_esik", "lgb_eksi_esik")
s2_ham = []
s2_oz = []
s2_tani = []
s2_kf = []
for tur in ("ayrimci_degil", "gelire_gore"):
    for se in (0.80, 0.85, 0.90, 0.95):
        for sp in (0.90, 0.92, 0.94, 0.96, 0.98, 0.99):
            sid += 1
            t1 = time.time()
            spc = sp_hucre(sp, tur)
            kf = kapali_form(W_c, O_c, se, spc)
            kfk = kapali_form(WK_c, OK_c, se, spc)
            alt_ihlal = p_c < 1 - spc - 1e-12
            ust_ihlal = p_c > se + 1e-12
            uyumlu = not (alt_ihlal.any() or ust_ihlal.any())
            ihlal = "; ".join([f"Q{h // 10} {'poor' if h % 10 else 'non-poor'}: observed {100 * p:.1f} < 1 - Sp {100 * (1 - s):.1f}" for h, p, s in zip(HUC[alt_ihlal], p_c[alt_ihlal], spc[alt_ihlal])] +
                              [f"Q{h // 10} {'poor' if h % 10 else 'non-poor'}: observed {100 * p:.1f} > Se {100 * se:.1f}" for h, p in zip(HUC[ust_ihlal], p_c[ust_ihlal])])
            s2_kf.append({"sid": sid, "tur": tur, "Se": se, "Sp": sp, "Sp_dusuk_gelir": float(spc.min()), "uyumlu": uyumlu, "ihlal": ihlal,
                          "kapali_form_dislama_hane": kf["dislama_hatasi"], "kapali_form_dislama_kisi": kfk["dislama_hatasi"],
                          "kapali_form_FI_yoksul_icinde": kf["FI_yoksul_icinde"], "kapali_form_FI_yayginligi": kf["FI_yayginligi"],
                          "uyumlu_en_kucuk_Sp": uyum_sinir[tur], "uyumlu_en_kucuk_Se": uyum_sinir["Se"],
                          "uyumlu_risk_ondaligi": bool(np.all(((p_r >= 1 - np.where(rsk_dusuk & (tur == "gelire_gore"), sp - 0.05, sp) - 1e-12) & (p_r <= se + 1e-12))[rg])),
                          "risk_en_kucuk_Sp": risk_sinir[tur], "risk_en_kucuk_Sp_2se": risk_sinir[tur + "_2se"], "risk_en_kucuk_Se": risk_sinir["Se"], "risk_en_kucuk_Se_2se": risk_sinir["Se_2se"]})
            sp_i = np.where(dusuk_gelir == 1, sp - 0.05, sp) if tur == "gelire_gore" else np.full(len(y), sp)
            pi_ham = (p_obs - (1 - sp_i)) / (se + sp_i - 1)
            pi_e = np.clip(pi_ham, 0.001, 0.999)
            po = se * pi_e + (1 - sp_i) * (1 - pi_e)
            pT_e = np.where(y == 1, se * pi_e / po, (1 - se) * pi_e / (1 - po))
            rng = np.random.default_rng(TOHUM0 + 1000 * sid)
            eski = []
            for m_ in range(M_S2):
                T = (rng.uniform(size=len(y)) < pT_e).astype(float)
                eski.append(100 * np.sum(w * T * (1 - yoksul)) / np.sum(w * T))
            tn = {"sid": sid, "tur": tur, "Se": se, "Sp": sp, "alt_kirpma_payi": 100 * np.sum(w * (pi_ham < 0.001)) / w.sum(), "ust_kirpma_payi": 100 * np.sum(w * (pi_ham > 0.999)) / w.sum(),
                  "alt_kirpma_payi_yoksul_degil": 100 * np.sum(w * (pi_ham < 0.001) * (1 - yoksul)) / np.sum(w * (1 - yoksul)), "ust_kirpma_payi_yoksul": 100 * np.sum(w * (pi_ham > 0.999) * yoksul) / np.sum(w * yoksul)}
            tn.update(sesp_satir(pT_e, "gerceklesen_"))
            tn.update({"beklenen_dislama_eski": 100 * np.sum(w * pT_e * (1 - yoksul)) / np.sum(w * pT_e), "simulasyon_ortalamasi_eski": float(np.mean(eski)),
                       "kapali_form_dislama_hane": kf["dislama_hatasi"], "eski_eksi_kapali_form": float(np.mean(eski)) - kf["dislama_hatasi"], "uyumlu": uyumlu})
            s2_tani.append(tn)
            satir = {"sid": sid, "tur": tur, "Se": se, "Sp": sp, "Sp_dusuk_gelir": float(spc.min()), "uyumlu": uyumlu, "M": M_S2 if uyumlu else 0,
                     "kapali_form_dislama_hane": kf["dislama_hatasi"], "kapali_form_dislama_kisi": kfk["dislama_hatasi"], "kapali_form_FI_yoksul_icinde": kf["FI_yoksul_icinde"]}
            if uyumlu:
                pi_c = (p_c - (1 - spc)) / (se + spc - 1)
                pT = np.where(y == 1, se * pi_c[hix] / p_c[hix], (1 - se) * pi_c[hix] / (1 - p_c[hix]))
                satir.update(sesp_satir(pT, "gerceklesen_"))
                rng = np.random.default_rng(TOHUM0 + 1000 * sid)
                sonuc = []
                for m_ in range(M_S2):
                    T = (rng.uniform(size=len(y)) < pT).astype(float)
                    o = olculer(T)
                    o.update({"sid": sid, "m": m_})
                    sonuc.append(o)
                r = pd.DataFrame(sonuc)
                r["tur"], r["Se"], r["Sp"] = tur, se, sp
                s2_ham.append(r)
                for k in S2_OLCU:
                    satir[k] = float(r[k].mean())
                    satir[k + "_alt"] = float(r[k].quantile(0.025))
                    satir[k + "_ust"] = float(r[k].quantile(0.975))
                satir["dislama_eksi_kapali_form"] = satir["dislama_hatasi"] - kf["dislama_hatasi"]
            s2_oz.append(satir)
            senaryolar.append({"sid": sid, "calisma": "S2", "tur": tur, "Se": se, "Sp": sp, "Sp_dusuk_gelir": float(spc.min()), "tekrar": M_S2 if uyumlu else 0, "uyumlu": uyumlu, "tohum": TOHUM0 + 1000 * sid,
                               "sure_dk": round((time.time() - t1) / 60, 3),
                               "ogrenici": "gercek durum, gelir besligi x yoksulluk hucrelerinin gozlenen HE090 payindan Bayes ile atandi; gozlenen veriyle bagdasmayan senaryolar simule edilmedi"})
s2_ham = pd.concat(s2_ham, ignore_index=True)
s2_ham.to_csv(SIM / "S2_ham.csv", index=False)
s2_oz = pd.DataFrame(s2_oz)
s2_oz.to_csv(SIM / "S2_ozet.csv", index=False)
s2_oz.assign(**{f"gozlenen_{k}": v for k, v in gozlenen.items()}).to_csv(FV / "fig6b_yanlis_siniflama.csv", index=False)
pd.DataFrame(s2_tani).to_csv(SIM / "S2_tani_eski.csv", index=False)
pd.DataFrame(s2_kf).to_csv(SIM / "S2_kapali_form.csv", index=False)
hucre_tablo.to_csv(SIM / "S2_hucreler.csv", index=False)
risk_tablo.to_csv(SIM / "S2_risk_hucreleri.csv", index=False)
egri = []
for tur in ("ayrimci_degil", "gelire_gore"):
    for se in (0.80, 0.85, 0.90, 0.95):
        for sp in np.round(np.arange(0.9, 1.00001, 0.001), 3):
            spc = sp_hucre(sp, tur)
            egri.append({"tur": tur, "Se": se, "Sp": sp, "kapali_form_dislama_hane": kapali_form(W_c, O_c, se, spc)["dislama_hatasi"],
                         "uyumlu": bool(np.all((p_c >= 1 - spc - 1e-12) & (p_c <= se + 1e-12)))})
pd.DataFrame(egri).assign(uyumlu_en_kucuk_Sp=lambda d: d["tur"].map(uyum_sinir), risk_en_kucuk_Sp=lambda d: d["tur"].map(risk_sinir)).to_csv(FV / "fig6b_kapali_form_egrisi.csv", index=False)
uy = s2_oz[s2_oz["uyumlu"]]
denetim = {"en_buyuk_sim_eksi_kapali_form": float(uy["dislama_eksi_kapali_form"].abs().max()),
           "en_buyuk_Se_sapmasi": float(np.max(np.abs(np.r_[uy["gerceklesen_Se"] - uy["Se"], uy["gerceklesen_Se_Q12"] - uy["Se"], uy["gerceklesen_Se_Q35"] - uy["Se"]]))),
           "en_buyuk_Sp_sapmasi": float(np.max(np.abs(np.r_[uy["gerceklesen_Sp_Q12"] - uy["Sp_dusuk_gelir"], uy["gerceklesen_Sp_Q35"] - uy["Sp"]]))),
           "ayrimci_olmayan_Se_araligi_en_buyuk": float(uy[uy["tur"] == "ayrimci_degil"].groupby("Sp")["dislama_hatasi"].agg(lambda v: v.max() - v.min()).max())}
yaz("S2 bitti. Gozlenen:", {k: round(v, 2) for k, v in gozlenen.items()})
yaz("S2 hucreler:\n" + hucre_tablo.round(2).to_string())
yaz("S2 uyum sinirlari:", {k: round(v, 4) for k, v in uyum_sinir.items()}, "risk ondaliklari:", {k: round(v, 4) for k, v in risk_sinir.items()}, "denetimler:", {k: round(v, 4) for k, v in denetim.items()})
yaz("S2 risk ondaliklari:\n" + risk_tablo.round(2).to_string())
yaz("S2 aralik (uyumlu senaryolar):\n" + uy.groupby("tur")[["dislama_hatasi", "kural_seti_duyarlilik", "yoksulluk_esigi_duyarlilik", "kural_eksi_esik", "lgb_eksi_esik"]].agg(["min", "max"]).round(2).to_string())


def wq(x, ww, pr):
    o = np.argsort(x, kind="mergesort")
    c = np.cumsum(ww[o]) / ww.sum()
    return np.interp(pr, c, x[o])


def rcs(x, k):
    d = (k[-1] - k[0]) ** 2
    out = [x]
    for j_ in range(len(k) - 2):
        out.append((np.maximum(x - k[j_], 0) ** 3 - np.maximum(x - k[-2], 0) ** 3 * (k[-1] - k[j_]) / (k[-1] - k[-2]) + np.maximum(x - k[-1], 0) ** 3 * (k[-2] - k[j_]) / (k[-1] - k[-2])) / d)
    return np.column_stack(out)


def wlojit(X, yy, ww):
    b = np.zeros(X.shape[1])
    for _ in range(100):
        mu = expit(X @ b)
        st = np.linalg.solve(X.T @ (X * (ww * mu * (1 - mu))[:, None]), X.T @ (ww * (yy - mu)))
        b += st
        if np.max(np.abs(st)) < 1e-12:
            break
    return b


def gerceklesen_g(pT, m):
    ww, yy, pp = w[m], y[m], pT[m]
    a, b = np.sum(ww * pp), np.sum(ww * (1 - pp))
    return (float(np.sum(ww * yy * pp) / a) if a > 0 else np.nan), (float(np.sum(ww * (1 - yy) * (1 - pp)) / b) if b > 0 else np.nan)


DEC = risk_kod // 10
z_b = logit(p_ham)
HD = (hix[:, None] == np.arange(len(HUC))[None, :]).astype(float)
B_SEC = {"sabit_dogrusal": (np.column_stack([np.ones_like(z_b), z_b]), None),
         "hucre_dogrusal": (np.column_stack([HD, z_b]), None),
         "hucre_rcs4": (None, np.array([0.05, 0.35, 0.65, 0.95])),
         "hucre_rcs5": (None, np.array([0.05, 0.275, 0.5, 0.725, 0.95]))}
b_kal, b_kal_oz, b_q = [], {}, {}
for ad, (X_, kp) in B_SEC.items():
    dug = wq(z_b, w, kp) if kp is not None else None
    if X_ is None:
        X_ = np.column_stack([HD, rcs(z_b, dug)])
    kat = wlojit(X_, y, w)
    q_ = expit(X_ @ kat)
    b_q[ad] = q_
    sap = []
    for d in range(10):
        m = DEC == d
        sap.append(100 * (np.sum(w[m] * y[m]) - np.sum(w[m] * q_[m])) / w[m].sum())
        b_kal.append({"secenek": ad, "risk_ondaligi": d + 1, "n": int(m.sum()), "gozlenen_FI": 100 * np.sum(w[m] * y[m]) / w[m].sum(), "kalibre_q": 100 * np.sum(w[m] * q_[m]) / w[m].sum()})
    huc_sap = 100 * (O_c - huc_top(w * q_)) / W_c
    b_kal_oz[ad] = {"katsayilar": kat.tolist(), "dugumler_logit": dug.tolist() if dug is not None else None, "ondalik_ort_mutlak_sapma": float(np.mean(np.abs(sap))),
                    "ondalik_en_buyuk_mutlak_sapma": float(np.max(np.abs(sap))), "hucre_en_buyuk_mutlak_sapma": float(np.max(np.abs(huc_sap))),
                    "q_agirlikli_yuzde1": float(wq(q_, w, 0.01)), "q_agirlikli_yuzde99": float(wq(q_, w, 0.99)), "B_en_kucuk_Sp": float(1 - wq(q_, w, 0.01)), "B_en_kucuk_Se": float(wq(q_, w, 0.99))}
B_SECILEN = min((k for k in B_SEC if k.startswith("hucre")), key=lambda k: b_kal_oz[k]["ondalik_ort_mutlak_sapma"])
q_B = b_q[B_SECILEN]
pd.DataFrame(b_kal).assign(fark=lambda d: d["gozlenen_FI"] - d["kalibre_q"], secilen=lambda d: d["secenek"] == B_SECILEN).to_csv(SIM / "S2_B_kalibrasyon.csv", index=False)


def b_olasilik(se, sp_i):
    pi = np.clip((q_B - (1 - sp_i)) / (se + sp_i - 1), 0, 1)
    return np.clip(np.where(y == 1, se * pi / q_B, (1 - se) * pi / (1 - q_B)), 0, 1)


def a_olasilik(se, spc):
    pi_c = (p_c - (1 - spc)) / (se + spc - 1)
    return np.where(y == 1, se * pi_c[hix] / p_c[hix], (1 - se) * pi_c[hix] / (1 - p_c[hix]))


def ondalik_sesp(pT, tasarim, tur, se, sp):
    out = []
    for d in range(10):
        for g, gad in ((None, "tum"), (1, "Q12"), (0, "Q35")):
            m = (DEC == d) if g is None else (DEC == d) & (dusuk_gelir == g)
            if not m.any():
                continue
            s_, p_ = gerceklesen_g(pT, m)
            nom = sp - 0.05 if (tur == "gelire_gore" and g == 1) else (sp if (tur == "ayrimci_degil" or g == 0) else np.nan)
            out.append({"tasarim": tasarim, "tur": tur, "Se": se, "Sp": sp, "risk_ondaligi": d + 1, "gelir_grubu": gad, "n": int(m.sum()), "gozlenen_FI": 100 * np.sum(w[m] * y[m]) / w[m].sum(),
                        "nominal_Se": se, "nominal_Sp": nom, "gerceklesen_Se": s_, "gerceklesen_Sp": p_})
    return out


def simule(pT, rng):
    r = pd.DataFrame([olculer((rng.uniform(size=len(y)) < pT).astype(float)) for _ in range(M_S2)])
    o = {}
    for k in S2_OLCU:
        o[k] = float(r[k].mean())
        o[k + "_alt"] = float(r[k].quantile(0.025))
        o[k + "_ust"] = float(r[k].quantile(0.975))
    return o, r


S2_EK_SE, S2_EK_SP = (0.98, 0.99, 1.0), (0.999, 1.0)
s2_tas, s2_tas_ham, ond_A, ond_B = [], [], [], []
j = 0
for tur in ("ayrimci_degil", "gelire_gore"):
    for izgara, se_l, sp_l in ((True, (0.80, 0.85, 0.90, 0.95), (0.90, 0.92, 0.94, 0.96, 0.98, 0.99)), (False, S2_EK_SE, S2_EK_SP)):
        for se in se_l:
            for sp in sp_l:
                j += 1
                spc = sp_hucre(sp, tur)
                kf = kapali_form(W_c, O_c, se, spc)
                kfk = kapali_form(WK_c, OK_c, se, spc)
                uyA = bool(np.all((p_c >= 1 - spc - 1e-12) & (p_c <= se + 1e-12)))
                sp_i = np.where((dusuk_gelir == 1) & (tur == "gelire_gore"), sp - 0.05, sp)
                alt_b, ust_b = q_B < 1 - sp_i - 1e-12, q_B > se + 1e-12
                ihlal_b = float(100 * np.sum(w * (alt_b | ust_b)) / w.sum())
                uyB = ihlal_b < 1
                satir = {"j": j, "tur": tur, "Se": se, "Sp": sp, "Sp_dusuk_gelir": float(spc.min()), "izgara": izgara, "kapali_form_dislama_hane": kf["dislama_hatasi"], "kapali_form_dislama_kisi": kfk["dislama_hatasi"],
                         "uyumlu_A": uyA, "uyumlu_A_risk_ondaligi": bool(np.all(((p_r >= 1 - np.where(rsk_dusuk & (tur == "gelire_gore"), sp - 0.05, sp) - 1e-12) & (p_r <= se + 1e-12))[rg])),
                         "B_alt_ihlal_payi": float(100 * np.sum(w * alt_b) / w.sum()), "B_ust_ihlal_payi": float(100 * np.sum(w * ust_b) / w.sum()), "B_ihlal_payi": ihlal_b, "uyumlu_B": uyB}
                if uyA:
                    pT = a_olasilik(se, spc)
                    oa = ondalik_sesp(pT, "A", tur, se, sp)
                    ond_A.extend(oa)
                    if izgara:
                        k_ = s2_oz[(s2_oz["tur"] == tur) & (s2_oz["Se"] == se) & (s2_oz["Sp"] == sp)].iloc[0]
                        o = {c: float(k_[c]) for k in S2_OLCU for c in (k, k + "_alt", k + "_ust")}
                    else:
                        o, r = simule(pT, np.random.default_rng([TOHUM0, 1, j]))
                        s2_tas_ham.append(r.assign(tasarim="A", tur=tur, Se=se, Sp=sp, m=np.arange(M_S2)))
                    satir.update({f"A_{k}": v for k, v in o.items()})
                    satir["A_dislama_eksi_kapali_form"] = o["dislama_hatasi"] - kf["dislama_hatasi"]
                    satir["A_ondalik_Se_min"] = min(x["gerceklesen_Se"] for x in oa if x["gelir_grubu"] == "tum" and not np.isnan(x["gerceklesen_Se"]))
                    satir["A_ondalik_Se_max"] = max(x["gerceklesen_Se"] for x in oa if x["gelir_grubu"] == "tum" and not np.isnan(x["gerceklesen_Se"]))
                if uyB:
                    pT = b_olasilik(se, sp_i)
                    ob = ondalik_sesp(pT, "B", tur, se, sp)
                    ond_B.extend(ob)
                    o, r = simule(pT, np.random.default_rng([TOHUM0, 2, j]))
                    s2_tas_ham.append(r.assign(tasarim="B", tur=tur, Se=se, Sp=sp, m=np.arange(M_S2)))
                    satir.update({f"B_{k}": v for k, v in o.items()})
                    satir["B_dislama_eksi_kapali_form"] = o["dislama_hatasi"] - kf["dislama_hatasi"]
                    gs = sesp_satir(pT, "")
                    sap = [abs(gs["Se"] - se), abs(gs["Se_Q12"] - se), abs(gs["Se_Q35"] - se), abs(gs["Sp_Q12"] - float(sp_i[dusuk_gelir == 1][0])), abs(gs["Sp_Q35"] - sp)]
                    sap += [abs(x["gerceklesen_Se"] - se) for x in ob if x["gelir_grubu"] != "tum" and x["n"] >= 100 and not np.isnan(x["gerceklesen_Se"])]
                    sap += [abs(x["gerceklesen_Sp"] - x["nominal_Sp"]) for x in ob if x["gelir_grubu"] != "tum" and x["n"] >= 100 and not np.isnan(x["gerceklesen_Sp"])]
                    satir.update({f"B_gerceklesen_{k}": v for k, v in gs.items()})
                    satir["B_en_buyuk_SeSp_sapmasi"] = float(max(sap))
                s2_tas.append(satir)
s2_tas = pd.DataFrame(s2_tas)
s2_tas.to_csv(SIM / "S2_tasarimlar.csv", index=False)
pd.concat(s2_tas_ham, ignore_index=True).to_csv(SIM / "S2_tasarim_ham.csv", index=False)
pd.DataFrame(ond_A).to_csv(SIM / "S2_A_ondalik_SeSp.csv", index=False)
pd.DataFrame(ond_B).to_csv(SIM / "S2_B_ondalik_SeSp.csv", index=False)
kont = s2_tas[(s2_tas["tur"] == "ayrimci_degil") & (s2_tas["Se"] == 1.0) & (s2_tas["Sp"] == 1.0)].iloc[0]
for k in ("dislama_hatasi", "kural_eksi_esik", "lgb_eksi_esik"):
    assert abs(kont[f"A_{k}"] - gozlenen[k]) < 1e-9 and abs(kont[f"B_{k}"] - gozlenen[k]) < 1e-9, k
uB = s2_tas[s2_tas["uyumlu_B"]]
denetim_B = {"kalibrasyon_secilen": B_SECILEN, "uyumlu_B_izgarada": int(s2_tas[s2_tas["izgara"]]["uyumlu_B"].sum()), "uyumlu_B_toplam": int(len(uB)),
             "en_buyuk_SeSp_sapmasi": float(uB["B_en_buyuk_SeSp_sapmasi"].max()), "en_buyuk_sim_eksi_kapali_form": float(uB["B_dislama_eksi_kapali_form"].abs().max()),
             "en_buyuk_kirpilan_pay": float(uB["B_ihlal_payi"].max())}
yaz("S2 B kalibrasyonu:", B_SECILEN, {k: {a: (round(b, 4) if isinstance(b, float) else b) for a, b in v.items() if a not in ("katsayilar", "dugumler_logit")} for k, v in b_kal_oz.items()})
yaz("S2 iki tasarim:\n" + s2_tas[["tur", "Se", "Sp", "izgara", "kapali_form_dislama_hane", "uyumlu_A", "uyumlu_B", "B_ihlal_payi", "A_kural_eksi_esik", "A_lgb_eksi_esik", "B_kural_eksi_esik", "B_lgb_eksi_esik"]].round(3).to_string())
yaz("S2 B denetimleri:", denetim_B)

t0 = time.time()
p_gercek = p_obs
cs = np.sort(np.unique(cart))[::-1]
pay_kum = np.array([np.sum(w[cart >= c]) / w.sum() for c in cs])
c_pov_hepsi = float(np.sum(w * yoksul) / w.sum())
kural_esik = cs[np.argmax(pay_kum >= c_pov_hepsi)]
bayrak = (cart >= kural_esik).astype(float)
gercek = {"dislama_hatasi": np.sum(w * p_gercek * (1 - yoksul)) / np.sum(w * p_gercek), "kural_duyarlilik": np.sum(w * p_gercek * bayrak) / np.sum(w * p_gercek),
          "kural_ppv": np.sum(w * p_gercek * bayrak) / np.sum(w * bayrak)}
n = len(y)


def s3_veri(s):
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
    nokta = {"dislama_hatasi": a1.sum() / a2.sum(), "kural_duyarlilik": a3.sum() / a2.sum(), "kural_ppv": a3.sum() / a4.sum()}
    b1, b2, b3, b4 = a1 @ M, a2 @ M, a3 @ M, a4 @ M
    bt = {"dislama_hatasi": b1 / b2, "kural_duyarlilik": b3 / b2, "kural_ppv": b3 / b4}
    out = []
    for k in nokta:
        lo, hi = np.percentile(bt[k], [2.5, 97.5])
        out.append({"s": s, "olcu": k, "tahmin": 100 * nokta[k], "alt": 100 * lo, "ust": 100 * hi, "se_boot": 100 * bt[k].std(ddof=1), "gercek": 100 * gercek[k], "kapsadi": int(lo <= gercek[k] <= hi)})
    return out


sid += 1
t1 = time.time()
s3 = Parallel(n_jobs=ISCI, backend="loky")(delayed(s3_veri)(s) for s in range(S_S3))
s3_ham = pd.DataFrame([x for o in s3 for x in o])
s3_ham.to_csv(SIM / "S3_ham.csv", index=False)
s3_oz = s3_ham.groupby("olcu").agg(gercek=("gercek", "first"), ortalama_tahmin=("tahmin", "mean"), ampirik_se=("tahmin", "std"), ortalama_boot_se=("se_boot", "mean"),
                                    kapsama=("kapsadi", "mean"), S=("s", "nunique")).reset_index()
s3_oz["yanlilik"] = s3_oz["ortalama_tahmin"] - s3_oz["gercek"]
s3_oz["kapsama"] = 100 * s3_oz["kapsama"]
s3_oz["kapsama_mcse"] = np.sqrt(s3_oz["kapsama"] * (100 - s3_oz["kapsama"]) / s3_oz["S"])
s3_oz.to_csv(SIM / "S3_ozet.csv", index=False)
s3_oz.to_csv(FV / "fig6c_kapsama.csv", index=False)
senaryolar.append({"sid": sid, "calisma": "S3", "tekrar": S_S3, "bootstrap": B_S3, "tohum": TOHUM0 + 500000, "sure_dk": round((time.time() - t1) / 60, 2),
                   "ogrenici": "sozde nufus = 2025 haneleri (HB040), gercek olasilik = kesim kalibreli LightGBM A1; esit olasilikli iadeli cekim; Rao-Wu n-1 bootstrap"})
yaz("S3 ozet:\n" + s3_oz.round(3).to_string())

pd.DataFrame(senaryolar).to_csv(SIM / "senaryo_tablosu.csv", index=False)
ozet = pd.concat([s1_oz.assign(calisma="S1"), s2_oz.assign(calisma="S2"), s3_oz.assign(calisma="S3")], ignore_index=True)
ozet.to_csv(SIM / "simulasyon_ozet.csv", index=False)
json.dump({"mod": MOD, "R_S1": R_S1, "M_S2": M_S2, "S_S3": S_S3, "B_S3": B_S3, "toplam_dk": round((time.time() - T_BAS) / 60, 2), "gozlenen": gozlenen, "kural_esik_S3": float(kural_esik),
           "S2_uyum_sinirlari": uyum_sinir, "S2_risk_ondaligi_sinirlari": risk_sinir, "S2_denetim": denetim, "S2_B_kalibrasyon": b_kal_oz, "S2_B_denetim": denetim_B,
           "S2_ek_senaryolar": {"Se": list(S2_EK_SE), "Sp": list(S2_EK_SP), "tohum": "numpy SeedSequence (20261101, tasarim 1=A 2=B, senaryo sirasi j)"}},
          open(SIM / "simulasyon_bilgi.json", "w"), indent=2, default=float)
yaz("simulasyon.py bitti. Toplam (dk):", round((time.time() - T_BAS) / 60, 2))
