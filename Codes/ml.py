import gzip
import hashlib
import json
import pickle
import sys
import time
import warnings
from pathlib import Path

import lightgbm as lgb
import numpy as np
import pandas as pd
from joblib import Parallel, delayed
from scipy import sparse
from scipy.stats import norm, spearmanr
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import StratifiedKFold
from sklearn.preprocessing import SplineTransformer
from sklearn.tree import DecisionTreeClassifier

warnings.filterwarnings("ignore", category=UserWarning)

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data"
MLD = VERI / "ml"
OB = VERI / "onbellek" / "ml"
SON = KOK / "Results"
EK = SON / "Supplementary"
LOG = SON / "log"
FV = VERI / "figur_verileri"
for k in (MLD, OB, FV, LOG, EK):
    k.mkdir(parents=True, exist_ok=True)
TOHUM = 20261026
TOHUMLAR = [TOHUM + i for i in range(5)]
ISCI = 16
B_BOOT = 8000
B_YARIM = B_BOOT // 2
N_KONFIG = 60
T_BAS = time.time()
ETK = json.loads((KOK / "Codes" / "etiketler.json").read_text(encoding="utf-8"))
SURE = []


def yaz(*a):
    print(f"[{(time.time() - T_BAS) / 60:6.1f} dk]", *a, flush=True)


def sure_kaydet(adim, t0):
    SURE.append({"adim": adim, "dakika": round((time.time() - t0) / 60, 2), "yer": "CPU"})


T1 = ["log_goreli_gelir", "hane_gelir_dilim5", "pay_ucret", "pay_mutesebbis", "pay_emekli", "pay_sosyal", "pay_ozel_transfer",
      "sosyal_yardim_var", "ozel_transfer_var", "kira_geliri_var", "kira_orani"]
T2 = ["reis_yas", "hane_buyuklugu", "n_cocuk", "n_0_5", "n_65plus", "n_75plus", "n_yetiskin", "n_kronik", "n_gali", "n_kotu_saglik",
      "n_karsilanmayan", "n_calisan", "n_issiz", "n_emekli", "n_ev_isi", "n_kayitsiz", "n_yevmiyeli", "n_gecici", "calisan_oran",
      "bagimli_oran", "is_yogunlugu", "HH060", "HH070", "m2_kisi", "goreli_kira",
      "HB031", "HB050", "reis_cinsiyet", "reis_medeni", "reis_calisma7", "reis_egitim", "egitim_max", "egitim_min", "reis_saglik",
      "reis_kronik", "reis_gali", "tek_yetiskin_cocuklu", "HH010", "HH020", "HH080", "HH100", "HH110", "HH120", "HH145",
      "HH180_var", "HH190_var", "HH200_var", "HH220_var", "HH230_var", "HH240_var",
      "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070", "kalabalik_konut", "ciddi_konut_yoksunlugu"]
T3 = ["HE040", "HE010", "HE020", "HE030", "HE060", "HE070", "he050_orani"]
T4 = ["HE080", "HE100", "HE110", "HE120", "HH180", "HH190", "HH200", "HH220", "HH230", "HH240",
      "msy_internet", "msy_giysi", "msy_ayakkabi", "msy_harclik", "msy_bos_zaman", "msy_arkadas_aile"]
T2_IDARI = ["reis_yas", "hane_buyuklugu", "n_cocuk", "n_0_5", "n_65plus", "n_75plus", "n_yetiskin", "n_calisan", "n_issiz",
            "n_emekli", "n_kayitsiz", "calisan_oran", "is_yogunlugu", "HB030", "HB050", "reis_cinsiyet", "reis_medeni",
            "reis_calisma7", "reis_egitim", "egitim_max", "egitim_min", "tek_yetiskin_cocuklu", "HH010", "HH020", "HH240_var"]
T2_HB030 = [v if v != "HB031" else "HB030" for v in T2]
NOMINAL = {"HB030", "HB031", "HB050", "reis_medeni", "reis_calisma7", "HH010", "HH020", "HH080", "HH100", "HH110",
           "HE010", "HE020", "HE030", "HE070", "HE120", "HH180", "HH190", "HH200", "HH220", "HH230", "HH240"}
SIRALI = {"hane_gelir_dilim5", "reis_egitim", "egitim_max", "egitim_min", "reis_saglik", "reis_gali", "HE040", "HE060", "HH145"}
SAYIM = {"hane_buyuklugu", "n_cocuk", "n_0_5", "n_65plus", "n_75plus", "n_yetiskin", "n_kronik", "n_gali", "n_kotu_saglik",
         "n_karsilanmayan", "n_calisan", "n_issiz", "n_emekli", "n_ev_isi", "n_kayitsiz", "n_yevmiyeli", "n_gecici", "HH060"}
SPLINE = ["log_goreli_gelir", "reis_yas", "is_yogunlugu", "m2_kisi", "he050_orani", "goreli_kira"]
SETLER = {
    "A1": ("A", T1 + T2), "A2": ("A", T2), "A3": ("A", T1 + T2 + T3), "A4": ("A", T1 + T2 + T3 + T4),
    "B1": ("B", T2 + ["log_goreli_gelir"]), "B2": ("B", T2), "B3": ("B", T2 + ["log_goreli_gelir"] + T3),
    "A2i": ("A", T2_IDARI),
}
SET_ACIKLAMA = {
    "A1": "All households; income + structural (T1 + T2)", "A2": "All households; structural only (T2)",
    "A3": "All households; T1 + T2 + financial strain (T3)", "A4": "All households; T1 + T2 + T3 + deprivation items (T4), upper bound",
    "B1": "Non-poor households; structural + relative income", "B2": "Non-poor households; structural only",
    "B3": "Non-poor households; structural + relative income + financial strain", "A2i": "All households; register-like subset of structural features",
}

def ozellik_ozeti(feats):
    return hashlib.md5(",".join(feats).encode()).hexdigest()[:8]


h = pd.read_parquet(VERI / "hane_2023_2025.parquet")
h["HB031"] = h["HB031"].astype(str)
h["HB030"] = h["HB030"].astype(str)
h["dusuk_is_e"] = h["dusuk_is_yogunlugu"].fillna(0).astype(int)
h["e_yoksul_60"] = h["yoksul"].astype(int)
h["e_yoksul_50"] = h["yoksul_50"].astype(int)
h["e_yoksul_70"] = h["yoksul_70"].astype(int)
h["e_msy_etsiz_5"] = h["msy_etsiz_5"].astype(int)
h["e_dusuk_is"] = h["dusuk_is_e"]
h["w"] = h["HB040"] / h.groupby("yil")["HB040"].transform("mean")
yaz("Hane verisi:", h.shape, h.groupby("yil").size().to_dict())
egitim_yillari = h["yil"].isin([2023, 2024])
h["n_cocuk_ham"] = h["n_cocuk"].copy()
kodlama = []
for v in sorted(set(T1 + T2 + T3 + T4 + T2_IDARI)):
    x = h[v]
    if v in NOMINAL or v in SIRALI:
        tr = h.loc[egitim_yillari, [v, "FI"]].dropna()
        say = tr.groupby(v)["FI"].agg(["size", "sum"])
        say["olaysiz"] = say["size"] - say["sum"]
        seyrek = say.index[(say["size"] < 100) | (say["sum"] < 10) | (say["olaysiz"] < 10)].tolist()
        if seyrek:
            sirali = sorted(say.index.tolist(), key=lambda z: float(z) if not isinstance(z, str) else z)
            if v in SIRALI:
                esleme = {}
                for s in seyrek:
                    i = sirali.index(s)
                    adaylar = [k for k in sirali if k not in seyrek]
                    hedef = min(adaylar, key=lambda k: abs(sirali.index(k) - i))
                    esleme[s] = hedef
            else:
                mod = say.drop(index=seyrek)["size"].idxmax()
                esleme = {s: mod for s in seyrek}
            h[v] = h[v].replace(esleme)
            for s, t in esleme.items():
                kodlama.append({"degisken": v, "kod": s, "birlestirildigi_kod": t, "n_egitim": int(say.loc[s, "size"]), "olay_egitim": int(say.loc[s, "sum"])})
    elif v in SAYIM:
        tr = h.loc[egitim_yillari, v].dropna()
        degerler = np.sort(tr.unique())
        ust = degerler[-1]
        for k in degerler[::-1]:
            if (tr >= k).sum() >= 100:
                ust = k
                break
        if ust < degerler[-1]:
            n_ust = int((h[v] > ust).sum())
            h[v] = h[v].clip(upper=ust)
            kodlama.append({"degisken": v, "kod": f">{ust:g}", "birlestirildigi_kod": f"{ust:g}", "n_egitim": int((tr > ust).sum()), "olay_egitim": None, "n_tum_yillar": n_ust})
pd.DataFrame(kodlama).to_csv(SON / "H2_seyrek_kategori_birlestirme.csv", index=False)
yaz("Seyrek kategori / ust kodlama satiri:", len(kodlama))

KAT_SIRA = {}
for v in NOMINAL:
    if v in h:
        KAT_SIRA[v] = sorted(h[v].dropna().unique().tolist(), key=lambda z: str(z))


def lgb_X(df, feats):
    X = df[feats].copy()
    for v in feats:
        if v in NOMINAL:
            X[v] = pd.Categorical(X[v], categories=KAT_SIRA[v])
        else:
            X[v] = X[v].astype(float)
    return X


def nufus(df, pop):
    return df if pop == "A" else df[df["yoksul"] == 0]


def wlogloss(y, p, w):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return float(-np.sum(w * (y * np.log(p) + (1 - y) * np.log(1 - p))) / np.sum(w))


def auc_w(s, y, w):
    o = np.argsort(s, kind="mergesort")
    s, y, w = s[o], y[o], w[o]
    u, inv = np.unique(s, return_inverse=True)
    w1 = np.bincount(inv, weights=w * y)
    w0 = np.bincount(inv, weights=w * (1 - y))
    c0 = np.cumsum(w0) - w0
    return float(np.sum(w1 * (c0 + 0.5 * w0)) / (w1.sum() * w0.sum()))


def kat_listesi(feats):
    return [v for v in feats if v in NOMINAL]


def lgb_egit(Xtr, ytr, wtr, par, n_tur, tohum, Xva=None, yva=None, wva=None, isci=1, es=100):
    p = {"objective": "binary", "verbosity": -1, "num_threads": isci, "seed": tohum, "bagging_freq": 1,
         "deterministic": True, "force_col_wise": True, "feature_pre_filter": False}
    p.update(par)
    dtr = lgb.Dataset(Xtr, ytr, weight=wtr, categorical_feature=kat_listesi(list(Xtr.columns)), free_raw_data=False)
    if Xva is not None:
        dva = lgb.Dataset(Xva, yva, weight=wva, reference=dtr, categorical_feature=kat_listesi(list(Xtr.columns)))
        b = lgb.train(p, dtr, num_boost_round=n_tur, valid_sets=[dva], callbacks=[lgb.early_stopping(es, verbose=False)])
    else:
        b = lgb.train(p, dtr, num_boost_round=n_tur)
    return b


def konfig_uret(n, rng):
    out = []
    for i in range(n):
        out.append({
            "num_leaves": int(rng.integers(8, 129)),
            "min_data_in_leaf": int(rng.integers(20, 401)),
            "learning_rate": float(np.exp(rng.uniform(np.log(0.01), np.log(0.1)))),
            "feature_fraction": float(rng.uniform(0.4, 1.0)),
            "bagging_fraction": float(rng.uniform(0.5, 1.0)),
            "lambda_l2": float(np.exp(rng.uniform(np.log(1e-3), np.log(20.0)))),
            "max_depth": int(rng.choice([-1, 4, 6, 8, 10])),
        })
    return out


INCE_SINIR = {"num_leaves": (24, 256), "min_data_in_leaf": (10, 200), "learning_rate": (0.004, 0.03), "lambda_l2": (0.01, 30.0), "lambda_l1": (0.01, 5.0), "cat_smooth": (1.0, 50.0)}


def konfig_uret_ince(n, rng):
    out = []
    for i in range(n):
        out.append({
            "num_leaves": int(np.round(np.exp(rng.uniform(*np.log(INCE_SINIR["num_leaves"]))))),
            "min_data_in_leaf": int(np.round(np.exp(rng.uniform(*np.log(INCE_SINIR["min_data_in_leaf"]))))),
            "learning_rate": float(np.exp(rng.uniform(*np.log(INCE_SINIR["learning_rate"])))),
            "feature_fraction": float(rng.uniform(0.5, 1.0)),
            "bagging_fraction": float(rng.uniform(0.6, 1.0)),
            "lambda_l2": float(np.exp(rng.uniform(*np.log(INCE_SINIR["lambda_l2"])))),
            "lambda_l1": float(0.0 if rng.uniform() < 0.5 else np.exp(rng.uniform(*np.log(INCE_SINIR["lambda_l1"])))),
            "min_gain_to_split": float(rng.choice([0.0, 0.0, 0.01, 0.05])),
            "cat_smooth": float(np.exp(rng.uniform(*np.log(INCE_SINIR["cat_smooth"])))),
            "max_depth": int(rng.choice([8, 10, 12, 14, -1])),
        })
    return out


KONFIGLER = konfig_uret(N_KONFIG, np.random.default_rng(TOHUM)) + konfig_uret_ince(N_KONFIG, np.random.default_rng(TOHUM + 1))
ASAMA = ["1 genis"] * N_KONFIG + ["2 ince"] * N_KONFIG
EK_TOHUM = [TOHUM + 101, TOHUM + 102]
EN_IYI_K = 5


def sabir(par):
    return max(100, int(round(2.0 / par["learning_rate"])))


def katlar(pop):
    d = nufus(h, pop)
    k1_tr = d[d["yil"] == 2023]
    k1_va = d[(d["yil"] == 2024) & (d["eslesen_onceki_yil"] == 0)]
    k2_tr = d[d["yil"] == 2024]
    k2_va = d[(d["yil"] == 2023) & (d["eslesen_sonraki_yil"] == 0)]
    return [("2023->2024", k1_tr, k1_va), ("2024->2023", k2_tr, k2_va)]


def ayar_gorevi(feats, ki, par, kat_ad, tr, va, tohum=TOHUM):
    b = lgb_egit(lgb_X(tr, feats), tr["FI"].values, tr["w"].values, par, 10000, tohum,
                 lgb_X(va, feats), va["FI"].values, va["w"].values, isci=1, es=sabir(par))
    p = b.predict(lgb_X(va, feats), num_iteration=b.best_iteration)
    return {"konfig": ki, "kat": kat_ad, "tohum": tohum, "best_iter": int(b.best_iteration), "logloss": wlogloss(va["FI"].values, p, va["w"].values),
            "auc": auc_w(p, va["FI"].values, va["w"].values)}


def lgb_ayar(set_ad):
    f = OB / f"ayar_{set_ad}_{ozellik_ozeti(SETLER[set_ad][1])}.csv"
    if f.exists():
        return pd.read_csv(f, float_precision="round_trip")
    t0 = time.time()
    pop, feats = SETLER[set_ad]
    kk = katlar(pop)
    sut = feats + ["FI", "w"]
    gorev = [(ki, par, ka, tr[sut], va[sut]) for ki, par in enumerate(KONFIGLER) for (ka, tr, va) in kk]
    gorev.sort(key=lambda g: g[1]["learning_rate"])
    res = Parallel(n_jobs=ISCI, backend="loky")(delayed(ayar_gorevi)(feats, ki, par, ka, tr, va) for (ki, par, ka, tr, va) in gorev)
    r = pd.DataFrame(res)
    r["asama"] = r["konfig"].map(lambda k: ASAMA[k])
    oz = r.groupby("konfig")["logloss"].mean().sort_values()
    en_iyiler = oz.index[:EN_IYI_K].tolist()
    gorev3 = [(ki, KONFIGLER[ki], ka, tr[sut], va[sut], t) for ki in en_iyiler for (ka, tr, va) in kk for t in EK_TOHUM]
    res3 = Parallel(n_jobs=ISCI, backend="loky")(delayed(ayar_gorevi)(feats, ki, par, ka, tr, va, t) for (ki, par, ka, tr, va, t) in gorev3)
    r3 = pd.DataFrame(res3)
    r3["asama"] = "3 tohum"
    r = pd.concat([r, r3], ignore_index=True)
    r["set"] = set_ad
    r.to_csv(f, index=False)
    sure_kaydet(f"LightGBM ayari {set_ad} ({len(gorev) + len(gorev3)} model)", t0)
    yaz(f"Ayar {set_ad}: {len(gorev) + len(gorev3)} model, {(time.time() - t0) / 60:.1f} dk")
    return r


HP_SUT = ["num_leaves", "min_data_in_leaf", "learning_rate", "feature_fraction", "bagging_fraction", "lambda_l2", "max_depth", "lambda_l1", "min_gain_to_split", "cat_smooth"]
HP_TAM = {"num_leaves", "min_data_in_leaf", "max_depth"}
GENIS_SINIR = {"num_leaves": (8, 512), "min_data_in_leaf": (2, 400), "learning_rate": (0.002, 0.1), "lambda_l2": (1e-3, 100.0)}


def par_ekle(r):
    if "num_leaves" in r.columns:
        return r
    kp = pd.DataFrame([dict(konfig=i, **k) for i, k in enumerate(KONFIGLER)])
    return r.merge(kp, on="konfig", how="left")


def par_al(r, k):
    sat = r[r["konfig"] == k].iloc[0]
    par = {}
    for c in HP_SUT:
        if c in sat and pd.notna(sat[c]):
            par[c] = int(sat[c]) if c in HP_TAM else float(sat[c])
    return par


def en_iyi(r):
    tek = r[r["tohum"] == TOHUM].groupby("konfig").agg(logloss=("logloss", "mean"), auc=("auc", "mean"), best_iter=("best_iter", "mean")).reset_index()
    cok = r.groupby("konfig").agg(logloss=("logloss", "mean"), logloss_sd=("logloss", "std"), auc=("auc", "mean"), best_iter=("best_iter", "mean"), n=("logloss", "size")).reset_index()
    cok = cok[cok["n"] >= 6]
    k = int(cok.loc[cok["logloss"].idxmin(), "konfig"])
    sec = r[r["konfig"] == k]
    it = sec.groupby("kat")["best_iter"].mean().round().astype(int).to_dict()
    return k, par_al(r, k), int(round(sec["best_iter"].mean())), it, tek, cok


def sinir_kontrol(par, sinir=INCE_SINIR):
    uyari = []
    if par["learning_rate"] <= sinir["learning_rate"][0] * 1.15:
        uyari.append("learning_rate alt sinirda")
    if par["num_leaves"] >= sinir["num_leaves"][1] * 0.9:
        uyari.append("num_leaves ust sinirda")
    if par["min_data_in_leaf"] <= sinir["min_data_in_leaf"][0] * 1.15 + 0.5:
        uyari.append("min_data_in_leaf alt sinirda")
    if par.get("lambda_l2", 1) >= sinir["lambda_l2"][1] * 0.85:
        uyari.append("lambda_l2 ust sinirda")
    return "; ".join(uyari) if uyari else "yok"


def konfig_genislet(baz, n, rng, uyari):
    out = []
    for i in range(n):
        c = dict(baz)
        c["num_leaves"] = int(np.clip(np.round(baz["num_leaves"] * np.exp(rng.normal(0.3 if "num_leaves" in uyari else 0.0, 0.4))), *GENIS_SINIR["num_leaves"]))
        c["min_data_in_leaf"] = int(np.clip(np.round(baz["min_data_in_leaf"] * np.exp(rng.normal(-0.5 if "min_data" in uyari else 0.0, 0.5))), *GENIS_SINIR["min_data_in_leaf"]))
        c["learning_rate"] = float(np.clip(baz["learning_rate"] * np.exp(rng.normal(-0.4 if "learning_rate" in uyari else 0.0, 0.35)), *GENIS_SINIR["learning_rate"]))
        c["lambda_l2"] = float(np.clip(baz.get("lambda_l2", 1.0) * np.exp(rng.normal(0.4 if "lambda_l2" in uyari else 0.0, 0.8)), *GENIS_SINIR["lambda_l2"]))
        c["feature_fraction"] = float(np.clip(baz["feature_fraction"] + rng.normal(0, 0.08), 0.3, 1.0))
        c["bagging_fraction"] = float(np.clip(baz["bagging_fraction"] + rng.normal(0, 0.08), 0.4, 1.0))
        c["lambda_l1"] = float(np.clip(baz.get("lambda_l1", 0.0) * np.exp(rng.normal(0, 0.8)), 0.0, 10.0))
        c["min_gain_to_split"] = float(baz.get("min_gain_to_split", 0.0))
        c["cat_smooth"] = float(np.clip(baz.get("cat_smooth", 10.0) * np.exp(rng.normal(0, 0.5)), 1.0, 100.0))
        c["max_depth"] = int(baz["max_depth"])
        out.append(c)
    return out


def lgb_genislet(set_ad, r):
    f = OB / f"ayar4_{set_ad}_{ozellik_ozeti(SETLER[set_ad][1])}.csv"
    if f.exists():
        r4 = pd.read_csv(f, float_precision="round_trip")
        return pd.concat([r, r4], ignore_index=True) if len(r4) else r
    pop, feats = SETLER[set_ad]
    kk = katlar(pop)
    sut = feats + ["FI", "w"]
    ek = []
    for tur in (1, 2):
        rr = pd.concat([r] + ek, ignore_index=True)
        k, par, _, _, _, _ = en_iyi(rr)
        uyari = sinir_kontrol(par, INCE_SINIR if tur == 1 else GENIS_SINIR)
        if uyari == "yok":
            break
        t0 = time.time()
        yeni = konfig_genislet(par, 30, np.random.default_rng(TOHUM + 400 + tur), uyari)
        ids = [1000 * tur + i for i in range(len(yeni))]
        gorev = [(ki, c, ka, tr[sut], va[sut]) for ki, c in zip(ids, yeni) for (ka, tr, va) in kk]
        gorev.sort(key=lambda g: g[1]["learning_rate"])
        res = pd.DataFrame(Parallel(n_jobs=ISCI, backend="loky")(delayed(ayar_gorevi)(feats, ki, c, ka, tr, va) for (ki, c, ka, tr, va) in gorev))
        pk = pd.DataFrame([dict(konfig=i, **c) for i, c in zip(ids, yeni)])
        res = res.merge(pk, on="konfig")
        en = res.groupby("konfig")["logloss"].mean().sort_values().index[:3].tolist()
        gorev3 = [(ki, dict(pk[pk["konfig"] == ki].iloc[0][HP_SUT].to_dict()), ka, tr[sut], va[sut], t) for ki in en for (ka, tr, va) in kk for t in EK_TOHUM]
        for g in gorev3:
            for c in HP_TAM:
                g[1][c] = int(g[1][c])
        res3 = pd.DataFrame(Parallel(n_jobs=ISCI, backend="loky")(delayed(ayar_gorevi)(feats, ki, c, ka, tr, va, t) for (ki, c, ka, tr, va, t) in gorev3)).merge(pk, on="konfig")
        res["asama"] = f"4 genisletme {tur}"
        res3["asama"] = f"4 genisletme {tur} tohum"
        ek += [res, res3]
        sure_kaydet(f"LightGBM sinir genisletme {set_ad} tur {tur} ({len(gorev) + len(gorev3)} model)", t0)
        yaz(f"Genisletme {set_ad} tur {tur} ({uyari}): {len(gorev) + len(gorev3)} model, {(time.time() - t0) / 60:.1f} dk")
    ekdf = pd.concat(ek, ignore_index=True) if ek else pd.DataFrame(columns=r.columns)
    ekdf["set"] = set_ad
    ekdf.to_csv(f, index=False)
    return pd.concat([r, ekdf], ignore_index=True) if ek else r


ayarlar = {}
ayar_duy = []
ayar_tum = []
for s in SETLER:
    r = lgb_genislet(s, par_ekle(lgb_ayar(s)))
    ayar_tum.append(r)
    k, par, n_tur, it, tek, cok = en_iyi(r)
    asama_k = r.loc[r["konfig"] == k, "asama"].iloc[0]
    son_sinir = GENIS_SINIR if (r["asama"].astype(str).str.startswith("4")).any() else INCE_SINIR
    ayarlar[s] = {"konfig": k, "asama": asama_k, "par": par, "n_tur": n_tur, "iter_kat": it, "logloss_cv": float(cok.loc[cok["konfig"] == k, "logloss"].iloc[0]),
                  "logloss_cv_sd": float(cok.loc[cok["konfig"] == k, "logloss_sd"].iloc[0]), "auc_cv": float(cok.loc[cok["konfig"] == k, "auc"].iloc[0]),
                  "logloss_asama1_en_iyi": float(tek[tek["konfig"] < N_KONFIG]["logloss"].min()),
                  "logloss_asama2_en_iyi": float(tek[(tek["konfig"] >= N_KONFIG) & (tek["konfig"] < 2 * N_KONFIG)]["logloss"].min()),
                  "logloss_asama4_en_iyi": float(tek[tek["konfig"] >= 1000]["logloss"].min()) if (tek["konfig"] >= 1000).any() else np.nan,
                  "sinir": sinir_kontrol(par, son_sinir)}
    kp = r[r["tohum"] == TOHUM].groupby("konfig").agg(logloss=("logloss", "mean"), **{hp: (hp, "first") for hp in HP_SUT}).reset_index()
    for hp in HP_SUT:
        x = kp[hp].fillna(0 if hp in ("lambda_l1", "min_gain_to_split") else 10.0)
        ayar_duy.append({"set": s, "hiperparametre": hp, "spearman_logloss": float(spearmanr(x, kp["logloss"]).statistic)})
    yaz(s, "secilen konfig", k, f"({asama_k})", "n_tur", n_tur, "logloss", round(ayarlar[s]["logloss_cv"], 4), "+-", round(ayarlar[s]["logloss_cv_sd"], 4),
        "auc", round(ayarlar[s]["auc_cv"], 4), "| asama 1/2/4 en iyi", round(ayarlar[s]["logloss_asama1_en_iyi"], 4), round(ayarlar[s]["logloss_asama2_en_iyi"], 4),
        round(ayarlar[s]["logloss_asama4_en_iyi"], 4), "| sinir:", ayarlar[s]["sinir"], "|", par)
pd.DataFrame(ayar_duy).to_csv(LOG / "H2_ayar_duyarlilik.csv", index=False)
ayar_tab = []
for s, a in ayarlar.items():
    satir = {"set": s, "aciklama": SET_ACIKLAMA[s], "n_ozellik": len(SETLER[s][1]), "secilen_konfig": a["konfig"], "asama": a["asama"], "n_tur_final": a["n_tur"],
             "best_iter_2023_2024": a["iter_kat"].get("2023->2024"), "best_iter_2024_2023": a["iter_kat"].get("2024->2023"),
             "cv_logloss": a["logloss_cv"], "cv_logloss_sd_tohum_kat": a["logloss_cv_sd"], "cv_auc": a["auc_cv"],
             "asama1_en_iyi_logloss": a["logloss_asama1_en_iyi"], "asama2_en_iyi_logloss": a["logloss_asama2_en_iyi"], "asama4_en_iyi_logloss": a["logloss_asama4_en_iyi"], "sinir_kontrolu": a["sinir"]}
    satir.update({"lambda_l1": 0.0, "min_gain_to_split": 0.0, "cat_smooth": 10.0})
    satir.update(a["par"])
    ayar_tab.append(satir)
pd.DataFrame(ayar_tab).to_csv(SON / "H2_hiperparametreler.csv", index=False)
pd.concat(ayar_tum, ignore_index=True).to_csv(SON / "H2_ayar_tum_konfigler.csv", index=False)
pd.DataFrame([dict(konfig=i, asama=ASAMA[i], **k) for i, k in enumerate(KONFIGLER)]).to_csv(SON / "H2_arama_uzayi_konfigler.csv", index=False)
(MLD / "ozellik_setleri.json").write_text(json.dumps({**{k: v[1] for k, v in SETLER.items()}, "katmanlar": {"T1": T1, "T2": T2, "T3": T3, "T4": T4, "T2_idari": T2_IDARI}}, indent=1), encoding="utf-8")


def lgb_nihai(set_ad, egitim_yil, ad, tohumlar=TOHUMLAR, n_tur=None):
    a = ayarlar[set_ad]
    nt = n_tur if n_tur is not None else a["n_tur"]
    f = OB / f"model_{ad}_k{a['konfig']}_t{nt}_{ozellik_ozeti(SETLER[set_ad][1])}.pkl"
    if f.exists():
        return pickle.loads(f.read_bytes())
    pop, feats = SETLER[set_ad]
    d = nufus(h, pop)
    tr = d[d["yil"].isin(egitim_yil)]
    modeller = Parallel(n_jobs=len(tohumlar), backend="loky")(
        delayed(lgb_egit)(lgb_X(tr, feats), tr["FI"].values, tr["w"].values, a["par"], nt, t, isci=max(1, ISCI // len(tohumlar))) for t in tohumlar)
    paket = {"modeller": [m.model_to_string() for m in modeller], "feats": feats, "n_tur": nt, "set": set_ad, "egitim": egitim_yil}
    f.write_bytes(pickle.dumps(paket))
    return paket


def paket_tahmin(paket, df, logit=False, tek=False):
    X = lgb_X(df, paket["feats"])
    ps = [lgb.Booster(model_str=m).predict(X, raw_score=logit) for m in paket["modeller"]]
    if tek:
        return np.vstack(ps)
    return np.mean(ps, axis=0)


t0 = time.time()
paketler = {}
for s in SETLER:
    paketler[s] = lgb_nihai(s, [2023, 2024], f"{s}_2023_2024")
paketler["A1_2023"] = lgb_nihai("A1", [2023], "A1_2023", n_tur=ayarlar["A1"]["iter_kat"]["2023->2024"])
paketler["B1_2023"] = lgb_nihai("B1", [2023], "B1_2023", n_tur=ayarlar["B1"]["iter_kat"]["2023->2024"])
sure_kaydet("LightGBM nihai modeller (5 tohum)", t0)
yaz("Nihai LightGBM modelleri hazir")

BICIM_SETLER = ("A1", "A2")
N_BICIM = 60
BICIM_TUR_TAVAN = 30000
BICIM_SINIR = {"learning_rate": (0.005, 0.3), "num_leaves": (2, 32), "min_data_in_leaf": (5, 500)}


def konfig_uret_bicim(n, rng, tur):
    out = []
    for i in range(n):
        c = {"learning_rate": float(np.exp(rng.uniform(*np.log(BICIM_SINIR["learning_rate"])))),
             "min_data_in_leaf": int(np.round(np.exp(rng.uniform(*np.log(BICIM_SINIR["min_data_in_leaf"]))))),
             "feature_fraction": float(rng.uniform(0.3, 1.0)),
             "bagging_fraction": float(rng.uniform(0.5, 1.0)),
             "lambda_l2": float(np.exp(rng.uniform(np.log(1e-3), np.log(100.0)))),
             "lambda_l1": float(0.0 if rng.uniform() < 0.5 else np.exp(rng.uniform(np.log(0.01), np.log(5.0)))),
             "min_gain_to_split": 0.0,
             "cat_smooth": float(np.exp(rng.uniform(np.log(1.0), np.log(100.0))))}
        c["num_leaves"] = int(np.round(np.exp(rng.uniform(*np.log(BICIM_SINIR["num_leaves"]))))) if tur == "ek" else 4
        c["max_depth"] = -1 if tur == "ek" else 2
        out.append(c)
    return out


def bicim_par(par, tur, feats):
    p = dict(par)
    if tur == "ek":
        p["interaction_constraints"] = [[j] for j in range(len(feats))]
    return p


def bicim_gorevi(feats, tur, ki, par, kat_ad, tr, va, tohum=TOHUM):
    b = lgb_egit(lgb_X(tr, feats), tr["FI"].values, tr["w"].values, bicim_par(par, tur, feats), BICIM_TUR_TAVAN, tohum,
                 lgb_X(va, feats), va["FI"].values, va["w"].values, isci=1, es=sabir(par))
    p = b.predict(lgb_X(va, feats), num_iteration=b.best_iteration)
    return {"konfig": ki, "kat": kat_ad, "tohum": tohum, "best_iter": int(b.best_iteration), "logloss": wlogloss(va["FI"].values, p, va["w"].values),
            "auc": auc_w(p, va["FI"].values, va["w"].values)}


def bicim_calistir(set_ad, tur, konf, ids, kk, feats, sut):
    gorev = [(ki, c, ka, tr[sut], va[sut]) for ki, c in zip(ids, konf) for (ka, tr, va) in kk]
    gorev.sort(key=lambda g: g[1]["learning_rate"])
    r = pd.DataFrame(Parallel(n_jobs=ISCI, backend="loky")(delayed(bicim_gorevi)(feats, tur, ki, c, ka, tr, va) for (ki, c, ka, tr, va) in gorev))
    sec = r.groupby("konfig")["logloss"].mean().sort_values().index[:EN_IYI_K].tolist()
    kdict = dict(zip(ids, konf))
    gorev3 = [(ki, kdict[ki], ka, tr[sut], va[sut], t) for ki in sec for (ka, tr, va) in kk for t in EK_TOHUM]
    r3 = pd.DataFrame(Parallel(n_jobs=ISCI, backend="loky")(delayed(bicim_gorevi)(feats, tur, ki, c, ka, tr, va, t) for (ki, c, ka, tr, va, t) in gorev3))
    return pd.concat([r, r3], ignore_index=True).merge(pd.DataFrame([dict(konfig=i, **c) for i, c in zip(ids, konf)]), on="konfig"), len(gorev) + len(gorev3)


def bicim_sinir(par, tur):
    uyari = []
    if par["learning_rate"] <= BICIM_SINIR["learning_rate"][0] * 1.15:
        uyari.append("learning_rate alt sinirda")
    if par["learning_rate"] >= BICIM_SINIR["learning_rate"][1] * 0.85:
        uyari.append("learning_rate ust sinirda")
    if par["min_data_in_leaf"] <= BICIM_SINIR["min_data_in_leaf"][0] * 1.15 + 0.5:
        uyari.append("min_data_in_leaf alt sinirda")
    if tur == "ek" and par["num_leaves"] >= BICIM_SINIR["num_leaves"][1] * 0.9:
        uyari.append("num_leaves ust sinirda")
    return "; ".join(uyari) if uyari else "yok"


def bicim_ayar(set_ad, tur):
    pop, feats = SETLER[set_ad]
    f = OB / f"bicim_ayar_{tur}_{set_ad}_{ozellik_ozeti(feats)}.csv"
    if f.exists():
        return pd.read_csv(f, float_precision="round_trip")
    t0 = time.time()
    kk = katlar(pop)
    sut = feats + ["FI", "w"]
    konf = konfig_uret_bicim(N_BICIM, np.random.default_rng(TOHUM + 600 + (0 if tur == "ek" else 1) + 10 * BICIM_SETLER.index(set_ad)), tur)
    r, n_model = bicim_calistir(set_ad, tur, konf, list(range(len(konf))), kk, feats, sut)
    r["asama"] = "1 rastgele"
    k, par, _, _, _, _ = en_iyi(r)
    uyari = bicim_sinir(par, tur)
    if uyari != "yok":
        rng = np.random.default_rng(TOHUM + 700 + (0 if tur == "ek" else 1) + 10 * BICIM_SETLER.index(set_ad))
        yeni = []
        for i in range(30):
            c = dict(par)
            c["learning_rate"] = float(np.clip(par["learning_rate"] * np.exp(rng.normal(-0.5 if "learning_rate alt" in uyari else (0.5 if "learning_rate ust" in uyari else 0.0), 0.35)), 0.001, 1.0))
            c["min_data_in_leaf"] = int(np.clip(np.round(par["min_data_in_leaf"] * np.exp(rng.normal(-0.5 if "min_data" in uyari else 0.0, 0.5))), 1, 1000))
            c["lambda_l2"] = float(np.clip(par.get("lambda_l2", 1.0) * np.exp(rng.normal(0, 0.8)), 1e-4, 300.0))
            c["feature_fraction"] = float(np.clip(par["feature_fraction"] + rng.normal(0, 0.08), 0.2, 1.0))
            c["bagging_fraction"] = float(np.clip(par["bagging_fraction"] + rng.normal(0, 0.08), 0.4, 1.0))
            if tur == "ek":
                c["num_leaves"] = int(np.clip(np.round(par["num_leaves"] * np.exp(rng.normal(0.4 if "num_leaves" in uyari else 0.0, 0.4))), 2, 128))
            yeni.append(c)
        r4, n4 = bicim_calistir(set_ad, tur, yeni, [1000 + i for i in range(len(yeni))], kk, feats, sut)
        r4["asama"] = "4 genisletme"
        r = pd.concat([r, r4], ignore_index=True)
        n_model += n4
    r["set"], r["tur"] = set_ad, tur
    r.to_csv(f, index=False)
    sure_kaydet(f"Bicim merdiveni LightGBM ayari {tur} {set_ad} ({n_model} model)", t0)
    return r


bicim = {}
bicim_bilgi = []
t0 = time.time()
for s in BICIM_SETLER:
    pop, feats = SETLER[s]
    for tur in ("ek", "d2"):
        r = bicim_ayar(s, tur)
        k, par, n_tur, it, tek, cok = en_iyi(r)
        f = OB / f"bicim_model_{tur}_{s}_k{k}_t{n_tur}_{ozellik_ozeti(feats)}.pkl"
        if f.exists():
            paket = pickle.loads(f.read_bytes())
        else:
            d = nufus(h, pop)
            tr = d[d["yil"].isin([2023, 2024])]
            modeller = Parallel(n_jobs=len(TOHUMLAR), backend="loky")(
                delayed(lgb_egit)(lgb_X(tr, feats), tr["FI"].values, tr["w"].values, bicim_par(par, tur, feats), n_tur, t, isci=max(1, ISCI // len(TOHUMLAR))) for t in TOHUMLAR)
            paket = {"modeller": [m.model_to_string() for m in modeller], "feats": feats, "n_tur": n_tur, "set": s, "egitim": [2023, 2024]}
            f.write_bytes(pickle.dumps(paket))
        bicim[f"lgb_{tur}_{s}"] = paket
        sec = r[r["konfig"] == k]
        bicim_bilgi.append({"kol": f"lgb_{tur}_{s}", "set": s, "tur": tur, "konfig": k, "asama": sec["asama"].iloc[0], "n_tur": n_tur, "cv_logloss": float(cok.loc[cok["konfig"] == k, "logloss"].iloc[0]),
                            "cv_auc": float(cok.loc[cok["konfig"] == k, "auc"].iloc[0]), "sinir": bicim_sinir(par, tur), "tur_tavanina_yakin": bool(sec["best_iter"].max() >= 0.98 * BICIM_TUR_TAVAN),
                            "n_konfig": int(r["konfig"].nunique()), **par})
        yaz(f"Bicim {tur} {s}: konfig {k}, {n_tur} tur, CV log-loss {bicim_bilgi[-1]['cv_logloss']:.4f}, sinir: {bicim_bilgi[-1]['sinir']}, {par}")
pd.DataFrame(bicim_bilgi).to_csv(LOG / "H2_bicim_ayar.csv", index=False)
sure_kaydet("Bicim merdiveni: kisitli LightGBM ayari ve nihai modeller", t0)


class Kodlayici:
    def __init__(self, feats, spline=True, sirali_sayisal=False):
        self.feats = feats
        self.spline = spline
        self.sirali_sayisal = sirali_sayisal

    def fit(self, df, w=None):
        self.kat = {}
        self.say = {}
        self.spl = {}
        for v in self.feats:
            x = df[v]
            if v in NOMINAL or (v in SIRALI and not self.sirali_sayisal):
                self.kat[v] = sorted(x.dropna().unique().tolist(), key=lambda z: str(z))
            else:
                xv = x.astype(float)
                med = float(np.nanmedian(xv)) if xv.notna().any() else 0.0
                self.say[v] = {"med": med, "bos": bool(xv.isna().any())}
                if self.spline and v in SPLINE:
                    st = SplineTransformer(n_knots=5, degree=3, knots="quantile", include_bias=False)
                    st.fit(xv.fillna(med).values.reshape(-1, 1))
                    self.spl[v] = st
        X, ad = self._ham(df)
        self.ort = X.mean(0)
        self.ss = X.std(0)
        self.ss[self.ss == 0] = 1
        self.ad = ad
        return self

    def _ham(self, df):
        sut = []
        ad = []
        for v in self.feats:
            x = df[v]
            if v in self.kat:
                for k in self.kat[v]:
                    sut.append((x == k).astype(float).values)
                    ad.append((v, f"{v}={k}"))
                sut.append(x.isna().astype(float).values)
                ad.append((v, f"{v}=bos"))
            else:
                xv = x.astype(float)
                bos = xv.isna().values
                xv = xv.fillna(self.say[v]["med"]).values
                if v in self.spl:
                    B = self.spl[v].transform(xv.reshape(-1, 1))
                    for j in range(B.shape[1]):
                        sut.append(B[:, j])
                        ad.append((v, f"{v}_s{j + 1}"))
                else:
                    sut.append(xv)
                    ad.append((v, v))
                if self.say[v]["bos"]:
                    sut.append(bos.astype(float))
                    ad.append((v, f"{v}_bos"))
        return np.column_stack(sut), ad

    def transform(self, df):
        X, _ = self._ham(df)
        return (X - self.ort) / self.ss


def lojistik_ayar(feats, pop, Cs, spline=True, sirali_sayisal=False):
    sonuc = []
    for ka, tr, va in katlar(pop):
        kd = Kodlayici(feats, spline=spline, sirali_sayisal=sirali_sayisal).fit(tr)
        Xtr, Xva = kd.transform(tr), kd.transform(va)
        for C in Cs:
            m = LogisticRegression(C=C, solver="lbfgs", max_iter=3000)
            m.fit(Xtr, tr["FI"].values, sample_weight=tr["w"].values)
            p = m.predict_proba(Xva)[:, 1]
            sonuc.append({"kat": ka, "C": C, "logloss": wlogloss(va["FI"].values, p, va["w"].values), "auc": auc_w(p, va["FI"].values, va["w"].values)})
    r = pd.DataFrame(sonuc)
    oz = r.groupby("C")[["logloss", "auc"]].mean().reset_index()
    return float(oz.loc[oz["logloss"].idxmin(), "C"]), r


def lojistik_nihai(ad, feats, pop, egitim_yil=(2023, 2024), spline=True, sirali_sayisal=False):
    f = OB / f"lojistik_{ad}.pkl"
    if f.exists():
        return pickle.loads(f.read_bytes())
    Cs = list(np.logspace(-5, 1, 13))
    C, r = lojistik_ayar(feats, pop, Cs, spline=spline, sirali_sayisal=sirali_sayisal)
    d = nufus(h, pop)
    tr = d[d["yil"].isin(list(egitim_yil))]
    kd = Kodlayici(feats, spline=spline, sirali_sayisal=sirali_sayisal).fit(tr)
    C_son = C * float(np.mean([k_tr["w"].sum() for _, k_tr, _ in katlar(pop)])) / float(tr["w"].sum())
    m = LogisticRegression(C=C_son, solver="lbfgs", max_iter=5000).fit(kd.transform(tr), tr["FI"].values, sample_weight=tr["w"].values)
    paket = {"kd": kd, "m": m, "C": C, "C_nihai": C_son, "cv": r, "feats": feats}
    f.write_bytes(pickle.dumps(paket))
    return paket


t0 = time.time()
loj = {"logit_A1": lojistik_nihai("A1", T1 + T2, "A"), "logit_A2": lojistik_nihai("A2", T2, "A"), "logit_B1": lojistik_nihai("B1", T2 + ["log_goreli_gelir"], "B")}
loj["logit_A1_2023"] = lojistik_nihai("A1_2023", T1 + T2, "A", egitim_yil=(2023,))
loj["logit_lin_A1"] = lojistik_nihai("lin_A1", T1 + T2, "A", spline=False, sirali_sayisal=True)
loj["logit_lin_A2"] = lojistik_nihai("lin_A2", T2, "A", spline=False, sirali_sayisal=True)
sure_kaydet("Cezali lojistik (L2) ayar ve nihai", t0)
yaz("Lojistik modeller hazir; C:", {k: round(v["C"], 4) for k, v in loj.items()})


def cart_X(df, feats, ref_kat):
    sut = {}
    for v in feats:
        if v in NOMINAL:
            for k in ref_kat[v]:
                sut[f"{v}={k}"] = (df[v] == k).astype(float).values
        else:
            sut[v] = df[v].astype(float).values
    return pd.DataFrame(sut, index=df.index)


def cart_kur(ad, feats, pop, egitim_yil=(2023, 2024)):
    f = OB / f"cart_{ad}.pkl"
    if f.exists():
        return pickle.loads(f.read_bytes())
    d = nufus(h, pop)
    ref_kat = {v: KAT_SIRA[v] for v in feats if v in NOMINAL}
    sonuc = []
    katlar_ = [(ka, cart_X(tr, feats, ref_kat), tr, cart_X(va, feats, ref_kat), va) for ka, tr, va in katlar(pop)]
    for kr in ("entropy", "gini"):
        for mwf in (0.001, 0.0025, 0.005, 0.01, 0.02, 0.05, 0.075, 0.1):
            alfalar = np.unique(np.concatenate([np.round(DecisionTreeClassifier(max_depth=3, criterion=kr, min_weight_fraction_leaf=mwf, random_state=TOHUM)
                                                         .cost_complexity_pruning_path(Xtr, tr["FI"].values, sample_weight=tr["w"].values).ccp_alphas, 8)
                                                for ka, Xtr, tr, Xva, va in katlar_]))
            for ka, Xtr, tr, Xva, va in katlar_:
                for a in alfalar:
                    t = DecisionTreeClassifier(max_depth=3, criterion=kr, min_weight_fraction_leaf=mwf, ccp_alpha=float(a), random_state=TOHUM)
                    t.fit(Xtr, tr["FI"].values, sample_weight=tr["w"].values)
                    p = t.predict_proba(Xva)[:, 1]
                    sonuc.append({"olcut": kr, "mwf": mwf, "alpha": float(a), "kat": ka, "yaprak": int(t.get_n_leaves()), "logloss": wlogloss(va["FI"].values, p, va["w"].values),
                                  "auc": auc_w(p, va["FI"].values, va["w"].values)})
    r = pd.DataFrame(sonuc)
    oz = r.groupby(["olcut", "mwf", "alpha"]).agg(logloss=("logloss", "mean"), auc=("auc", "mean"), n_kat=("kat", "nunique"), yaprak=("yaprak", "mean")).reset_index()
    oz = oz[oz["n_kat"] == 2]
    best = oz.loc[oz["logloss"].idxmin()]
    tr = d[d["yil"].isin(list(egitim_yil))]
    Xtr = cart_X(tr, feats, ref_kat)
    t = DecisionTreeClassifier(max_depth=3, criterion=str(best["olcut"]), min_weight_fraction_leaf=float(best["mwf"]), ccp_alpha=float(best["alpha"]), random_state=TOHUM)
    t.fit(Xtr, tr["FI"].values, sample_weight=tr["w"].values)
    paket = {"t": t, "feats": feats, "ref_kat": ref_kat, "kolonlar": list(Xtr.columns), "olcut": str(best["olcut"]), "mwf": float(best["mwf"]), "alpha": float(best["alpha"]),
             "cv_logloss": float(best["logloss"]), "cv_auc": float(best["auc"]), "cv": r, "pop": pop}
    f.write_bytes(pickle.dumps(paket))
    return paket


def cart_tahmin(paket, df):
    return paket["t"].predict_proba(cart_X(df, paket["feats"], paket["ref_kat"])[paket["kolonlar"]])[:, 1]


def cart_yaprak(paket, df):
    return paket["t"].apply(cart_X(df, paket["feats"], paket["ref_kat"])[paket["kolonlar"]])


def l1_kur(ad, feats, pop, en_fazla=6, egitim_yil=(2023, 2024)):
    f = OB / f"l1_{ad}.pkl"
    if f.exists():
        return pickle.loads(f.read_bytes())
    d = nufus(h, pop)
    tr = d[d["yil"].isin(list(egitim_yil))]
    kd = Kodlayici(feats, spline=False).fit(tr)
    X = kd.transform(tr)
    taban = np.array([a[0] for a in kd.ad])
    yol = []
    secilen = None
    for C in np.logspace(-4, 0, 41):
        m = LogisticRegression(C=C, l1_ratio=1.0, solver="liblinear", max_iter=5000, random_state=TOHUM)
        m.fit(X, tr["FI"].values, sample_weight=tr["w"].values)
        nz = np.abs(m.coef_[0]) > 1e-8
        degisken = sorted(set(taban[nz]))
        yol.append({"C": C, "n_degisken": len(degisken), "degiskenler": ";".join(degisken)})
        if len(degisken) <= en_fazla:
            secilen = (C, degisken)
    C, degisken = secilen
    kd2 = Kodlayici(degisken, spline=False).fit(tr)
    m2 = LogisticRegression(C=10.0, solver="lbfgs", max_iter=5000).fit(kd2.transform(tr), tr["FI"].values, sample_weight=tr["w"].values)
    paket = {"kd": kd2, "m": m2, "C_l1": C, "degiskenler": degisken, "yol": pd.DataFrame(yol), "feats": degisken}
    f.write_bytes(pickle.dumps(paket))
    return paket


def loj_tahmin(paket, df):
    return paket["m"].predict_proba(paket["kd"].transform(df))[:, 1]


t0 = time.time()
cartlar = {
    "cart_T2": cart_kur("T2", T2_HB030, "A"),
    "cart_T1T2": cart_kur("T1T2", T1 + T2_HB030, "A"),
    "cart_T2idari": cart_kur("T2idari", T2_IDARI, "A"),
    "cart_B_T2": cart_kur("B_T2", T2_HB030, "B"),
    "cart_B_T2gelir": cart_kur("B_T2gelir", T2_HB030 + ["log_goreli_gelir"], "B"),
}
cartlar["cart_T2_2023"] = cart_kur("T2_2023", T2_HB030, "A", egitim_yil=(2023,))
l1ler = {
    "l1_T2": l1_kur("T2", T2_HB030, "A"),
    "l1_T1T2": l1_kur("T1T2", T1 + T2_HB030, "A"),
    "l1_B_T2": l1_kur("B_T2", T2_HB030, "B"),
}
sure_kaydet("Sade kural setleri (CART, L1)", t0)
yaz("Kural setleri hazir:", {k: (int(v["t"].get_n_leaves()), v["olcut"], v["mwf"], round(v["alpha"], 6), round(v["cv_logloss"], 4)) for k, v in cartlar.items()}, {k: v["degiskenler"] for k, v in l1ler.items()})


def kat_etiket(v, k):
    tablo_ad = ETK["kategori_esleme"].get(v, v)
    tablo = ETK["kategori"].get(tablo_ad, {})
    anahtar = str(int(k)) if isinstance(k, (int, float, np.integer, np.floating)) and float(k).is_integer() else str(k)
    return tablo.get(anahtar, anahtar)


def degisken_etiket(v):
    return ETK["degisken"].get(v, v)


IKILI = {"reis_cinsiyet", "reis_kronik", "HS010", "HS020", "HS030", "HS040", "HS050", "HS060", "HS070", "HH120", "tek_yetiskin_cocuklu",
         "kalabalik_konut", "ciddi_konut_yoksunlugu", "sosyal_yardim_var", "ozel_transfer_var", "kira_geliri_var"}
EKSIKLI = {v for v in set(T1 + T2 + T3 + T2_IDARI) if h.loc[h["yil"].isin([2023, 2024]), v].isna().any()}


def kosul_metni(ad, yon, esik, eksik_sol):
    if "=" in ad:
        v, k = ad.split("=", 1)
        kk = kat_etiket(v, k if not k.replace(".", "", 1).isdigit() else float(k))
        return f"{degisken_etiket(v)}: {kk}" if yon == "sag" else f"{degisken_etiket(v)}: not {kk}"
    v = ad
    eksik = " (or missing)" if v in EKSIKLI and ((eksik_sol and yon == "sol") or (not eksik_sol and yon == "sag")) else ""
    alt = int(np.floor(esik))
    if v in IKILI or v.endswith("_var"):
        return f"{degisken_etiket(v)}: {kat_etiket(v, alt if yon == 'sol' else alt + 1)}{eksik}"
    if v in SIRALI:
        kodlar = SIRALI_KOD[v]
        alt_k = max([k for k in kodlar if k <= esik], default=kodlar[0])
        ust_k = min([k for k in kodlar if k > esik], default=kodlar[-1])
        return f"{degisken_etiket(v)} ≤ {kat_etiket(v, alt_k)}{eksik}" if yon == "sol" else f"{degisken_etiket(v)} ≥ {kat_etiket(v, ust_k)}{eksik}"
    if v in SAYIM or v == "reis_yas":
        if yon == "sol":
            return f"{degisken_etiket(v)} = 0{eksik}" if alt == 0 else f"{degisken_etiket(v)} ≤ {alt}{eksik}"
        return f"{degisken_etiket(v)} ≥ {alt + 1}{eksik}"
    if v == "log_goreli_gelir":
        g = float(np.exp(esik))
        return f"{degisken_etiket('goreli_esdeger_gelir')} ≤ {g:.2f}{eksik}" if yon == "sol" else f"{degisken_etiket('goreli_esdeger_gelir')} > {g:.2f}{eksik}"
    return f"{degisken_etiket(v)} ≤ {esik:.2f}{eksik}" if yon == "sol" else f"{degisken_etiket(v)} > {esik:.2f}{eksik}"


SIRALI_KOD = {v: sorted(float(k) for k in h[v].dropna().unique()) for v in SIRALI if v in h}


def aralik_metni(v, lo, hi, eksik):
    ek = " (or missing)" if eksik else ""
    if v == "log_goreli_gelir":
        return f"{degisken_etiket('goreli_esdeger_gelir')} {np.exp(lo):.2f}–{np.exp(hi):.2f}{ek}"
    if v in SIRALI:
        kodlar = SIRALI_KOD[v]
        a = min([k for k in kodlar if k > lo], default=kodlar[-1])
        b = max([k for k in kodlar if k <= hi], default=kodlar[0])
        return f"{degisken_etiket(v)}: {kat_etiket(v, a)}" + (f" to {kat_etiket(v, b)}" if b != a else "") + ek
    if v in SAYIM or v == "reis_yas":
        a, b = int(np.floor(lo)) + 1, int(np.floor(hi))
        return f"{degisken_etiket(v)} = {a}{ek}" if a == b else f"{degisken_etiket(v)} {a}–{b}{ek}"
    return f"{degisken_etiket(v)} {lo:.2f}–{hi:.2f}{ek}"


def yol_metni(kos):
    sira = []
    sinir = {}
    for f, yon, e, es in kos:
        if f not in sinir:
            sinir[f] = {"lo": None, "hi": None, "parca": []}
            sira.append(f)
        d = sinir[f]
        d["parca"].append((yon, e, es))
        if yon == "sol":
            d["hi"] = e if d["hi"] is None else min(d["hi"], e)
        else:
            d["lo"] = e if d["lo"] is None else max(d["lo"], e)
    out = []
    for f in sira:
        d = sinir[f]
        if "=" in f or len(d["parca"]) == 1 or d["lo"] is None or d["hi"] is None:
            if "=" in f or len(d["parca"]) == 1:
                out += [kosul_metni(f, y, e, es) for y, e, es in d["parca"]]
            else:
                yon_son = "sol" if d["lo"] is None else "sag"
                esik = d["hi"] if yon_son == "sol" else d["lo"]
                es_son = [p for p in d["parca"] if p[0] == yon_son][0][2]
                out.append(kosul_metni(f, yon_son, esik, es_son))
        else:
            eksik = f in EKSIKLI and all((es and y == "sol") or (not es and y == "sag") for y, e, es in d["parca"])
            out.append(aralik_metni(f, d["lo"], d["hi"], eksik))
    return " AND ".join(out)


def kurallar(paket, ad, egit, test):
    t = paket["t"].tree_
    kol = paket["kolonlar"]
    eksik_sol = getattr(t, "missing_go_to_left", np.ones(t.node_count, dtype=bool))
    yollar = {}

    def gez(dugum, kos):
        if t.children_left[dugum] == -1:
            yollar[dugum] = kos
            return
        f = kol[t.feature[dugum]]
        e = t.threshold[dugum]
        gez(t.children_left[dugum], kos + [(f, "sol", e, bool(eksik_sol[dugum]))])
        gez(t.children_right[dugum], kos + [(f, "sag", e, bool(eksik_sol[dugum]))])

    gez(0, [])
    ly_e = cart_yaprak(paket, egit)
    ly_t = cart_yaprak(paket, test)
    satir = []
    for yp, kos in yollar.items():
        me = ly_e == yp
        mt = ly_t == yp
        metin = yol_metni(kos) if kos else "All households"
        satir.append({"kural_seti": ad, "yaprak": int(yp), "kural": metin,
                      "egitim_pay": 100 * egit["w"].values[me].sum() / egit["w"].values.sum(), "egitim_FI": 100 * np.sum(egit["w"].values[me] * egit["FI"].values[me]) / max(egit["w"].values[me].sum(), 1e-12),
                      "egitim_n": int(me.sum()), "test_pay": 100 * test["w"].values[mt].sum() / test["w"].values.sum(),
                      "test_FI": 100 * np.sum(test["w"].values[mt] * test["FI"].values[mt]) / max(test["w"].values[mt].sum(), 1e-12) if mt.sum() else np.nan, "test_n": int(mt.sum())})
    r = pd.DataFrame(satir).sort_values("egitim_FI", ascending=False).reset_index(drop=True)
    r["sira"] = np.arange(1, len(r) + 1)
    r["egitim_kumulatif_pay"] = r["egitim_pay"].cumsum()
    return r


te = h[h["yil"] == 2025].copy().reset_index(drop=True)
eg = h[h["yil"].isin([2023, 2024])]
kural_tab = []
for ad, p in cartlar.items():
    if ad.endswith("_2023"):
        continue
    egit = nufus(eg, p["pop"])
    test = nufus(te[te["test_temiz"] == 1], p["pop"])
    kural_tab.append(kurallar(p, ad, egit, test))
kural_tab = pd.concat(kural_tab)
kural_tab.to_csv(SON / "H2_kurallar.csv", index=False)
l1_tab = []
for ad, p in l1ler.items():
    m = p["m"]
    b0_ham = float(m.intercept_[0] - np.sum(m.coef_[0] * p["kd"].ort / p["kd"].ss))
    l1_tab.append({"model": ad, "degisken": "(sabit)", "terim": "(sabit)", "katsayi_ham": b0_ham, "OR_birim": np.exp(b0_ham)})
    for (v, kol), b in zip(p["kd"].ad, m.coef_[0] / p["kd"].ss):
        l1_tab.append({"model": ad, "degisken": v, "terim": kol, "katsayi_ham": b, "OR_birim": np.exp(b)})
pd.DataFrame(l1_tab).to_csv(SON / "H2_l1_katsayilar.csv", index=False)
pd.concat([p["yol"].assign(model=ad) for ad, p in l1ler.items()]).to_csv(LOG / "H2_l1_yol.csv", index=False)
pd.concat([p["cv"].assign(model=ad) for ad, p in cartlar.items()]).to_csv(LOG / "H2_cart_cv.csv", index=False)
yaz("Kurallar yazildi")

skorlar = pd.DataFrame({"hane_kimlik": te["hane_kimlik"].values})
for s in SETLER:
    pop = SETLER[s][0]
    skorlar[f"lgb_{s}"] = paket_tahmin(paketler[s], te)
skorlar["lgb_A1_2023"] = paket_tahmin(paketler["A1_2023"], te)
skorlar["lgb_B1_2023"] = paket_tahmin(paketler["B1_2023"], te)
for k, p in loj.items():
    skorlar[k] = loj_tahmin(p, te)
for k, p in cartlar.items():
    skorlar[k] = cart_tahmin(p, te)
for k, p in l1ler.items():
    skorlar[k] = loj_tahmin(p, te)
for k, p in bicim.items():
    skorlar[k] = paket_tahmin(p, te)
tek_tohum = {s: paket_tahmin(paketler[s], te, tek=True) for s in ("A1", "A2", "A3", "B1")}
skorlar.to_parquet(MLD / "skorlar_2025.parquet", index=False)
yaz("2025 skorlari yazildi:", skorlar.shape)

t0 = time.time()
MODK = SON / "modeller"
MODK_LGB = MLD / "lightgbm"
for k in (MODK / "lojistik", MODK_LGB):
    k.mkdir(parents=True, exist_ok=True)


def yerel(x):
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, np.floating):
        return float(x)
    return x


LOJ_ACIKLAMA = {"logit_lin_A1": "Ridge logistic, linear terms; income + structural (T1 + T2); all households",
                "logit_lin_A2": "Ridge logistic, linear terms; structural only (T2); all households",
                "logit_A1": "Ridge logistic, cubic B-splines for continuous features; income + structural; all households",
                "logit_A2": "Ridge logistic, cubic B-splines for continuous features; structural only; all households",
                "logit_B1": "Ridge logistic, cubic B-splines; structural + relative income; non-poor households",
                "l1_T2": "Lasso logistic (at most six variables, refitted with a weak ridge penalty); structural; all households",
                "l1_T1T2": "Lasso logistic (at most six variables, refitted with a weak ridge penalty); income + structural; all households",
                "l1_B_T2": "Lasso logistic (at most six variables, refitted with a weak ridge penalty); structural; non-poor households"}
LGB_DISA = {"lgb_A1": "A1", "lgb_A2": "A2", "lgb_A2i": "A2i", "lgb_A3": "A3", "lgb_B1": "B1"}
loj_disa = {**{k: loj[k] for k in ("logit_lin_A1", "logit_lin_A2", "logit_A1", "logit_A2", "logit_B1")}, **l1ler}
model_liste = []
for ad, p in loj_disa.items():
    kd, m = p["kd"], p["m"]
    b, b0 = m.coef_[0], float(m.intercept_[0])
    b_ham = b / kd.ss
    b0_ham = b0 - float(np.sum(b * kd.ort / kd.ss))
    spl = {v: {"dugumler": [float(z) for z in st.bsplines_[0].t[st.degree:-st.degree]], "dugum_vektoru": [float(z) for z in st.bsplines_[0].t], "derece": int(st.degree),
               "dis_deger": str(st.extrapolation), "dahil_sabit": bool(st.include_bias)} for v, st in kd.spl.items()}
    js = {"model": ad, "aciklama": LOJ_ACIKLAMA[ad], "nufus": "non-poor households" if "_B" in ad else "all households", "egitim": "2023-2024",
          "ozellikler": list(kd.feats), "sirali_sayisal": bool(kd.sirali_sayisal), "spline": bool(kd.spline),
          "kategoriler": {v: [yerel(z) for z in ks] for v, ks in kd.kat.items()}, "sayisal": {v: {"medyan": float(s["med"]), "eksik_gostergesi": bool(s["bos"])} for v, s in kd.say.items()},
          "spline_dugumleri": spl, "terimler": [t for _, t in kd.ad], "terim_degiskeni": [v for v, _ in kd.ad], "ortalama": kd.ort.tolist(), "standart_sapma": kd.ss.tolist(),
          "sabit": b0, "katsayilar": b.tolist(), "sabit_ham": b0_ham, "katsayilar_ham": b_ham.tolist(), "C_ayar": float(p["C"]) if "C" in p else None,
          "C_nihai": float(p["C_nihai"]) if "C_nihai" in p else 10.0, "C_l1_yol": float(p["C_l1"]) if "C_l1" in p else None}
    (MODK / "lojistik" / f"{ad}.json").write_text(json.dumps(js, indent=1, ensure_ascii=False), encoding="utf-8")
    pd.DataFrame([{"terim": "(sabit)", "degisken": "", "katsayi_olcekli": b0, "ortalama": np.nan, "standart_sapma": np.nan, "katsayi_ham": b0_ham}] +
                 [{"terim": t, "degisken": v, "katsayi_olcekli": bb, "ortalama": o, "standart_sapma": s, "katsayi_ham": bh} for (v, t), bb, o, s, bh in zip(kd.ad, b, kd.ort, kd.ss, b_ham)]
                 ).to_csv(MODK / "lojistik" / f"{ad}_katsayilar.csv", index=False)
    model_liste.append({"model": ad, "tur": "lojistik", "aciklama": LOJ_ACIKLAMA[ad], "n_ozellik": len(kd.feats), "n_terim_veya_agac": len(kd.ad), "dosyalar": f"lojistik/{ad}.json; lojistik/{ad}_katsayilar.csv"})
lgb_liste = []
for ad, s in LGB_DISA.items():
    pk = paketler[s]
    for i, ms in enumerate(pk["modeller"]):
        with gzip.GzipFile(MODK_LGB / f"{ad}_tohum{i + 1}.txt.gz", "wb", compresslevel=6, mtime=0) as fz:
            fz.write(ms.encode("utf-8"))
    js = {"model": ad, "aciklama": SET_ACIKLAMA[s], "ozellikler": list(pk["feats"]), "nominal": [v for v in pk["feats"] if v in NOMINAL],
          "kategori_sirasi": {v: [yerel(z) for z in KAT_SIRA[v]] for v in pk["feats"] if v in NOMINAL}, "n_tur": int(pk["n_tur"]), "tohumlar": TOHUMLAR,
          "dosyalar": [f"{ad}_tohum{i + 1}.txt.gz" for i in range(len(pk["modeller"]))], "birlestirme": "mean of the predicted probabilities of the five boosters"}
    (MODK_LGB / f"{ad}.json").write_text(json.dumps(js, indent=1, ensure_ascii=False), encoding="utf-8")
    lgb_liste.append({"model": ad, "tur": "lightgbm", "aciklama": SET_ACIKLAMA[s], "n_ozellik": len(pk["feats"]), "n_terim_veya_agac": int(pk["n_tur"]), "dosyalar": f"{ad}.json; {ad}_tohum1-5.txt.gz"})
pd.DataFrame(lgb_liste).to_csv(MODK_LGB / "model_listesi.csv", index=False)
on_isleme = {"metin_sutunlar": ["HB030", "HB031"],
             "kategori_birlestirme": [{"degisken": r["degisken"], "kod": yerel(r["kod"]), "hedef": yerel(r["birlestirildigi_kod"])} for r in kodlama if not str(r["kod"]).startswith(">")],
             "ust_sinir": [{"degisken": r["degisken"], "ust": float(r["birlestirildigi_kod"])} for r in kodlama if str(r["kod"]).startswith(">")]}
(MODK / "on_isleme.json").write_text(json.dumps(on_isleme, indent=1, ensure_ascii=False), encoding="utf-8")
girdi = sorted({v for p in loj_disa.values() for v in p["kd"].feats})
pd.DataFrame([{"degisken": v, "etiket": degisken_etiket(v), "tur": "nominal" if v in NOMINAL else ("sirali" if v in SIRALI else "sayisal"),
               "eksik_olabilir": bool(h.loc[egitim_yillari, v].isna().any()), "modeller": ";".join([a for a, p in loj_disa.items() if v in p["kd"].feats])}
              for v in girdi]).to_csv(MODK / "girdi_sutunlari.csv", index=False)
pd.DataFrame(model_liste).to_csv(MODK / "model_listesi.csv", index=False)
sure_kaydet("Model dosyalari (Results/modeller; LightGBM yalniz yerel)", t0)
yaz("Model dosyalari yazildi:", len(model_liste), "lojistik model; LightGBM dokumleri yerelde", MODK_LGB)

ARAMA = [
    ("tum LightGBM asamalari", "LightGBM", "objective", None, None, "sabit", "binary", "HB040 weights scaled to mean 1 within year; bagging_freq 1; deterministic"),
    ("tum LightGBM asamalari", "LightGBM", "num_boost_round (ayar)", None, 10000, "sabit ust sinir", "", "early stopping on the validation fold; patience max(100, round(2 / learning_rate))"),
    ("tum LightGBM asamalari", "LightGBM", "katlar", None, None, "sabit", "train 2023 -> validate 2024 unmatched; train 2024 -> validate 2023 unmatched", "criterion: weighted log-loss averaged over folds (and seeds)"),
    ("1 genis", "LightGBM", "num_leaves", 8, 128, "tamsayi tekduze", "", f"{N_KONFIG} configurations, seed {TOHUM}"),
    ("1 genis", "LightGBM", "min_data_in_leaf", 20, 400, "tamsayi tekduze", "", ""),
    ("1 genis", "LightGBM", "learning_rate", 0.01, 0.1, "log-tekduze", "", ""),
    ("1 genis", "LightGBM", "feature_fraction", 0.4, 1.0, "tekduze", "", ""),
    ("1 genis", "LightGBM", "bagging_fraction", 0.5, 1.0, "tekduze", "", ""),
    ("1 genis", "LightGBM", "lambda_l2", 1e-3, 20.0, "log-tekduze", "", ""),
    ("1 genis", "LightGBM", "max_depth", None, None, "secenek kumesi", "-1; 4; 6; 8; 10", "equal probabilities; -1 = no limit"),
    ("1 genis", "LightGBM", "lambda_l1", 0.0, 0.0, "sabit", "", "LightGBM default"),
    ("1 genis", "LightGBM", "min_gain_to_split", 0.0, 0.0, "sabit", "", "LightGBM default"),
    ("1 genis", "LightGBM", "cat_smooth", 10.0, 10.0, "sabit", "", "LightGBM default"),
    ("2 odakli", "LightGBM", "num_leaves", INCE_SINIR["num_leaves"][0], INCE_SINIR["num_leaves"][1], "log-tekduze (tamsayiya yuvarlanir)", "", f"{N_KONFIG} configurations, seed {TOHUM + 1}"),
    ("2 odakli", "LightGBM", "min_data_in_leaf", INCE_SINIR["min_data_in_leaf"][0], INCE_SINIR["min_data_in_leaf"][1], "log-tekduze (tamsayiya yuvarlanir)", "", ""),
    ("2 odakli", "LightGBM", "learning_rate", INCE_SINIR["learning_rate"][0], INCE_SINIR["learning_rate"][1], "log-tekduze", "", ""),
    ("2 odakli", "LightGBM", "feature_fraction", 0.5, 1.0, "tekduze", "", ""),
    ("2 odakli", "LightGBM", "bagging_fraction", 0.6, 1.0, "tekduze", "", ""),
    ("2 odakli", "LightGBM", "lambda_l2", INCE_SINIR["lambda_l2"][0], INCE_SINIR["lambda_l2"][1], "log-tekduze", "", ""),
    ("2 odakli", "LightGBM", "lambda_l1", INCE_SINIR["lambda_l1"][0], INCE_SINIR["lambda_l1"][1], "karisim: 0 (olasilik 0.5) veya log-tekduze", "", ""),
    ("2 odakli", "LightGBM", "min_gain_to_split", None, None, "secenek kumesi", "0 (p = 0.5); 0.01 (p = 0.25); 0.05 (p = 0.25)", ""),
    ("2 odakli", "LightGBM", "cat_smooth", INCE_SINIR["cat_smooth"][0], INCE_SINIR["cat_smooth"][1], "log-tekduze", "", ""),
    ("2 odakli", "LightGBM", "max_depth", None, None, "secenek kumesi", "8; 10; 12; 14; -1", "equal probabilities"),
    ("3 tohum yeniden degerlendirme", "LightGBM", "tohum", None, None, "secenek kumesi", "; ".join(str(t) for t in EK_TOHUM), f"the {EN_IYI_K} configurations with the lowest mean log-loss re-run with two further seeds; selection among configurations with >= 6 evaluations (3 seeds x 2 folds)"),
    ("4 sinir genisletme", "LightGBM", "tetikleyici", None, None, "kural", "", "selected configuration within 15% of the lower learning_rate or min_data_in_leaf bound, within 10% of the upper num_leaves bound or within 15% of the upper lambda_l2 bound; at most 2 rounds of 30 configurations (seeds 20261427, 20261428); best 3 of each round re-run with two seeds"),
    ("4 sinir genisletme", "LightGBM", "num_leaves", GENIS_SINIR["num_leaves"][0], GENIS_SINIR["num_leaves"][1], "carpimsal log-normal sapma (sd 0.4; ortalama 0.3 sinirdaysa), yuvarlanir ve kirpilir", "", "perturbation of the current best configuration"),
    ("4 sinir genisletme", "LightGBM", "min_data_in_leaf", GENIS_SINIR["min_data_in_leaf"][0], GENIS_SINIR["min_data_in_leaf"][1], "carpimsal log-normal sapma (sd 0.5; ortalama -0.5 sinirdaysa), yuvarlanir ve kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "learning_rate", GENIS_SINIR["learning_rate"][0], GENIS_SINIR["learning_rate"][1], "carpimsal log-normal sapma (sd 0.35; ortalama -0.4 sinirdaysa), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "lambda_l2", GENIS_SINIR["lambda_l2"][0], GENIS_SINIR["lambda_l2"][1], "carpimsal log-normal sapma (sd 0.8; ortalama 0.4 sinirdaysa), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "feature_fraction", 0.3, 1.0, "toplamsal normal sapma (sd 0.08), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "bagging_fraction", 0.4, 1.0, "toplamsal normal sapma (sd 0.08), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "lambda_l1", 0.0, 10.0, "carpimsal log-normal sapma (sd 0.8), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "cat_smooth", 1.0, 100.0, "carpimsal log-normal sapma (sd 0.5), kirpilir", "", ""),
    ("4 sinir genisletme", "LightGBM", "min_gain_to_split; max_depth", None, None, "sabit", "", "kept from the current best configuration"),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "num_boost_round (ayar)", None, BICIM_TUR_TAVAN, "sabit ust sinir", "", f"{N_BICIM} configurations per set and form; additive: interaction constraints, one feature per tree; depth 2: num_leaves 4, max_depth 2"),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "learning_rate", BICIM_SINIR["learning_rate"][0], BICIM_SINIR["learning_rate"][1], "log-tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "min_data_in_leaf", BICIM_SINIR["min_data_in_leaf"][0], BICIM_SINIR["min_data_in_leaf"][1], "log-tekduze (tamsayiya yuvarlanir)", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive)", "num_leaves", BICIM_SINIR["num_leaves"][0], BICIM_SINIR["num_leaves"][1], "log-tekduze (tamsayiya yuvarlanir)", "", "depth 2: fixed at 4"),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "feature_fraction", 0.3, 1.0, "tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "bagging_fraction", 0.5, 1.0, "tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "lambda_l2", 1e-3, 100.0, "log-tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "lambda_l1", 0.01, 5.0, "karisim: 0 (olasilik 0.5) veya log-tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "cat_smooth", 1.0, 100.0, "log-tekduze", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "min_gain_to_split", 0.0, 0.0, "sabit", "", ""),
    ("bicim merdiveni kisitli modeller", "LightGBM (additive, depth 2)", "genisletme", None, None, "kural", "", "if the best configuration is near a bound: 30 perturbations (learning_rate clipped to [0.001, 1], min_data_in_leaf [1, 1000], lambda_l2 [1e-4, 300], feature_fraction [0.2, 1], bagging_fraction [0.4, 1], num_leaves [2, 128])"),
    ("ridge", "Ridge logistic (linear, splines)", "C", 1e-5, 10.0, "secenek kumesi", "; ".join(f"{c:.4g}" for c in np.logspace(-5, 1, 13)), "13 log-spaced values; final C rescaled by mean fold training weight / full training weight; splines: cubic B-splines with 5 quantile knots"),
    ("lasso", "Lasso logistic", "C (L1 yolu)", 1e-4, 1.0, "secenek kumesi", "41 log-spaced values", "largest C with at most six variables; refit with ridge penalty C = 10"),
    ("CART", "Depth-3 tree", "criterion", None, None, "secenek kumesi", "entropy; gini", "max_depth 3"),
    ("CART", "Depth-3 tree", "min_weight_fraction_leaf", 0.001, 0.1, "secenek kumesi", "0.001; 0.0025; 0.005; 0.01; 0.02; 0.05; 0.075; 0.1", ""),
    ("CART", "Depth-3 tree", "ccp_alpha", None, None, "secenek kumesi", "union of both folds' cost-complexity pruning paths (rounded to 8 decimals)", "every value evaluated in both folds"),
    ("MLP", "Multilayer perceptron", "gizli katmanlar", None, None, "secenek kumesi", "(128, 64); (256, 128)", "ReLU; AdamW; batch 512; weighted binary cross-entropy"),
    ("MLP", "Multilayer perceptron", "dropout", None, None, "secenek kumesi", "0.1; 0.3", ""),
    ("MLP", "Multilayer perceptron", "weight_decay", None, None, "secenek kumesi", "1e-5; 1e-3", ""),
    ("MLP", "Multilayer perceptron", "learning_rate", 1e-3, 1e-3, "sabit", "", ""),
    ("MLP", "Multilayer perceptron", "epok", 1, 40, "secim", "", "epoch with the lowest validation log-loss, averaged over folds; five seeds averaged in the final model"),
]
arama = pd.DataFrame(ARAMA, columns=["asama", "ogrenici", "parametre", "alt_sinir", "ust_sinir", "olcek", "secenekler", "not"])
for i, k in enumerate(KONFIGLER):
    asm = "1 genis" if i < N_KONFIG else "2 odakli"
    for p_, v_ in k.items():
        r_ = arama[(arama["asama"] == asm) & (arama["parametre"] == p_)].iloc[0]
        if pd.notna(r_["alt_sinir"]) and pd.notna(r_["ust_sinir"]) and v_ != 0:
            assert r_["alt_sinir"] - 1e-12 <= v_ <= r_["ust_sinir"] + 1e-12, (asm, p_, v_)
        elif r_["secenekler"]:
            assert str(v_) in [s.split(" ")[0] for s in r_["secenekler"].split("; ")] or float(v_) in [float(s.split(" ")[0]) for s in r_["secenekler"].split("; ")], (asm, p_, v_)
for s in BICIM_SETLER:
    for tur in ("ek", "d2"):
        for k in konfig_uret_bicim(N_BICIM, np.random.default_rng(TOHUM + 600 + (0 if tur == "ek" else 1) + 10 * BICIM_SETLER.index(s)), tur):
            for p_ in ("learning_rate", "min_data_in_leaf", "lambda_l2", "feature_fraction", "bagging_fraction", "cat_smooth"):
                r_ = arama[(arama["asama"] == "bicim merdiveni kisitli modeller") & (arama["parametre"] == p_)].iloc[0]
                assert r_["alt_sinir"] - 1e-12 <= k[p_] <= r_["ust_sinir"] + 1e-12, (s, tur, p_, k[p_])
arama.to_csv(SON / "H2_arama_uzayi_tanim.csv", index=False)
yaz("Arama uzayi tanimi yazildi:", len(arama), "satir")

y = te["FI"].values.astype(float)
w = te["HB040"].values.astype(float)
cocuk = te["n_cocuk_ham"].values.astype(float)
n_te = len(te)
rng = np.random.default_rng(TOHUM + 7)
M = np.zeros((n_te, B_BOOT), dtype=np.int16)
for b in range(B_BOOT):
    M[:, b] = np.bincount(rng.integers(0, n_te, n_te - 1), minlength=n_te)
WB = (w[:, None] * M * (n_te / (n_te - 1))).astype(np.float64)
W0 = w[:, None]


def grup_matris(skor):
    u, inv = np.unique(-skor, return_inverse=True)
    G = len(u)
    return sparse.csr_matrix((np.ones(len(skor)), (inv, np.arange(len(skor)))), shape=(G, len(skor)))


def kapsam(skor, yy, kk, Wb, c):
    A = grup_matris(skor)
    Wg = A @ Wb
    W1g = A @ (Wb * yy[:, None])
    Kg = A @ (Wb * (kk * yy)[:, None])
    once = np.cumsum(Wg, axis=0) - Wg
    tot = Wg.sum(0)
    hedef = c * tot
    with np.errstate(divide="ignore", invalid="ignore"):
        frac = np.where(Wg > 0, np.clip((hedef - once) / Wg, 0, 1), 0)
    sec = (frac * Wg).sum(0)
    secFI = (frac * W1g).sum(0)
    secK = (frac * Kg).sum(0)
    return {"kapsama": 100 * sec / tot, "duyarlilik": 100 * secFI / W1g.sum(0), "ppv": 100 * secFI / sec, "cocuk": 100 * secK / Kg.sum(0)}


def bayrak(f, yy, kk, Wb):
    f = f.astype(float)
    tot = Wb.sum(0)
    sec = (Wb * f[:, None]).sum(0)
    secFI = (Wb * (f * yy)[:, None]).sum(0)
    secK = (Wb * (f * yy * kk)[:, None]).sum(0)
    return {"kapsama": 100 * sec / tot, "duyarlilik": 100 * secFI / (Wb * yy[:, None]).sum(0), "ppv": 100 * secFI / sec, "cocuk": 100 * secK / (Wb * (yy * kk)[:, None]).sum(0)}


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


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def kalibrasyon(p, yy, ww):
    z = logit(p)
    b = np.zeros(2)
    X = np.column_stack([np.ones_like(z), z])
    for _ in range(50):
        mu = 1 / (1 + np.exp(-(X @ b)))
        H = X.T @ (X * (ww * mu * (1 - mu))[:, None])
        g = X.T @ (ww * (yy - mu))
        st = np.linalg.solve(H, g)
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


DEGER = {"temiz": te["test_temiz"].values == 1, "tam": np.ones(n_te, dtype=bool), "temiz_2023": te["test_temiz_2023"].values == 1, "temiz_imza": te["test_temiz_imza"].values == 1, "temiz_siki": te["test_temiz_siki"].values == 1}
POP_M = {"A": np.ones(n_te, dtype=bool), "B": te["yoksul"].values == 0}
yoksul = te["yoksul"].values.astype(float)
gelir_skor = -te["goreli_esdeger_gelir"].values.astype(float)
SKOR_KOLLAR = {
    "A": ["gelir_sirasi", "lgb_A1", "lgb_A2", "lgb_A3", "lgb_A4", "lgb_A2i", "logit_A1", "logit_A2", "cart_T2", "cart_T1T2", "cart_T2idari", "l1_T2", "l1_T1T2",
          "yoksul+lgb_B1", "yoksul+cart_B_T2", "yoksul+cart_B_T2gelir", "yoksul+l1_B_T2", "lgb_A1_2023", "cart_T2_2023", "logit_A1_2023",
          "logit_lin_A1", "logit_lin_A2", "lgb_ek_A1", "lgb_ek_A2", "lgb_d2_A1", "lgb_d2_A2"],
    "B": ["gelir_sirasi", "lgb_B1", "lgb_B2", "lgb_B3", "logit_B1", "cart_B_T2", "cart_B_T2gelir", "l1_B_T2", "lgb_B1_2023"],
}
BAYRAK_KOLLAR = {"yoksul_60": te["e_yoksul_60"].values, "yoksul_50": te["e_yoksul_50"].values, "yoksul_70": te["e_yoksul_70"].values,
                 "msy_etsiz_5": te["e_msy_etsiz_5"].values, "dusuk_is_yogunlugu": te["e_dusuk_is"].values}


def skor_al(kol):
    if kol == "gelir_sirasi":
        return gelir_skor
    if kol.startswith("yoksul+"):
        return np.where(yoksul == 1, 10.0 + 0 * yoksul, skorlar[kol.split("+", 1)[1]].values)
    return skorlar[kol].values


def degerlendir(sema, pop, Wb):
    m = DEGER[sema] & POP_M[pop]
    yy, kk, W = y[m], cocuk[m], Wb[m]
    tot = W.sum(0)
    c_pov = (W * yoksul[m][:, None]).sum(0) / tot
    c_fi = (W * yy[:, None]).sum(0) / tot
    noktalar = {"yoksulluk_orani": c_pov, "20": np.full(W.shape[1], 0.20), "30": np.full(W.shape[1], 0.30), "40": np.full(W.shape[1], 0.40), "FI_yayginligi": c_fi}
    out = {}
    for kol in SKOR_KOLLAR[pop]:
        if kol.endswith("_2023") and sema != "temiz_2023":
            continue
        if not kol.endswith("_2023") and sema == "temiz_2023" and kol not in ("gelir_sirasi",):
            continue
        s = skor_al(kol)[m]
        for nk, c in noktalar.items():
            if pop == "B" and nk == "yoksulluk_orani":
                continue
            out[(kol, nk)] = kapsam(s, yy, kk, W, c)
    if pop == "A":
        for kol, f in BAYRAK_KOLLAR.items():
            out[(kol, "kendi")] = bayrak(f[m], yy, kk, W)
    return out


def ozetle(nokta, boot, sema, pop):
    satir = []
    for (kol, nk), v0 in nokta.items():
        vb = boot[(kol, nk)]
        r = {"sema": sema, "nufus": pop, "kol": kol, "kapsama_noktasi": nk}
        for metr in ("kapsama", "duyarlilik", "ppv", "cocuk"):
            r[metr] = float(v0[metr][0])
            r[metr + "_alt"] = float(np.nanpercentile(vb[metr], 2.5))
            r[metr + "_ust"] = float(np.nanpercentile(vb[metr], 97.5))
            r[metr + "_alt_yarim"] = float(np.nanpercentile(vb[metr][:B_YARIM], 2.5))
            r[metr + "_ust_yarim"] = float(np.nanpercentile(vb[metr][:B_YARIM], 97.5))
        r["dislama_hatasi"] = 100 - r["duyarlilik"]
        r["dahil_etme_hatasi"] = 100 - r["ppv"]
        satir.append(r)
    return satir


t0 = time.time()
metrik = []
fark = []
for sema in ("temiz", "tam", "temiz_2023", "temiz_imza", "temiz_siki"):
    for pop in ("A", "B"):
        if sema == "temiz_2023" and pop == "B":
            continue
        n0 = degerlendir(sema, pop, W0)
        nb = degerlendir(sema, pop, WB)
        metrik += ozetle(n0, nb, sema, pop)
        if pop == "A":
            ref0, refb = n0[("yoksul_60", "kendi")], nb[("yoksul_60", "kendi")]
            for (kol, nk), v0 in n0.items():
                if nk != "yoksulluk_orani":
                    continue
                for metr in ("duyarlilik", "ppv", "cocuk"):
                    dlt = nb[(kol, nk)][metr] - refb[metr]
                    fark.append({"sema": sema, "nufus": pop, "kol": kol, "karsilastirma": "yoksul_60", "metrik": metr, "fark": float(v0[metr][0] - ref0[metr][0]),
                                 "alt": float(np.nanpercentile(dlt, 2.5)), "ust": float(np.nanpercentile(dlt, 97.5)),
                                 "alt_yarim": float(np.nanpercentile(dlt[:B_YARIM], 2.5)), "ust_yarim": float(np.nanpercentile(dlt[:B_YARIM], 97.5)),
                                 "p_tek_yonlu": float(np.mean(dlt <= 0))})
        for nk in ("20", "30", "40", "FI_yayginligi"):
            ref0, refb = n0[("gelir_sirasi", nk)], nb[("gelir_sirasi", nk)]
            for (kol, nk2), v0 in n0.items():
                if nk2 != nk or kol == "gelir_sirasi":
                    continue
                for metr in ("duyarlilik", "ppv", "cocuk"):
                    dlt = nb[(kol, nk)][metr] - refb[metr]
                    fark.append({"sema": sema, "nufus": pop, "kol": kol, "karsilastirma": f"gelir_sirasi@{nk}", "metrik": metr, "fark": float(v0[metr][0] - ref0[metr][0]),
                                 "alt": float(np.nanpercentile(dlt, 2.5)), "ust": float(np.nanpercentile(dlt, 97.5)),
                                 "alt_yarim": float(np.nanpercentile(dlt[:B_YARIM], 2.5)), "ust_yarim": float(np.nanpercentile(dlt[:B_YARIM], 97.5)),
                                 "p_tek_yonlu": float(np.mean(dlt <= 0))})
metrik = pd.DataFrame(metrik)
fark = pd.DataFrame(fark)
metrik.to_csv(SON / "H2_hedefleme_metrikleri.csv", index=False)
fark.to_csv(SON / "H2_eslesik_farklar.csv", index=False)
yak = []
for df_, ad in ((metrik, "metrik"), (fark, "fark")):
    if ad == "metrik":
        for metr in ("kapsama", "duyarlilik", "ppv", "cocuk"):
            d_ = np.maximum(np.abs(df_[metr + "_alt"] - df_[metr + "_alt_yarim"]), np.abs(df_[metr + "_ust"] - df_[metr + "_ust_yarim"]))
            ana = df_["sema"].eq("temiz") & df_["nufus"].eq("A")
            yak.append({"tablo": ad, "metrik": metr, "en_buyuk": float(np.nanmax(d_)), "medyan": float(np.nanmedian(d_)), "ana_test_en_buyuk": float(np.nanmax(d_[ana])), "pay_0_1_ustu": float(np.mean(d_ > 0.1))})
    else:
        for metr in ("duyarlilik", "ppv", "cocuk"):
            m_ = df_["metrik"].eq(metr)
            d_ = np.maximum(np.abs(df_.loc[m_, "alt"] - df_.loc[m_, "alt_yarim"]), np.abs(df_.loc[m_, "ust"] - df_.loc[m_, "ust_yarim"]))
            ana = df_.loc[m_, "sema"].eq("temiz")
            yak.append({"tablo": ad, "metrik": metr, "en_buyuk": float(np.nanmax(d_)), "medyan": float(np.nanmedian(d_)), "ana_test_en_buyuk": float(np.nanmax(d_[ana])), "pay_0_1_ustu": float(np.mean(d_ > 0.1))})
yak = pd.DataFrame(yak)
yak.to_csv(LOG / "H2_bootstrap_yakinsama.csv", index=False)
yakinsama = float(yak.loc[yak["metrik"] == "duyarlilik", "ana_test_en_buyuk"].max())
sure_kaydet(f"Hedefleme metrikleri ve eslesik bootstrap (B = {B_BOOT})", t0)
yaz("Bootstrap yakinsama (B/2 ile B arasinda sinir farki, puan):\n" + yak.round(3).to_string())

t0 = time.time()
m_ana = DEGER["temiz"] & POP_M["A"]
yy_a, kk_a, w_a = y[m_ana], cocuk[m_ana], w[m_ana]


def ana_kollar(Wm, kollar):
    c_pov = (Wm * yoksul[m_ana][:, None]).sum(0) / Wm.sum(0)
    v = {kol: kapsam(skor_al(kol)[m_ana], yy_a, kk_a, Wm, c_pov) for kol in kollar}
    v["yoksul_60"] = bayrak(BAYRAK_KOLLAR["yoksul_60"][m_ana], yy_a, kk_a, Wm)
    return v


KOLLAR_EK = ("lgb_A1", "lgb_A2", "logit_lin_A1", "cart_T2")
v0 = ana_kollar(W0[m_ana], KOLLAR_EK)
vb = ana_kollar(WB[m_ana], KOLLAR_EK)
for kol in KOLLAR_EK:
    r_ = fark[(fark["sema"] == "temiz") & (fark["nufus"] == "A") & (fark["kol"] == kol) & (fark["karsilastirma"] == "yoksul_60") & (fark["metrik"] == "duyarlilik")].iloc[0]
    assert abs(float(v0[kol]["duyarlilik"][0] - v0["yoksul_60"]["duyarlilik"][0]) - r_["fark"]) < 1e-9
    assert abs(float(np.percentile(vb[kol]["duyarlilik"] - vb["yoksul_60"]["duyarlilik"], 2.5)) - r_["alt"]) < 1e-9
fark_ek = []
for kol, ref, metrikler in (("lgb_A1", "lgb_A2", ("duyarlilik", "ppv", "cocuk")), ("logit_lin_A1", "lgb_A2", ("duyarlilik",))):
    for metr in metrikler:
        dlt = vb[kol][metr] - vb[ref][metr]
        fark_ek.append({"sema": "temiz", "nufus": "A", "kol": kol, "karsilastirma": ref, "metrik": metr, "fark": float(v0[kol][metr][0] - v0[ref][metr][0]),
                        "alt": float(np.nanpercentile(dlt, 2.5)), "ust": float(np.nanpercentile(dlt, 97.5)),
                        "alt_yarim": float(np.nanpercentile(dlt[:B_YARIM], 2.5)), "ust_yarim": float(np.nanpercentile(dlt[:B_YARIM], 97.5)),
                        "p_tek_yonlu": float(np.mean(dlt <= 0))})
fark_ek = pd.DataFrame(fark_ek)
pd.concat([fark, fark_ek], ignore_index=True).to_csv(SON / "H2_eslesik_farklar.csv", index=False)
yaz("Model-model eslesik farklar (temiz, yoksulluk orani):\n" + fark_ek[["kol", "karsilastirma", "metrik", "fark", "alt", "ust"]].round(2).to_string())

KOLLAR_ARALIK = ("cart_T2", "lgb_A1", "logit_lin_A1")
n_a = len(w_a)
jk = {kol: [] for kol in KOLLAR_ARALIK}
for bas in range(0, n_a, 1000):
    ix = np.arange(bas, min(bas + 1000, n_a))
    Wj = np.repeat(w_a[:, None], len(ix), axis=1)
    Wj[ix, np.arange(len(ix))] = 0.0
    vj = ana_kollar(Wj, KOLLAR_ARALIK)
    for kol in KOLLAR_ARALIK:
        jk[kol].append(vj[kol]["duyarlilik"] - vj["yoksul_60"]["duyarlilik"])
z_ = norm.ppf([0.025, 0.975])
aralik = []
for kol in KOLLAR_ARALIK:
    th = float(v0[kol]["duyarlilik"][0] - v0["yoksul_60"]["duyarlilik"][0])
    bt = vb[kol]["duyarlilik"] - vb["yoksul_60"]["duyarlilik"]
    tj = np.concatenate(jk[kol])
    q = np.percentile(bt, [2.5, 97.5])
    dj = tj.mean() - tj
    a_ = float(np.sum(dj ** 3) / (6 * np.sum(dj ** 2) ** 1.5))
    z0 = float(norm.ppf((np.sum(bt < th) + 0.5 * np.sum(bt == th)) / len(bt)))
    alfa = norm.cdf(z0 + (z0 + z_) / (1 - a_ * (z0 + z_)))
    qb = np.percentile(bt, 100 * alfa)
    for yontem, (lo, hi) in (("yuzdelik", q), ("basic", (2 * th - q[1], 2 * th - q[0])), ("BCa", qb)):
        aralik.append({"sema": "temiz", "nufus": "A", "kol": kol, "karsilastirma": "yoksul_60", "metrik": "duyarlilik", "yontem": yontem, "fark": th, "alt": float(lo), "ust": float(hi),
                       "z0": z0 if yontem == "BCa" else np.nan, "ivme": a_ if yontem == "BCa" else np.nan, "B": B_BOOT, "jackknife_hane": n_a if yontem == "BCa" else np.nan})
aralik = pd.DataFrame(aralik)
aralik.to_csv(SON / "H2_aralik_yontemleri.csv", index=False)
sure_kaydet("Model-model farklari ve aralik yontemleri (yuzdelik, basic, BCa; hane jackknife ivmesi)", t0)
yaz("Aralik yontemleri (duyarlilik farki, yoksulluk cizgisine gore):\n" + aralik[["kol", "yontem", "fark", "alt", "ust", "z0", "ivme"]].round(3).to_string())

t0 = time.time()


def kollar_m(m, Wm, kollar):
    c_pov = (Wm * yoksul[m][:, None]).sum(0) / Wm.sum(0)
    v = {kol: kapsam(skor_al(kol)[m], y[m], cocuk[m], Wm, c_pov) for kol in kollar}
    v["yoksul_60"] = bayrak(BAYRAK_KOLLAR["yoksul_60"][m], y[m], cocuk[m], Wm)
    return v


def yuzde(v, q):
    return float(np.nanpercentile(v, q))


KOLLAR_MM = ("l1_T1T2", "lgb_A1", "logit_lin_A1", "lgb_A2", "logit_lin_A2")
W0a, WBa = W0[m_ana], WB[m_ana]
a0 = kollar_m(m_ana, W0a, KOLLAR_MM)
ab = kollar_m(m_ana, WBa, KOLLAR_MM)
p0 = 100 * (W0a * yy_a[:, None]).sum(0) / W0a.sum(0)
pb = 100 * (WBa * yy_a[:, None]).sum(0) / WBa.sum(0)
tavan = []
for nk, r0_, rb_ in (("yoksulluk_orani", a0["yoksul_60"]["kapsama"], ab["yoksul_60"]["kapsama"]), ("20", 20.0, 20.0), ("30", 30.0, 30.0), ("40", 40.0, 40.0), ("FI_yayginligi", p0, pb)):
    t_0 = np.minimum(100, 100 * np.asarray(r0_) / p0)
    t_b = np.minimum(100, 100 * np.asarray(rb_) / pb)
    tavan.append({"sema": "temiz", "nufus": "A", "kapsama_noktasi": nk, "kapsama": float(np.asarray(r0_).ravel()[0]), "FI_yayginligi": float(p0[0]), "tavan_duyarlilik": float(t_0.ravel()[0]),
                  "tavan_duyarlilik_alt": yuzde(t_b, 2.5), "tavan_duyarlilik_ust": yuzde(t_b, 97.5),
                  "tavan_ppv": float(100 if np.asarray(r0_).ravel()[0] <= p0[0] else 100 * p0[0] / np.asarray(r0_).ravel()[0])})
tavan = pd.DataFrame(tavan)
tavan.to_csv(SON / "H2_tavan.csv", index=False)
tav0 = np.minimum(100, 100 * a0["yoksul_60"]["kapsama"] / p0)
tavb = np.minimum(100, 100 * ab["yoksul_60"]["kapsama"] / pb)
es0, esb = a0["yoksul_60"]["duyarlilik"], ab["yoksul_60"]["duyarlilik"]
kazanc = [{"sema": "temiz", "nufus": "A", "kol": "yoksul_60", "olcu": "esik_tavan_orani", "deger": float(100 * es0[0] / tav0[0]),
           "alt": yuzde(100 * esb / tavb, 2.5), "ust": yuzde(100 * esb / tavb, 97.5), "duyarlilik": float(es0[0]), "esik_duyarlilik": float(es0[0]), "tavan": float(tav0[0])}]
for kol in KOLLAR_MM:
    g0 = 100 * (a0[kol]["duyarlilik"] - es0) / (tav0 - es0)
    gb = 100 * (ab[kol]["duyarlilik"] - esb) / (tavb - esb)
    kazanc.append({"sema": "temiz", "nufus": "A", "kol": kol, "olcu": "ulasilabilir_kazanc_payi", "deger": float(g0[0]), "alt": yuzde(gb, 2.5), "ust": yuzde(gb, 97.5),
                   "duyarlilik": float(a0[kol]["duyarlilik"][0]), "esik_duyarlilik": float(es0[0]), "tavan": float(tav0[0])})
kazanc = pd.DataFrame(kazanc)
kazanc.to_csv(SON / "H2_kazanc_payi.csv", index=False)
KARSILASTIRMA_MM = (("l1_T1T2", "lgb_A1"), ("l1_T1T2", "logit_lin_A1"), ("lgb_A1", "lgb_A2"), ("logit_lin_A1", "logit_lin_A2"))
mm = []
for sema in ("temiz", "temiz_siki"):
    m = DEGER[sema] & POP_M["A"]
    s0, sb = (a0, ab) if sema == "temiz" else (kollar_m(m, W0[m], KOLLAR_MM), kollar_m(m, WB[m], KOLLAR_MM))
    for kol, ref in KARSILASTIRMA_MM:
        for metr in ("duyarlilik", "ppv", "cocuk"):
            dlt = sb[kol][metr] - sb[ref][metr]
            mm.append({"sema": sema, "nufus": "A", "kol": kol, "karsilastirma": ref, "kapsama_noktasi": "yoksulluk_orani", "metrik": metr, "fark": float(s0[kol][metr][0] - s0[ref][metr][0]),
                       "alt": yuzde(dlt, 2.5), "ust": yuzde(dlt, 97.5), "alt_yarim": yuzde(dlt[:B_YARIM], 2.5), "ust_yarim": yuzde(dlt[:B_YARIM], 97.5), "p_tek_yonlu": float(np.mean(dlt <= 0))})
mm = pd.DataFrame(mm)
r_ = fark_ek[(fark_ek["kol"] == "lgb_A1") & (fark_ek["metrik"] == "cocuk")].iloc[0]
q_ = mm[(mm["sema"] == "temiz") & (mm["kol"] == "lgb_A1") & (mm["karsilastirma"] == "lgb_A2") & (mm["metrik"] == "cocuk")].iloc[0]
assert abs(r_["fark"] - q_["fark"]) < 1e-9 and abs(r_["alt"] - q_["alt"]) < 1e-9
mm.to_csv(SON / "H2_model_model_farklar.csv", index=False)


def secim_payi(skor, ww, c):
    u, inv = np.unique(-skor, return_inverse=True)
    Wg = np.bincount(inv, weights=ww)
    once = np.cumsum(Wg) - Wg
    return np.where(Wg > 0, np.clip((c * ww.sum() - once) / np.where(Wg > 0, Wg, 1), 0, 1), 0)[inv]


def agirlikli_medyan(x, ww):
    o = np.argsort(x)
    cw = np.cumsum(ww[o])
    return float(x[o][np.searchsorted(cw, 0.5 * cw[-1])])


c_pov0 = float(np.sum(w_a * yoksul[m_ana]) / w_a.sum())
cocuk_a = te["n_cocuk_ham"].values[m_ana].astype(float)
buyukluk_a = te["hane_buyuklugu"].values[m_ana].astype(float)
yasli_a = te["n_65plus"].values[m_ana].astype(float)
gelir_a = te["goreli_esdeger_gelir"].values[m_ana].astype(float)
secimler = {"tum_haneler": np.ones(len(w_a)), "FI_haneler": yy_a, "yoksul_60": yoksul[m_ana]}
for kol in ("l1_T1T2", "lgb_A1", "logit_lin_A1", "lgb_A2", "cart_T2"):
    secimler[kol] = secim_payi(skor_al(kol)[m_ana], w_a, c_pov0)
profil = []
for ad, f in secimler.items():
    ww = w_a * f
    if ad in KOLLAR_MM or ad == "yoksul_60":
        assert abs(100 * np.sum(ww * yy_a) / np.sum(w_a * yy_a) - a0[ad]["duyarlilik"][0]) < 1e-9
    profil.append({"sema": "temiz", "kol": ad, "secilen_pay": 100 * ww.sum() / w_a.sum(), "duyarlilik": 100 * np.sum(ww * yy_a) / np.sum(w_a * yy_a), "ppv": 100 * np.sum(ww * yy_a) / ww.sum(),
                   "ortalama_cocuk": np.sum(ww * cocuk_a) / ww.sum(), "cocuklu_hane_payi": 100 * np.sum(ww * (cocuk_a >= 1)) / ww.sum(),
                   "tek_kisilik_hane_payi": 100 * np.sum(ww * (buyukluk_a == 1)) / ww.sum(), "yasli_uyeli_hane_payi": 100 * np.sum(ww * (yasli_a >= 1)) / ww.sum(),
                   "medyan_goreli_gelir": agirlikli_medyan(gelir_a, ww), "ortalama_goreli_gelir": np.sum(ww * gelir_a) / ww.sum()})
profil = pd.DataFrame(profil)
profil.to_csv(SON / "H2_secilen_profil.csv", index=False)
sure_kaydet("Hedefleme tavani, ulasilabilir kazanc payi, modeller arasi farklar ve secilen hane profili", t0)
yaz("Tavan:\n" + tavan.round(2).to_string())
yaz("Ulasilabilir kazanc payi:\n" + kazanc.round(2).to_string())
yaz("Modeller arasi farklar:\n" + mm[["sema", "kol", "karsilastirma", "metrik", "fark", "alt", "ust"]].round(2).to_string())
yaz("Secilen hane profili:\n" + profil.round(2).to_string())

esiksiz = []
for sema in ("temiz", "tam", "temiz_2023"):
    for pop in ("A", "B"):
        if sema == "temiz_2023" and pop == "B":
            continue
        m = DEGER[sema] & POP_M[pop]
        yy, W = y[m], WB[m]
        for kol in [k for k in skorlar.columns if k != "hane_kimlik"]:
            if ("B" if "_B" in kol else "A") != pop:
                continue
            if kol.endswith("_2023") != (sema == "temiz_2023"):
                continue
            p = skorlar[kol].values[m]
            a0 = auc_w(p, yy, w[m])
            ab = auc_b(p, yy, W)
            ap0 = float(ap_b(p, yy, w[m][:, None])[0])
            apb = ap_b(p, yy, W)
            br0 = float(brier_b(p, yy, w[m][:, None])[0])
            brb = brier_b(p, yy, W)
            kal = kalibrasyon(p, yy, w[m])
            esiksiz.append({"sema": sema, "nufus": pop, "kol": kol, "n": int(m.sum()), "olay": int(yy.sum()), "auc": a0, "auc_alt": np.percentile(ab, 2.5), "auc_ust": np.percentile(ab, 97.5),
                            "pr_auc": ap0, "pr_auc_alt": np.percentile(apb, 2.5), "pr_auc_ust": np.percentile(apb, 97.5), "brier": br0, "brier_alt": np.percentile(brb, 2.5), "brier_ust": np.percentile(brb, 97.5),
                            "auc_agirliksiz": auc_w(p, yy, np.ones_like(yy)), "pr_auc_agirliksiz": float(ap_b(p, yy, np.ones((len(yy), 1)))[0]), **kal})
        if pop == "A":
            s = gelir_skor[m]
            esiksiz.append({"sema": sema, "nufus": pop, "kol": "gelir_sirasi", "n": int(m.sum()), "olay": int(yy.sum()), "auc": auc_w(s, yy, w[m]),
                            "auc_alt": np.percentile(auc_b(s, yy, W), 2.5), "auc_ust": np.percentile(auc_b(s, yy, W), 97.5),
                            "pr_auc": float(ap_b(s, yy, w[m][:, None])[0]), "auc_agirliksiz": auc_w(s, yy, np.ones_like(yy))})
esiksiz = pd.DataFrame(esiksiz)
esiksiz.to_csv(SON / "H2_esiksiz_metrikler.csv", index=False)
yaz("Esiksiz metrikler yazildi")

m = DEGER["temiz"]
yb, Wb_, w0b = y[m], WB[m], w[m]
c_pov_0 = np.array([np.sum(w0b * yoksul[m]) / w0b.sum()])
c_pov_b = (Wb_ * yoksul[m][:, None]).sum(0) / Wb_.sum(0)
bb = pd.DataFrame(bicim_bilgi).set_index("kol")


def kayip(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return -(yb * np.log(p) + (1 - yb) * np.log(1 - p))


def cv_kayip(kol, s):
    if kol.startswith("logit"):
        pk = loj[kol]
        return float(pk["cv"][np.isclose(pk["cv"]["C"], pk["C"])]["logloss"].mean())
    if kol in bb.index:
        return float(bb.loc[kol, "cv_logloss"])
    return float(ayarlar[s]["logloss_cv"])


bicim_tab = []
for s in BICIM_SETLER:
    onceki = None
    ilk_b = None
    for i, bs in enumerate(("logit_lin", "logit", "lgb_ek", "lgb_d2", "lgb")):
        kol = f"{bs}_{s}"
        p = skorlar[kol].values[m]
        L = kayip(p)
        v0 = {"logloss": float(np.sum(w0b * L) / w0b.sum()), "auc": auc_w(p, yb, w0b), "duyarlilik": float(kapsam(p, yb, cocuk[m], w0b[:, None], c_pov_0)["duyarlilik"][0])}
        vb = {"logloss": (L @ Wb_) / Wb_.sum(0), "auc": auc_b(p, yb, Wb_), "duyarlilik": kapsam(p, yb, cocuk[m], Wb_, c_pov_b)["duyarlilik"]}
        satir = {"set": s, "sira": i + 1, "basamak": bs, "kol": kol, "cv_logloss": cv_kayip(kol, s)}
        for mt in ("logloss", "auc", "duyarlilik"):
            satir[mt] = v0[mt]
            satir[mt + "_alt"], satir[mt + "_ust"] = (float(q) for q in np.percentile(vb[mt], [2.5, 97.5]))
            if onceki is not None:
                dlt = vb[mt] - onceki[1][mt]
                satir["d_" + mt] = v0[mt] - onceki[0][mt]
                satir["d_" + mt + "_alt"], satir["d_" + mt + "_ust"] = (float(q) for q in np.percentile(dlt, [2.5, 97.5]))
                satir["d_" + mt + "_p_iki_yonlu"] = float(2 * min(np.mean(dlt <= 0), np.mean(dlt >= 0)))
            if ilk_b is not None:
                dlt = vb[mt] - ilk_b[1][mt]
                satir["k_" + mt] = v0[mt] - ilk_b[0][mt]
                satir["k_" + mt + "_alt"], satir["k_" + mt + "_ust"] = (float(q) for q in np.percentile(dlt, [2.5, 97.5]))
        bicim_tab.append(satir)
        onceki = (v0, vb)
        if ilk_b is None:
            ilk_b = (v0, vb)
bicim_tab = pd.DataFrame(bicim_tab)
bicim_tab.to_csv(SON / "H2_bicim_merdiveni.csv", index=False)
bicim_tab.to_csv(FV / "fig4c_bicim.csv", index=False)
yaz("Bicim merdiveni:\n" + bicim_tab[["set", "basamak", "cv_logloss", "logloss", "auc", "duyarlilik", "d_logloss", "d_logloss_alt", "d_logloss_ust", "d_auc", "d_duyarlilik"]].round(4).to_string())

tohum_degiskenligi = []
m = DEGER["temiz"]
for s, P in tek_tohum.items():
    pop = SETLER[s][0]
    mm = m & POP_M[pop]
    for i, p in enumerate(P):
        k = kapsam(p[mm], y[mm], cocuk[mm], W0[mm], (W0[mm] * yoksul[mm][:, None]).sum(0) / W0[mm].sum(0) if pop == "A" else np.array([0.2]))
        tohum_degiskenligi.append({"set": s, "tohum": TOHUMLAR[i], "auc": auc_w(p[mm], y[mm], w[mm]), "duyarlilik": float(k["duyarlilik"][0])})
tohum_degiskenligi = pd.DataFrame(tohum_degiskenligi)
tohum_degiskenligi.to_csv(SON / "H2_tohum_degiskenligi.csv", index=False)
yaz("Tohum degiskenligi:\n", tohum_degiskenligi.groupby("set")[["auc", "duyarlilik"]].agg(["mean", "std"]).round(4))

egri = []
m = DEGER["temiz"]
cs = np.round(np.arange(0.02, 0.81, 0.01), 2)
for kol in ["gelir_sirasi", "lgb_A1", "lgb_A2", "lgb_A2i", "lgb_A3", "logit_A1", "cart_T2", "cart_T1T2", "cart_T2idari", "yoksul+lgb_B1", "yoksul+cart_B_T2"]:
    s = skor_al(kol)[m]
    for c in cs:
        k = kapsam(s, y[m], cocuk[m], W0[m], c)
        egri.append({"kol": kol, "kapsama": 100 * c, "duyarlilik": float(k["duyarlilik"][0]), "ppv": float(k["ppv"][0]), "cocuk": float(k["cocuk"][0])})
egri = pd.DataFrame(egri)
egri.to_csv(FV / "fig3a_kapsama_egrileri.csv", index=False)
nokta = metrik[(metrik["sema"] == "temiz") & (metrik["nufus"] == "A") & (metrik["kapsama_noktasi"] == "kendi")][["kol", "kapsama", "duyarlilik", "duyarlilik_alt", "duyarlilik_ust", "ppv"]]
nokta.to_csv(FV / "fig3a_esik_noktalari.csv", index=False)
egri_band = []
for kol in ["lgb_A1", "cart_T2", "gelir_sirasi"]:
    s = skor_al(kol)[m]
    for c in cs[::2]:
        k = kapsam(s, y[m], cocuk[m], WB[m], np.full(B_BOOT, c))
        egri_band.append({"kol": kol, "kapsama": 100 * c, "alt": float(np.percentile(k["duyarlilik"], 2.5)), "ust": float(np.percentile(k["duyarlilik"], 97.5))})
pd.DataFrame(egri_band).to_csv(FV / "fig3a_kapsama_bantlari.csv", index=False)


def net_fayda(p, yy, ww, esikler):
    N = ww.sum()
    out = []
    for pt in esikler:
        sec = p >= pt
        tp = np.sum(ww * yy * sec) / N
        fp = np.sum(ww * (1 - yy) * sec) / N
        out.append(tp - fp * pt / (1 - pt))
    return np.array(out)


esikler_dc = np.round(np.arange(0.05, 0.81, 0.01), 2)
dc = []
prev = np.sum(w[m] * y[m]) / w[m].sum()
for kol in ["lgb_A1", "lgb_A2", "lgb_A2i", "lgb_A3", "logit_A1", "cart_T2", "cart_T1T2"]:
    nf = net_fayda(skorlar[kol].values[m], y[m], w[m], esikler_dc)
    dc += [{"kol": kol, "esik": e, "net_fayda": v} for e, v in zip(esikler_dc, nf)]
for kol, f in (("yoksul_60", BAYRAK_KOLLAR["yoksul_60"]), ("msy_etsiz_5", BAYRAK_KOLLAR["msy_etsiz_5"])):
    nf = net_fayda(f[m].astype(float), y[m], w[m], esikler_dc)
    dc += [{"kol": kol, "esik": e, "net_fayda": v} for e, v in zip(esikler_dc, nf)]
dc += [{"kol": "hepsi", "esik": e, "net_fayda": prev - (1 - prev) * e / (1 - e)} for e in esikler_dc]
pd.DataFrame(dc).to_csv(SON / "H2_karar_egrisi.csv", index=False)
pd.DataFrame(dc).to_csv(FV / "figS_karar_egrisi.csv", index=False)


def kal_egri(p, yy, ww, k=10):
    o = np.argsort(p)
    cw = np.cumsum(ww[o]) / ww.sum()
    grp = np.minimum((cw * k).astype(int), k - 1)
    out = []
    for g in range(k):
        i = o[grp == g]
        out.append({"dilim": g + 1, "tahmin": np.sum(ww[i] * p[i]) / ww[i].sum(), "gozlenen": np.sum(ww[i] * yy[i]) / ww[i].sum(), "n": len(i)})
    return out


t0 = time.time()
yil_paket = {}
yil_oof = {}
for s in ("A1", "A3", "B1"):
    pop, feats = SETLER[s]
    for yy_ in (2023, 2024, 2025):
        f = OB / f"yilmodel_{s}_{yy_}_k{ayarlar[s]['konfig']}_t{ayarlar[s]['n_tur']}_{ozellik_ozeti(feats)}.pkl"
        if f.exists():
            yil_paket[(s, yy_)], yil_oof[(s, yy_)] = pickle.loads(f.read_bytes())
            continue
        d = nufus(h, pop)
        dy = d[d["yil"] == yy_]
        nt = ayarlar[s]["n_tur"]
        par = ayarlar[s]["par"]
        ts = TOHUMLAR[:3]
        tam_m = Parallel(n_jobs=3, backend="loky")(delayed(lgb_egit)(lgb_X(dy, feats), dy["FI"].values, dy["w"].values, par, nt, t, isci=5) for t in ts)
        skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=TOHUM)
        oof = np.zeros(len(dy))
        gorev = []
        for i_tr, i_va in skf.split(dy, dy["FI"].values):
            gorev.append((i_tr, i_va))
        res = Parallel(n_jobs=5, backend="loky")(delayed(lambda a, b: np.mean([lgb_egit(lgb_X(dy.iloc[a], feats), dy["FI"].values[a], dy["w"].values[a], par, nt, t, isci=3).predict(lgb_X(dy.iloc[b], feats)) for t in ts], axis=0))(a, b) for a, b in gorev)
        for (a, b), r in zip(gorev, res):
            oof[b] = r
        paket = {"modeller": [m_.model_to_string() for m_ in tam_m], "feats": feats}
        oof_s = pd.Series(oof, index=dy["hane_kimlik"].values)
        f.write_bytes(pickle.dumps((paket, oof_s)))
        yil_paket[(s, yy_)], yil_oof[(s, yy_)] = paket, oof_s
sure_kaydet("Yil modelleri (3 yil x 3 set, 5 katli OOF)", t0)
yaz("Yil modelleri hazir")

TEMIZ_MASKE = {
    (2023, 2024): lambda d: d["eslesen_onceki_yil"] == 0, (2024, 2025): lambda d: d["eslesen_onceki_yil"] == 0, (2023, 2025): lambda d: d["eslesen_2023"] == 0,
    (2024, 2023): lambda d: d["eslesen_sonraki_yil"] == 0, (2025, 2024): lambda d: d["eslesen_sonraki_yil"] == 0, (2025, 2023): lambda d: d["eslesen_2025"] == 0,
}
matris = []
kal_kayma = []
psi_tab = []
for s in ("A1", "A3", "B1"):
    pop, feats = SETLER[s]
    d = nufus(h, pop)
    for ey in (2023, 2024, 2025):
        for ty in (2023, 2024, 2025):
            dt = d[d["yil"] == ty]
            if ey == ty:
                p = yil_oof[(s, ey)].loc[dt["hane_kimlik"].values].values
                maskeler = {"tam": np.ones(len(dt), dtype=bool)}
            else:
                p = paket_tahmin(yil_paket[(s, ey)], dt)
                maskeler = {"tam": np.ones(len(dt), dtype=bool), "temiz": TEMIZ_MASKE[(ey, ty)](dt).values}
            for mk, mm in maskeler.items():
                yy, ww = dt["FI"].values[mm].astype(float), dt["HB040"].values[mm].astype(float)
                kal = kalibrasyon(p[mm], yy, ww)
                matris.append({"set": s, "egitim_yili": ey, "test_yili": ty, "test_seti": mk if ey != ty else "OOF", "n": int(mm.sum()), "auc": auc_w(p[mm], yy, ww), "brier": float(np.sum(ww * (p[mm] - yy) ** 2) / ww.sum()), **kal})
                if s == "A1" and ey == 2023 and (mk == "temiz" or ey == ty):
                    for r in kal_egri(p[mm], yy, ww):
                        kal_kayma.append({"set": s, "egitim_yili": ey, "test_yili": ty, **r})
    ref_d = d[d["yil"] == 2023]
    ref_p = yil_oof[(s, 2023)].loc[ref_d["hane_kimlik"].values].values
    ref_w = ref_d["HB040"].values
    o = np.argsort(ref_p)
    cw = np.cumsum(ref_w[o]) / ref_w.sum()
    kes = np.interp(np.arange(1, 10) / 10, cw, ref_p[o])
    beklenen = np.array([ref_w[np.digitize(ref_p, kes) == g].sum() for g in range(10)]) / ref_w.sum()
    for ty in (2024, 2025):
        dt = d[d["yil"] == ty]
        pt = paket_tahmin(yil_paket[(s, 2023)], dt)
        wt = dt["HB040"].values
        gercek = np.array([wt[np.digitize(pt, kes) == g].sum() for g in range(10)]) / wt.sum()
        psi = float(np.sum((gercek - beklenen) * np.log(np.maximum(gercek, 1e-6) / np.maximum(beklenen, 1e-6))))
        psi_tab.append({"set": s, "referans": "2023 (OOF)", "yil": ty, "PSI": psi, "ortalama_tahmin": float(np.sum(wt * pt) / wt.sum()), "gozlenen_FI": float(np.sum(wt * dt["FI"].values) / wt.sum())})
matris = pd.DataFrame(matris)
matris.to_csv(SON / "H2_yil_matrisi.csv", index=False)
pd.DataFrame(kal_kayma).to_csv(FV / "figS_kalibrasyon_kaymasi.csv", index=False)
pd.DataFrame(psi_tab).to_csv(SON / "H2_psi.csv", index=False)
yaz("3x3 matris:\n", matris[matris["set"] == "A1"][["egitim_yili", "test_yili", "test_seti", "auc", "kalibrasyon_kesim", "kalibrasyon_egim"]].round(3))
yaz("PSI:\n", pd.DataFrame(psi_tab).round(4))

t0 = time.time()


def shap_deger(paket, df):
    X = lgb_X(df, paket["feats"])
    anahtar = hashlib.md5(("".join(paket["modeller"]) + ",".join(df["hane_kimlik"].astype(str))).encode()).hexdigest()[:16]
    f = OB / f"shap_{anahtar}.npy"
    if f.exists():
        return np.load(f), X
    S = np.mean([lgb.Booster(model_str=m).predict(X, pred_contrib=True, num_threads=ISCI) for m in paket["modeller"]], axis=0)[:, :-1]
    np.save(f, S)
    return S, X


def grup_bul(v):
    for g, l in ETK["grup"].items():
        if v in l:
            return g
    return "Other"


shap_ozet = []
shap_grup = []
dep = []
for ad, paket, dfm in (("A1_ana", paketler["A1"], te[te["test_temiz"] == 1]), ("B1_ana", paketler["B1"], te[(te["test_temiz"] == 1) & (te["yoksul"] == 0)]),
                       ("A3_ana", paketler["A3"], te[te["test_temiz"] == 1])):
    S, X = shap_deger(paket, dfm)
    ww = dfm["HB040"].values
    imp = np.sum(np.abs(S) * ww[:, None], axis=0) / ww.sum()
    r = pd.DataFrame({"model": ad, "degisken": paket["feats"], "ortalama_mutlak_shap": imp})
    r["grup"] = r["degisken"].map(grup_bul)
    r["etiket"] = r["degisken"].map(degisken_etiket)
    r = r.sort_values("ortalama_mutlak_shap", ascending=False)
    r["sira"] = np.arange(1, len(r) + 1)
    shap_ozet.append(r)
    g = r.groupby("grup")["ortalama_mutlak_shap"].sum()
    shap_grup.append(pd.DataFrame({"model": ad, "grup": g.index, "toplam": g.values, "pay": 100 * g.values / g.sum()}))
    if ad in ("A1_ana", "B1_ana"):
        for v in r["degisken"].head(12):
            j = paket["feats"].index(v)
            x = dfm[v]
            sv = S[:, j]
            if v in NOMINAL or x.nunique() <= 12:
                for k in sorted(x.dropna().unique().tolist(), key=lambda z: str(z)) + ["bos"]:
                    mk = x.isna().values if k == "bos" else (x == k).values
                    if mk.sum() < 20:
                        continue
                    dep.append({"model": ad, "degisken": v, "etiket": degisken_etiket(v), "tur": "kategori", "x": str(k), "x_etiket": "Missing" if k == "bos" else kat_etiket(v, k),
                                "shap_ort": float(np.average(sv[mk], weights=ww[mk])), "shap_q25": float(np.percentile(sv[mk], 25)), "shap_q75": float(np.percentile(sv[mk], 75)), "n": int(mk.sum())})
            else:
                xv = x.astype(float).values
                ok = ~np.isnan(xv)
                kes = np.unique(np.nanpercentile(xv[ok], np.linspace(0, 100, 21)))
                bins = np.clip(np.digitize(xv[ok], kes[1:-1]), 0, len(kes) - 2)
                for bi in range(len(kes) - 1):
                    mk = bins == bi
                    if mk.sum() < 20:
                        continue
                    dep.append({"model": ad, "degisken": v, "etiket": degisken_etiket(v), "tur": "sayisal", "x": float(np.median(xv[ok][mk])), "x_etiket": "",
                                "shap_ort": float(np.average(sv[ok][mk], weights=ww[ok][mk])), "shap_q25": float(np.percentile(sv[ok][mk], 25)), "shap_q75": float(np.percentile(sv[ok][mk], 75)), "n": int(mk.sum())})
shap_ozet = pd.concat(shap_ozet)
shap_ozet.to_csv(SON / "H2_shap_onem.csv", index=False)
pd.concat(shap_grup).to_csv(SON / "H2_shap_grup_paylari.csv", index=False)
pd.DataFrame(dep).to_csv(FV / "figS_shap_bagimlilik.csv", index=False)
yaz("SHAP A1 ilk 12:\n", shap_ozet[shap_ozet["model"] == "A1_ana"].head(12)[["degisken", "ortalama_mutlak_shap", "grup"]])
yaz("SHAP grup paylari:\n", pd.concat(shap_grup).round(2))

paket = paketler["A1"]
dfa = te[te["test_temiz"] == 1]
S_a, _ = shap_deger(paket, dfa)
ilk12 = shap_ozet[shap_ozet["model"] == "A1_ana"].head(12)["degisken"].tolist()
wa = dfa["HB040"].values
goster = np.zeros(len(dfa), dtype=bool)
goster[np.random.default_rng(TOHUM + 21).choice(len(dfa), size=4000, replace=False, p=dfa["HB040"].values / dfa["HB040"].sum())] = True
ari = []
for sira, v in enumerate(ilk12):
    j = paket["feats"].index(v)
    x = dfa[v]
    if v in NOMINAL:
        renk = np.full(len(x), np.nan)
    else:
        xv = x.astype(float).values
        ok = ~np.isnan(xv)
        renk = np.full(len(xv), np.nan)
        o = np.argsort(xv[ok], kind="mergesort")
        cw = np.cumsum(wa[ok][o]) - wa[ok][o] / 2
        r_ = np.empty(ok.sum())
        r_[o] = cw / wa[ok].sum()
        r_ = pd.Series(r_).groupby(xv[ok]).transform("mean").values
        renk[ok] = r_
    ari.append(pd.DataFrame({"degisken": v, "etiket": degisken_etiket(v), "sira": sira + 1, "shap": S_a[:, j], "renk": renk, "w": wa, "goster": goster,
                             "ortalama_mutlak_shap": float(np.sum(np.abs(S_a[:, j]) * wa) / wa.sum())}))
pd.concat(ari, ignore_index=True).to_parquet(FV / "fig4a_shap_ari.parquet", index=False)
jg = [paket["feats"].index(v) for v in ("log_goreli_gelir", "hane_gelir_dilim5")]
jy = [paket["feats"].index(v) for v in paket["feats"] if v in T2]
gb = pd.DataFrame({"goreli_gelir": dfa["goreli_esdeger_gelir"].values, "shap_gelir": S_a[:, jg].sum(1), "shap_goreli_gelir": S_a[:, jg[0]], "shap_gelir_dilimi": S_a[:, jg[1]],
                   "shap_yapisal": S_a[:, jy].sum(1), "otomobil": dfa["HH240_var"].values, "FI": dfa["FI"].values, "w": wa,
                   "tahmin": skorlar["lgb_A1"].values[DEGER["temiz"]], "yoksul": dfa["yoksul"].values, "goster": goster})
gb.to_parquet(FV / "fig4b_gelir_bagimlilik.parquet", index=False)
lx = np.log(np.clip(gb["goreli_gelir"].values, 0.01, None))
kes = np.quantile(lx, np.linspace(0, 1, 41))
kb = np.clip(np.digitize(lx, kes[1:-1]), 0, 39)
pd.DataFrame([{"goreli_gelir": float(np.exp(np.average(lx[kb == b_], weights=wa[kb == b_]))), "shap_gelir": float(np.average(gb["shap_gelir"].values[kb == b_], weights=wa[kb == b_])),
               "shap_gelir_q25": float(np.percentile(gb["shap_gelir"].values[kb == b_], 25)), "shap_gelir_q75": float(np.percentile(gb["shap_gelir"].values[kb == b_], 75)),
               "n": int((kb == b_).sum())} for b_ in range(40) if (kb == b_).any()]).to_csv(FV / "fig4b_gelir_egrisi.csv", index=False)

N_H = 400
t_h = time.time()
hs_orn = dfa.iloc[np.random.default_rng(TOHUM + 11).choice(len(dfa), size=N_H, replace=False, p=dfa["HB040"].values / dfa["HB040"].sum())]
Xh = lgb_X(hs_orn, paket["feats"]).reset_index(drop=True)
f_h = OB / f"etkilesim_H_A1_{hashlib.md5(('|'.join(paket['modeller']) + ','.join(hs_orn['hane_kimlik'].astype(str)) + ','.join(ilk12)).encode()).hexdigest()[:16]}.pkl"
if f_h.exists():
    H_cift, H_oz = pickle.loads(f_h.read_bytes())
else:
    H_mod = [lgb.Booster(model_str=s_) for s_ in paket["modeller"]]

    def f_ham(X):
        return np.mean([b_.predict(X, raw_score=True, num_threads=ISCI) for b_ in H_mod], axis=0)

    def anahtar(cols):
        return np.array(["|".join(t) for t in zip(*[[str(v) for v in Xh[c].tolist()] for c in cols])])

    def pd_degerleri(cols):
        k_ = anahtar(cols)
        _, ilk_i, ters = np.unique(k_, return_index=True, return_inverse=True)
        Xb = Xh.iloc[np.tile(np.arange(N_H), len(ilk_i))].reset_index(drop=True)
        for c in cols:
            Xb[c] = Xh[c].iloc[np.repeat(ilk_i, N_H)].values
        pdv = f_ham(Xb).reshape(len(ilk_i), N_H).mean(1)
        out = pdv[ters]
        return out - out.mean()

    f0 = f_ham(Xh)
    f0 = f0 - f0.mean()
    PD1 = {v: pd_degerleri([v]) for v in ilk12}
    H_cift = []
    for a_ in range(len(ilk12)):
        for b_ in range(a_ + 1, len(ilk12)):
            v1, v2 = ilk12[a_], ilk12[b_]
            pd12 = pd_degerleri([v1, v2])
            art = pd12 - PD1[v1] - PD1[v2]
            H_cift.append({"degisken_1": v1, "degisken_2": v2, "H2": float(np.sum(art ** 2) / np.sum(pd12 ** 2)), "H_mutlak": float(np.sqrt(np.mean(art ** 2))), "n": N_H})
    H_oz = []
    for v in ilk12:
        Xb = Xh.iloc[np.repeat(np.arange(N_H), N_H)].reset_index(drop=True)
        Xb[v] = Xh[v].iloc[np.tile(np.arange(N_H), N_H)].values
        pd_d = f_ham(Xb).reshape(N_H, N_H).mean(1)
        pd_d = pd_d - pd_d.mean()
        art = f0 - PD1[v] - pd_d
        H_oz.append({"degisken": v, "H2": float(np.sum(art ** 2) / np.sum(f0 ** 2)), "H_mutlak": float(np.sqrt(np.mean(art ** 2))),
                     "ana_etki_sd": float(np.sqrt(np.mean(PD1[v] ** 2))), "n": N_H})
    H_cift, H_oz = pd.DataFrame(H_cift), pd.DataFrame(H_oz)
    f_h.write_bytes(pickle.dumps((H_cift, H_oz)))
    sure_kaydet(f"Friedman H etkilesim istatistikleri ({N_H} hane, A1 5 tohum, ilk 12 ozellik)", t_h)
H_cift = H_cift.sort_values("H_mutlak", ascending=False)
H_cift["etiket_1"] = H_cift["degisken_1"].map(degisken_etiket)
H_cift["etiket_2"] = H_cift["degisken_2"].map(degisken_etiket)
H_oz["etiket"] = H_oz["degisken"].map(degisken_etiket)
H_cift.to_csv(SON / "H2_etkilesim_H.csv", index=False)
H_oz.to_csv(SON / "H2_etkilesim_H_ozellik.csv", index=False)
H_cift.to_csv(FV / "fig4d_etkilesim.csv", index=False)
etk_yontem = f"Friedman H istatistigi: A1 nihai modeli (5 tohum, log-odds), 2025 ana test setinden agirlikla orantili {N_H} hane, ilk 12 ozellik; kismi bagimlilik orneklem noktalarinda"
yaz("Friedman H ciftler ilk 8:\n" + H_cift.head(8)[["degisken_1", "degisken_2", "H2", "H_mutlak"]].round(4).to_string())
yaz("Friedman H ozellikler:\n" + H_oz.sort_values("H2", ascending=False)[["degisken", "H2", "H_mutlak", "ana_etki_sd"]].round(4).to_string())

yil_shap = []
for s in ("A1", "A3"):
    pop, feats = SETLER[s]
    d = nufus(h, pop)
    for yy_ in (2023, 2024, 2025):
        dy = d[d["yil"] == yy_]
        S, _ = shap_deger(yil_paket[(s, yy_)], dy)
        ww = dy["HB040"].values
        imp = np.sum(np.abs(S) * ww[:, None], axis=0) / ww.sum()
        yil_shap.append(pd.DataFrame({"set": s, "yil": yy_, "degisken": feats, "ortalama_mutlak_shap": imp}))
yil_shap = pd.concat(yil_shap)
yil_shap["grup"] = yil_shap["degisken"].map(grup_bul)
yil_shap["pay"] = 100 * yil_shap["ortalama_mutlak_shap"] / yil_shap.groupby(["set", "yil"])["ortalama_mutlak_shap"].transform("sum")
yil_shap["sira"] = yil_shap.groupby(["set", "yil"])["ortalama_mutlak_shap"].rank(ascending=False, method="first").astype(int)
yil_shap.to_csv(SON / "H2_yil_shap.csv", index=False)
rho = []
for s in ("A1", "A3"):
    pv = yil_shap[yil_shap["set"] == s].pivot(index="degisken", columns="yil", values="ortalama_mutlak_shap")
    for a, b in ((2023, 2024), (2024, 2025), (2023, 2025)):
        rho.append({"set": s, "yil_1": a, "yil_2": b, "spearman": float(spearmanr(pv[a], pv[b]).statistic),
                    "spearman_ilk20": float(spearmanr(pv.loc[pv[a].sort_values(ascending=False).index[:20], a], pv.loc[pv[a].sort_values(ascending=False).index[:20], b]).statistic)})
pd.DataFrame(rho).to_csv(SON / "H2_yil_shap_spearman.csv", index=False)
yg = yil_shap.groupby(["set", "yil", "grup"])["pay"].sum().reset_index()
yg.to_csv(SON / "H2_yil_shap_grup_paylari.csv", index=False)
fig3c = yil_shap[yil_shap["set"] == "A1"].copy()
ilk = fig3c[fig3c["yil"] == 2025].sort_values("ortalama_mutlak_shap", ascending=False)["degisken"].head(12).tolist()
fig3c = fig3c[fig3c["degisken"].isin(ilk)].copy()
fig3c["etiket"] = fig3c["degisken"].map(degisken_etiket)
fig3c.to_csv(FV / "fig4e_yil_shap.csv", index=False)
yg.to_csv(FV / "fig4e_yil_shap_grup.csv", index=False)
sure_kaydet("SHAP (TreeSHAP, LightGBM pred_contrib) ve etkilesim taramasi", t0)
yaz("Yil SHAP Spearman:\n", pd.DataFrame(rho).round(3))

agac_dugum = []
for ad in ("cart_T2", "cart_T1T2", "cart_B_T2"):
    p = cartlar[ad]
    t = p["t"].tree_
    kol = p["kolonlar"]
    egit = nufus(eg, p["pop"])
    Xe = cart_X(egit, p["feats"], p["ref_kat"])[kol]
    yol_m = p["t"].decision_path(Xe)
    ws = egit["w"].values
    ys = egit["FI"].values
    for dgm in range(t.node_count):
        mk = yol_m[:, dgm].toarray().ravel() == 1
        sol = int(t.children_left[dgm])
        f = kol[t.feature[dgm]] if sol != -1 else ""
        agac_dugum.append({"agac": ad, "dugum": dgm, "sol": sol, "sag": int(t.children_right[dgm]), "ozellik": f,
                           "kosul_sol": kosul_metni(f, "sol", t.threshold[dgm], bool(getattr(t, "missing_go_to_left", np.ones(t.node_count, bool))[dgm])) if sol != -1 else "",
                           "kosul_sag": kosul_metni(f, "sag", t.threshold[dgm], bool(getattr(t, "missing_go_to_left", np.ones(t.node_count, bool))[dgm])) if sol != -1 else "",
                           "pay": 100 * ws[mk].sum() / ws.sum(), "FI": 100 * np.sum(ws[mk] * ys[mk]) / ws[mk].sum(), "n": int(mk.sum())})
pd.DataFrame(agac_dugum).to_csv(FV / "fig3c_agac.csv", index=False)

oz = {
    "ayarlar": {s: {"konfig": a["konfig"], "n_tur": a["n_tur"], "cv_logloss": a["logloss_cv"], "cv_auc": a["auc_cv"], **a["par"]} for s, a in ayarlar.items()},
    "lojistik_C": {k: v["C"] for k, v in loj.items()},
    "lojistik_C_nihai": {k: v["C_nihai"] for k, v in loj.items()},
    "bicim_merdiveni": bicim_bilgi,
    "cart": {k: {"yaprak": int(v["t"].get_n_leaves()), "derinlik": int(v["t"].get_depth()), "olcut": v["olcut"], "mwf": v["mwf"], "alpha": v["alpha"], "cv_logloss": v["cv_logloss"], "cv_auc": v["cv_auc"]} for k, v in cartlar.items()},
    "l1": {k: {"C": v["C_l1"], "degiskenler": v["degiskenler"]} for k, v in l1ler.items()},
    "bootstrap": {"B": B_BOOT, "tohum": TOHUM + 7, "yakinsama_yarim_tam_duyarlilik_en_buyuk_fark": yakinsama, "yontem": "Rao-Wu-Yue rescaled bootstrap, n-1 households with replacement, same draws for all arms"},
    "etkilesim_yontemi": etk_yontem,
    "n_test": {k: int(v.sum()) for k, v in DEGER.items()},
    "n_test_B_temiz": int((DEGER["temiz"] & POP_M["B"]).sum()),
    "tohumlar": TOHUMLAR,
}
(SON / "H2_ozet.json").write_text(json.dumps(oz, indent=2, ensure_ascii=False, default=float), encoding="utf-8")
pd.DataFrame(SURE).to_csv(LOG / "ml_sureler.csv", index=False)
yaz("ml.py bitti. Toplam sure (dk):", round((time.time() - T_BAS) / 60, 2))
