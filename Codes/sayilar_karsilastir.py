import json
import sys
from pathlib import Path


def duzlestir(x, on=""):
    if isinstance(x, dict):
        for k, v in x.items():
            yield from duzlestir(v, f"{on}.{k}" if on else str(k))
    elif isinstance(x, list):
        for i, v in enumerate(x):
            yield from duzlestir(v, f"{on}[{i}]")
    else:
        yield on, x


eski = dict(duzlestir(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))))
yeni = dict(duzlestir(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
atla = ("olusturma", "sure", "sure_boot_sn", "sure_dk", "toplam_dk")
ortak = [k for k in eski if k in yeni and not any(a in k for a in atla)]
farkli = []
for k in ortak:
    a, b = eski[k], yeni[k]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if abs(a - b) > 1e-9 * max(1.0, abs(a)):
            farkli.append((k, a, b))
    elif a != b:
        farkli.append((k, a, b))
sadece_eski = [k for k in eski if k not in yeni and not any(a in k for a in atla)]
sadece_yeni = [k for k in yeni if k not in eski and not any(a in k for a in atla)]
print(f"ortak alan {len(ortak)}, farkli {len(farkli)}, yalniz eskide {len(sadece_eski)}, yalniz yenide {len(sadece_yeni)}")
for k, a, b in farkli[:60]:
    print(f"  {k}: {a} -> {b}")
for k in sadece_eski[:20]:
    print("  yalniz eski:", k)
for k in sadece_yeni[:20]:
    print("  yalniz yeni:", k)
