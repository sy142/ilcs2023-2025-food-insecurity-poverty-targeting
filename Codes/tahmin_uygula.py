import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.interpolate import BSpline

KOK = Path(__file__).resolve().parents[1]
MODK = KOK / "Results" / "modeller"


def oku(yol):
    yol = Path(yol)
    return pd.read_parquet(yol) if yol.suffix == ".parquet" else pd.read_csv(yol)


def on_isle(df, oi):
    d = df.copy()
    for v in oi["metin_sutunlar"]:
        if v in d:
            d[v] = d[v].astype(str)
    for r in oi["kategori_birlestirme"]:
        if r["degisken"] in d:
            d[r["degisken"]] = d[r["degisken"]].replace({r["kod"]: r["hedef"]})
    for r in oi["ust_sinir"]:
        if r["degisken"] in d:
            d[r["degisken"]] = d[r["degisken"]].clip(upper=r["ust"])
    return d


def spline_taban(x, t, k):
    t = np.asarray(t, dtype=float)
    n = len(t) - k - 1
    spl = BSpline.construct_fast(t, np.eye(n), k, extrapolate=False)
    xmin, xmax = t[k], t[-k - 1]
    B = np.zeros((len(x), n))
    ic = (xmin <= x) & (x <= xmax)
    B[ic] = spl(x[ic])
    B[x < xmin, :k] = spl(xmin)[:k]
    B[x > xmax, -k:] = spl(xmax)[-k:]
    return B[:, :-1]


def lojistik_skor(d, js):
    sut = []
    for v in js["ozellikler"]:
        x = d[v]
        if v in js["kategoriler"]:
            for k in js["kategoriler"][v]:
                sut.append((x == k).astype(float).values)
            sut.append(x.isna().astype(float).values)
            continue
        s = js["sayisal"][v]
        xv = x.astype(float)
        bos = xv.isna().values
        xv = xv.fillna(s["medyan"]).values
        if v in js["spline_dugumleri"]:
            sp = js["spline_dugumleri"][v]
            assert sp["dis_deger"] == "constant" and not sp["dahil_sabit"]
            B = spline_taban(xv, sp["dugum_vektoru"], sp["derece"])
            sut += [B[:, j] for j in range(B.shape[1])]
        else:
            sut.append(xv)
        if s["eksik_gostergesi"]:
            sut.append(bos.astype(float))
    X = np.column_stack(sut)
    assert X.shape[1] == len(js["terimler"]), (js["model"], X.shape[1], len(js["terimler"]))
    z = js["sabit"] + ((X - np.array(js["ortalama"])) / np.array(js["standart_sapma"])) @ np.array(js["katsayilar"])
    return 1 / (1 + np.exp(-z))


def modeller_yukle(secim=None):
    out = {}
    for f in sorted((MODK / "lojistik").glob("*.json")):
        js = json.loads(f.read_text(encoding="utf-8"))
        if secim is None or js["model"] in secim:
            out[js["model"]] = js
    return out


def skorla(df, secim=None):
    oi = json.loads((MODK / "on_isleme.json").read_text(encoding="utf-8"))
    d = on_isle(df, oi)
    out = pd.DataFrame(index=df.index)
    for ad, js in modeller_yukle(secim).items():
        out[ad] = lojistik_skor(d, js)
    return out


def denetim():
    veri = KOK / "R_Data ve Python Data"
    h = pd.read_parquet(veri / "hane_2023_2025.parquet")
    te = h[(h["yil"] == 2025) & (h["test_temiz"] == 1)].reset_index(drop=True)
    s = skorla(te)
    ref = pd.read_parquet(veri / "ml" / "skorlar_2025.parquet").set_index("hane_kimlik").loc[te["hane_kimlik"].values]
    sonuc = pd.DataFrame([{"model": k, "n": len(te), "en_buyuk_mutlak_fark": float(np.max(np.abs(s[k].values - ref[k].values)))} for k in s.columns])
    sonuc.to_csv(MODK / "tahmin_uygula_denetim.csv", index=False)
    print(sonuc.to_string(index=False))
    assert sonuc["en_buyuk_mutlak_fark"].max() < 1e-8, "skorlar skorlar_2025 ile uyusmuyor"


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Results/modeller altindaki ridge ve lasso lojistik modelleriyle hane tablosundan gida guvencesizligi skorlari uretir; girdi sutunlari Results/modeller/girdi_sutunlari.csv")
    ap.add_argument("girdi", nargs="?", help="hane tablosu (.csv ya da .parquet)")
    ap.add_argument("cikti", nargs="?", help="skor dosyasi (.csv)")
    ap.add_argument("--modeller", default=None, help="virgulle ayrilmis model adlari (varsayilan: hepsi)")
    ap.add_argument("--kimlik", default=None, help="ciktiya tasinacak kimlik sutunu")
    ap.add_argument("--denetim", action="store_true", help="2025 ana test setinde skorlar_2025 ile karsilastirma (mikro veri gerekir)")
    a = ap.parse_args()
    if a.denetim:
        denetim()
    else:
        df = oku(a.girdi)
        s = skorla(df, a.modeller.split(",") if a.modeller else None)
        if a.kimlik:
            s.insert(0, a.kimlik, df[a.kimlik].values)
        s.to_csv(a.cikti, index=False)
