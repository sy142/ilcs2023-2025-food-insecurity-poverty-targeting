import json
from pathlib import Path

import pandas as pd

KOK = Path(__file__).resolve().parents[1]
YASAK_UZANTI = {".parquet", ".rds", ".rdata", ".feather", ".pkl", ".pickle", ".npy", ".npz", ".sav", ".dta", ".sas7bdat"}
KIMLIK = ("kimlik", "hane_id", "fert_id", "hane_1", "hane_2")
ESIK = 2000


def json_en_uzun(x):
    if isinstance(x, list):
        return max([len(x)] + [json_en_uzun(v) for v in x])
    if isinstance(x, dict):
        return max([0] + [json_en_uzun(v) for v in x.values()])
    return 0


satir = []
for klasor in ("Results", "Figures"):
    for f in sorted((KOK / klasor).rglob("*")):
        if not f.is_file() or f == KOK / "Results" / "log" / "gizlilik_taramasi.csv":
            continue
        u = f.suffix.lower()
        r = {"dosya": str(f.relative_to(KOK)), "uzanti": u, "boyut_kb": round(f.stat().st_size / 1024, 1), "satir": None, "kimlik_sutunu": "", "durum": "uygun"}
        if u in YASAK_UZANTI:
            r["durum"] = "MIKRO VERI BICIMI"
        elif u == ".csv":
            d = pd.read_csv(f, low_memory=False)
            r["satir"] = len(d)
            k = [c for c in d.columns if any(s in str(c).lower() for s in KIMLIK)]
            r["kimlik_sutunu"] = ";".join(k)
            if k:
                r["durum"] = "KIMLIK SUTUNU"
            elif len(d) > ESIK:
                r["durum"] = "incelenmeli (satir sayisi)"
        elif u == ".xlsx":
            for ad, d in pd.read_excel(f, sheet_name=None, header=None).items():
                r["satir"] = max(r["satir"] or 0, len(d))
            if r["satir"] > ESIK:
                r["durum"] = "incelenmeli (satir sayisi)"
        elif u == ".json":
            n = json_en_uzun(json.loads(f.read_text(encoding="utf-8")))
            r["satir"] = n
            if n > ESIK:
                r["durum"] = "incelenmeli (dizi uzunlugu)"
        satir.append(r)
t = pd.DataFrame(satir)
(KOK / "Results" / "log").mkdir(parents=True, exist_ok=True)
t.to_csv(KOK / "Results" / "log" / "gizlilik_taramasi.csv", index=False)
print(t["uzanti"].value_counts().to_string())
print(t[t["durum"] != "uygun"].to_string(index=False) if (t["durum"] != "uygun").any() else "Butun dosyalar uygun")
