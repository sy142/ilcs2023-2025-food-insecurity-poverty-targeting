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
    return out


gozlenen = olculer(y)
s2_ham = []
s2_oz = []
for tur in ("ayrimci_degil", "gelire_gore"):
    for se in (0.80, 0.85, 0.90, 0.95):
        for sp in (0.90, 0.92, 0.94, 0.96, 0.98, 0.99):
            sid += 1
            t1 = time.time()
            sp_i = np.where(dusuk_gelir == 1, sp - 0.05, sp) if tur == "gelire_gore" else np.full(len(y), sp)
            se_i = np.full(len(y), se)
            pi = np.clip((p_obs - (1 - sp_i)) / (se_i + sp_i - 1), 0.001, 0.999)
            po = se_i * pi + (1 - sp_i) * (1 - pi)
            p1 = se_i * pi / po
            p0 = (1 - se_i) * pi / (1 - po)
            pT = np.where(y == 1, p1, p0)
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
            satir = {"sid": sid, "tur": tur, "Se": se, "Sp": sp, "M": M_S2}
            for k in ("dislama_hatasi", "FI_yoksul_icinde", "FI_yayginligi", "kural_seti_duyarlilik", "lgb_A1_duyarlilik", "yoksulluk_esigi_duyarlilik", "kural_eksi_esik"):
                satir[k] = float(r[k].mean())
                satir[k + "_alt"] = float(r[k].quantile(0.025))
                satir[k + "_ust"] = float(r[k].quantile(0.975))
            s2_oz.append(satir)
            senaryolar.append({"sid": sid, "calisma": "S2", "tur": tur, "Se": se, "Sp": sp, "Sp_dusuk_gelir": sp - 0.05 if tur == "gelire_gore" else sp, "tekrar": M_S2, "tohum": TOHUM0 + 1000 * sid,
                               "sure_dk": round((time.time() - t1) / 60, 3), "ogrenici": "gercek durum, 2025 LightGBM A1 olasiliklarindan (kesim kalibreli) Bayes ile atandi"})
s2_ham = pd.concat(s2_ham, ignore_index=True)
s2_ham.to_csv(SIM / "S2_ham.csv", index=False)
s2_oz = pd.DataFrame(s2_oz)
s2_oz.to_csv(SIM / "S2_ozet.csv", index=False)
s2_oz.assign(**{f"gozlenen_{k}": v for k, v in gozlenen.items()}).to_csv(FV / "fig6b_yanlis_siniflama.csv", index=False)
yaz("S2 bitti. Gozlenen:", {k: round(v, 2) for k, v in gozlenen.items()})
yaz("S2 aralik:\n" + s2_oz.groupby("tur")[["dislama_hatasi", "kural_seti_duyarlilik", "yoksulluk_esigi_duyarlilik", "kural_eksi_esik"]].agg(["min", "max"]).round(2).to_string())

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
json.dump({"mod": MOD, "R_S1": R_S1, "M_S2": M_S2, "S_S3": S_S3, "B_S3": B_S3, "toplam_dk": round((time.time() - T_BAS) / 60, 2), "gozlenen": gozlenen, "kural_esik_S3": float(kural_esik)},
          open(SIM / "simulasyon_bilgi.json", "w"), indent=2, default=float)
yaz("simulasyon.py bitti. Toplam (dk):", round((time.time() - T_BAS) / 60, 2))
