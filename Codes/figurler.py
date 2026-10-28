import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, PathPatch, Rectangle
from matplotlib.path import Path as MPath
from matplotlib.lines import Line2D
from matplotlib.colors import Normalize
from matplotlib.cm import ScalarMappable
from matplotlib.ticker import FixedLocator, FixedFormatter, NullFormatter, NullLocator

sys.path.insert(0, str(Path(__file__).resolve().parent))
from figur_stili import (VERI, SONUC, TAM, TEK, CM, MUREKKEP, IKINCIL, SOLUK, IZGARA, KAGIT, RENK_GRUP, ETIKET_GRUP, ETIKET_GRUP_KISA, ZEMIN_GRUP,
                         RENK_YOKSUL, GRI_YOKSUL, RENK_YONTEM, ETIKET_YONTEM, RENK_GIDA, ETIKET_GIDA_KISA, ETIKET_BANT, YIL_RENK, AURORA_CMAP,
                         RENK_NEG, RENK_POZ, RENK_KURAL, ZEMIN_KURAL, HALE, DAR, stil_kur, panel_etiketi, panel_etiketi_fig, kaydet)

stil_kur()
EGIT_R = "#8A9BB0"
TEST_R = "#33475E"
ESLES_R = "#C2B9AC"
H3_R = "#7A8794"
ETK = json.loads((Path(__file__).resolve().parent / "etiketler.json").read_text(encoding="utf-8"))


def sayi(n):
    return f"{int(round(n)):,}"


def kisa_ad(v, uzun):
    return ETK.get("degisken_kisa", {}).get(v, uzun)


def serit(ax, x0, y0a, y0b, x1, y1a, y1b, renk, alfa=0.38, z=1):
    xm = (x0 + x1) / 2
    v = [(x0, y0a), (xm, y0a), (xm, y1a), (x1, y1a), (x1, y1b), (xm, y1b), (xm, y0b), (x0, y0b), (x0, y0a)]
    k = [MPath.MOVETO, MPath.CURVE4, MPath.CURVE4, MPath.CURVE4, MPath.LINETO, MPath.CURVE4, MPath.CURVE4, MPath.CURVE4, MPath.CLOSEPOLY]
    ax.add_patch(PathPatch(MPath(v, k), facecolor=renk, edgecolor="none", alpha=alfa, transform=ax.transAxes, zorder=z))


def cubuk(ax, x, ya, yb, renk, w=0.014):
    ax.add_patch(Rectangle((x, yb), w, ya - yb, facecolor=renk, edgecolor="none", transform=ax.transAxes, zorder=3))


def etiket2(ax, x, y, ust, alt_, renk=MUREKKEP, ha="left", boyut=7.0, alt_boyut=5.8):
    ax.text(x, y, ust, ha=ha, va="bottom", fontsize=boyut, fontweight="bold", color=renk, transform=ax.transAxes, zorder=5)
    if alt_:
        ax.text(x, y - 0.008, alt_, ha=ha, va="top", fontsize=alt_boyut, color=IKINCIL, transform=ax.transAxes, zorder=5, linespacing=1.25)


def not_(ax, x, y, s, **kw):
    kw.setdefault("fontsize", 5.6)
    kw.setdefault("color", IKINCIL)
    kw.setdefault("transform", ax.transAxes)
    kw.setdefault("zorder", 6)
    return ax.text(x, y, s, path_effects=HALE, **kw)


def ci_cizgi(ax, x, alt, ust, renk, lw=1.0, z=3, yatay=False):
    if yatay:
        ax.plot([alt, ust], [x, x], color=renk, lw=lw, zorder=z, solid_capstyle="butt")
    else:
        ax.plot([x, x], [alt, ust], color=renk, lw=lw, zorder=z, solid_capstyle="butt")


def gelir_ekseni(ax, etiketli=True):
    ax.set_xscale("log")
    ax.xaxis.set_major_locator(FixedLocator([0.1, 0.25, 0.5, 1, 2, 4]))
    ax.xaxis.set_major_formatter(FixedFormatter(["0.1", "0.25", "0.5", "1", "2", "4"]) if etiketli else NullFormatter())
    ax.xaxis.set_minor_locator(NullLocator())


def figure1():
    a = pd.read_csv(VERI / "fig1a_akis.csv").set_index("dugum")["n"]
    fig = plt.figure(figsize=(TAM, 10.4 * CM))
    axa = fig.add_axes([0.0, 0.0, 1.0, 1.0])
    axa.set_axis_off()
    axa.set_xlim(0, 1)
    axa.set_ylim(0, 1)

    sk = 0.50 / a["hane_toplam"]
    xA, xB = 0.135, 0.36
    yT = 0.88
    axa.text(0.052, yT + 0.055, f"{sayi(a['hane_toplam'])} households", ha="left", va="bottom", fontsize=7.6, fontweight="bold", color=MUREKKEP, transform=axa.transAxes)
    axa.text(0.232, yT + 0.056, f"{sayi(a['kisi_toplam'])} persons · ILCS cross-sections 2023–2025 · H$_1$ uses each year separately",
             ha="left", va="bottom", fontsize=6.2, color=IKINCIL, transform=axa.transAxes)
    y = yT
    blok = {}
    for yil in (2023, 2024, 2025):
        hgt = a[f"hane_{yil}"] * sk
        cubuk(axa, xA, y, y - hgt, EGIT_R if yil < 2025 else TEST_R)
        axa.text(xA - 0.012, y - hgt / 2 + 0.014, f"{yil}", ha="right", va="bottom", fontsize=7.2, fontweight="bold", color=MUREKKEP, transform=axa.transAxes)
        axa.text(xA - 0.012, y - hgt / 2 + 0.006, f"{sayi(a[f'hane_{yil}'])} households\n{sayi(a[f'kisi_{yil}'])} persons", ha="right", va="top", fontsize=6.2,
                 color=IKINCIL, transform=axa.transAxes, linespacing=1.25)
        blok[yil] = (y, y - hgt)
        y -= hgt + 0.04
    h_eg = a["egitim_hane"] * sk
    yE = 0.87
    serit(axa, xA + 0.014, blok[2023][0], blok[2023][1], xB, yE, yE - a["hane_2023"] * sk, EGIT_R, alfa=0.25)
    serit(axa, xA + 0.014, blok[2024][0], blok[2024][1], xB, yE - a["hane_2023"] * sk, yE - h_eg, EGIT_R, alfa=0.25)
    cubuk(axa, xB, yE, yE - h_eg, EGIT_R)
    etiket2(axa, xB + 0.024, yE - 0.07, f"H$_2$ training and tuning · {sayi(a['egitim_hane'])} households",
            f"2023 + 2024; tuning folds validated on households not\nmatched to the training year (2024: {sayi(a['kat_2024_temiz'])}; 2023: {sayi(a['kat_2023_temiz'])});\n"
            f"non-poor model: {sayi(a['egitim_yoksul_degil'])} households", renk=EGIT_R, boyut=7.2, alt_boyut=6.2)
    h_t = a["test_temiz"] * sk
    h_e = a["test_eslesen"] * sk
    yt_ = blok[2025][0]
    yT1 = 0.40
    serit(axa, xA + 0.014, yt_, yt_ - h_t, xB, yT1, yT1 - h_t, TEST_R, alfa=0.28)
    cubuk(axa, xB, yT1, yT1 - h_t, TEST_R)
    etiket2(axa, xB + 0.024, yT1 - 0.004, f"Main test set · {sayi(a['test_temiz'])} households",
            f"2025 households matched to neither 2023 nor 2024\nby member signature or reference-person key;\n{100 * a['test_temiz_tek_kisili'] / a['test_temiz']:.1f}% one-person (unweighted)", renk=TEST_R,
            boyut=7.2, alt_boyut=6.2)
    yT2 = 0.24
    serit(axa, xA + 0.014, yt_ - h_t, yt_ - h_t - h_e, xB, yT2, yT2 - h_e, ESLES_R, alfa=0.45)
    cubuk(axa, xB, yT2, yT2 - h_e, ESLES_R)
    etiket2(axa, xB + 0.024, yT2 - 0.012, f"Re-interviewed, matched to an earlier survey · {sayi(a['test_eslesen'])}",
            f"signature {sayi(a['test_eslesen_imza'])}; reference-person key: +{sayi(a['test_eslesen_reis_tek_kisili'])} one-person,\n"
            f"+{sayi(a['test_eslesen_reis_cok_kisili'])} changed composition; added back in the full-2025 test", renk=IKINCIL, boyut=6.8, alt_boyut=6.2)

    sp = 0.36 / a["kisi_2025"]
    xP, xQ = 0.715, 0.80
    yP = 0.87
    h25 = a["kisi_2025"] * sp
    cubuk(axa, xP, yP, yP - h25, H3_R)
    axa.text(xP - 0.004, yP + 0.014, f"H$_3$ · 2025 · {sayi(a['kisi_2025'])} persons", ha="left", va="bottom", fontsize=7.2, fontweight="bold", color=MUREKKEP, transform=axa.transAxes)
    hy = a["yetiskin_2025"] * sp
    yQ = 0.83
    serit(axa, xP + 0.014, yP, yP - hy, xQ, yQ, yQ - hy, H3_R, alfa=0.22)
    yg = yQ
    for g in (1, 2, 3):
        hg = a[f"yetiskin_G{g}"] * sp
        cubuk(axa, xQ, yg, yg - hg, RENK_GRUP[g])
        axa.text(xQ + 0.022, yg - hg / 2, f"{ETIKET_GRUP_KISA[g]} · {sayi(a[f'yetiskin_G{g}'])}", ha="left", va="center", fontsize=6.4, color=RENK_GRUP[g],
                 fontweight="bold", transform=axa.transAxes)
        yg -= hg
    axa.text(xQ, yQ - hy - 0.025, f"{sayi(a['yetiskin_2025'])} adults aged ≥18\nwith an individual questionnaire", ha="left", va="top",
             fontsize=6.2, color=IKINCIL, transform=axa.transAxes, linespacing=1.25)
    hdis = (a["kisi_2025"] - a["yetiskin_2025"]) * sp
    yD = 0.30
    serit(axa, xP + 0.014, yP - hy, yP - h25, xQ, yD, yD - hdis, "#C7B5A3", alfa=0.5)
    cubuk(axa, xQ, yD, yD - hdis, "#B9A794")
    axa.text(xQ + 0.022, yD - hdis / 2, f"{sayi(a['kisi_2025'] - a['yetiskin_2025'])} aged <18\nor not interviewed", ha="left", va="center", fontsize=6.2,
             color=IKINCIL, transform=axa.transAxes, linespacing=1.2)
    axa.text(xP, 0.12, f"Health-cost outcome: {sayi(a['hane_2025_saglik'])} households\nMeat outcome excludes {sayi(a['vejetaryen'])} vegetarian\nor vegan adults",
             ha="left", va="top", fontsize=6.2, color=IKINCIL, transform=axa.transAxes, linespacing=1.3)
    return kaydet(fig, "Figure1")


def figure2():
    a = pd.read_csv(VERI / "fig2a_yayginlik.csv")
    eg = pd.read_csv(VERI / "fig2b_gelir_egrisi.csv")
    yg = pd.read_csv(VERI / "fig2b_fi_yogunluk.csv")
    tst = pd.read_csv(SONUC / "H1_gelir_egrisi_testleri.csv", dtype={"yil": str})
    bt = pd.read_csv(VERI / "fig2b_hane_tipi.csv")
    c = pd.read_csv(VERI / "fig2c_cocuklar.csv")
    dE = pd.read_csv(VERI / "fig2d_erreygers.csv")
    fig = plt.figure(figsize=(TAM, 14.5 * CM))
    ax = fig.add_axes([0.092, 0.585, 0.48, 0.345])
    panel_etiketi_fig(fig, "a", 0.004, 0.995)
    y = 0.0
    yuk = []
    for yil in (2023, 2024, 2025):
        ax.text(0.3, y + 0.15, str(yil), fontsize=6.8, fontweight="bold", color=MUREKKEP, va="center", ha="left")
        y += 0.65
        for dz, ad in (("hane", "Households"), ("kisi", "Persons")):
            v = a[(a["yil"] == yil) & (a["duzey"] == dz)].set_index("olcu")
            fp, fnp, pv = v.loc["FI_ve_esik", "tahmin"], v.loc["FI_esik_degil", "tahmin"], v.loc["esik", "tahmin"]
            ax.barh(y, fp, height=0.56, color=RENK_GRUP[3], edgecolor="white", linewidth=0.6, zorder=2)
            ax.barh(y, fnp, left=fp, height=0.56, color=RENK_GRUP[2], edgecolor="white", linewidth=0.6, zorder=2)
            ax.barh(y, pv - fp, left=fp + fnp, height=0.56, color=GRI_YOKSUL, edgecolor="white", linewidth=0.6, zorder=2)
            ex, el, eu = v.loc["dislama", "tahmin"], v.loc["dislama", "alt"], v.loc["dislama", "ust"]
            ax.text(fp + fnp + (pv - fp) + 1.0, y, f"{ex:.1f} ({el:.1f}–{eu:.1f})", va="center", ha="left", fontsize=6.0, color=MUREKKEP, path_effects=HALE)
            yuk.append((y, ad))
            y += 0.68
        y += 0.25
    ax.set_yticks([p_ for p_, _ in yuk])
    ax.set_yticklabels([l_ for _, l_ in yuk], fontsize=6.2)
    ax.set_ylim(y - 0.2, -0.55)
    ax.set_xlim(0, 64)
    ax.set_xlabel("Share of households or persons, %")
    ax.grid(axis="y", visible=False)
    not_(ax, 0.995, 1.0, "Exclusion error, % (95% CI)", ha="right", va="top", fontsize=6.0)
    leg = [Rectangle((0, 0), 1, 1, color=RENK_GRUP[3]), Rectangle((0, 0), 1, 1, color=RENK_GRUP[2]), Rectangle((0, 0), 1, 1, color=GRI_YOKSUL)]
    ax.legend(leg, ["Food insecure, poor", "Food insecure, not poor", "Food secure, poor"], loc="lower left", bbox_to_anchor=(0.0, 1.0), ncol=3, fontsize=6.0,
              handlelength=1.0, columnspacing=1.0, borderaxespad=0.3)

    ax = fig.add_axes([0.685, 0.672, 0.30, 0.258])
    axs = fig.add_axes([0.685, 0.585, 0.30, 0.072], sharex=ax)
    panel_etiketi_fig(fig, "b", 0.615, 0.995)
    for yil, lw, alf in ((2023, 1.1, 0.22), (2025, 1.6, 0.20)):
        e = eg[eg["yil"] == yil]
        ax.fill_between(e["goreli_gelir"], e["alt"], e["ust"], color=YIL_RENK[yil], alpha=alf, lw=0, zorder=2)
        ax.plot(e["goreli_gelir"], e["p"], color=YIL_RENK[yil], lw=lw, zorder=3)
    for yil, x_, dy in ((2025, 0.3, 7.0), (2023, 0.3, -8.0)):
        e = eg[eg["yil"] == yil]
        yv = float(np.interp(np.log(x_), np.log(e["goreli_gelir"]), e["p"]))
        ax.text(x_, yv + dy, str(yil), color=YIL_RENK[yil], fontsize=6.4, fontweight="bold", ha="center", va="center", path_effects=HALE, zorder=5)
    ax.axvline(0.6, color=MUREKKEP, lw=0.8, ls=(0, (3, 2)), zorder=4)
    ax.axvline(1.0, color=SOLUK, lw=0.6, ls=(0, (1, 2)), zorder=1)
    ax.text(0.59, 3, "60% line", rotation=90, fontsize=6.0, color=MUREKKEP, ha="right", va="bottom", path_effects=HALE)
    ax.text(0.98, 3, "median", rotation=90, fontsize=6.0, color=SOLUK, ha="right", va="bottom", path_effects=HALE)
    rn = tst[tst["test"] == "dogrusal_olmama"]
    not_(ax, 0.98, 0.96, "non-linearity,\neach year p < 0.001" if (rn["p"] < 0.001).all() else "non-linearity: see Table 2", ha="right", va="top", fontsize=6.2, linespacing=1.15)
    gelir_ekseni(ax)
    ax.tick_params(axis="x", labelbottom=False, length=0)
    ax.set_xlim(0.1, 5)
    ax.set_ylim(0, 100)
    ax.set_ylabel("Food insecure, % of households")
    d25 = yg[yg["yil"] == 2025]
    x_, d_ = d25["goreli_gelir"].values, d25["yogunluk_log"].values
    sol = x_ <= 0.6
    axs.fill_between(x_[sol], 0, d_[sol], color=RENK_GRUP[3], lw=0, alpha=0.85)
    axs.fill_between(x_[~sol], 0, d_[~sol], color=RENK_GRUP[2], lw=0, alpha=0.85)
    axs.fill_between(x_[(x_ >= x_[sol][-1]) & (x_ <= x_[~sol][0])], 0, d_[(x_ >= x_[sol][-1]) & (x_ <= x_[~sol][0])], color=RENK_GRUP[2], lw=0, alpha=0.85)
    v25 = a[(a["yil"] == 2025) & (a["duzey"] == "hane") & (a["olcu"] == "dislama")]["tahmin"].iloc[0]
    axs.text(0.2, d_.max() * 0.55, f"poor {100 - v25:.0f}%", fontsize=6.0, color=RENK_GRUP[3], ha="center", va="center", fontweight="bold", path_effects=HALE)
    axs.text(2.7, d_.max() * 0.55, f"not poor {v25:.0f}%", fontsize=6.0, color=RENK_GRUP[2], ha="center", va="center", fontweight="bold", path_effects=HALE)
    axs.axvline(0.6, color=MUREKKEP, lw=0.8, ls=(0, (3, 2)))
    axs.set_ylim(0, d_.max() * 1.08)
    axs.set_yticks([])
    axs.spines["left"].set_visible(False)
    axs.grid(False)
    gelir_ekseni(axs)
    axs.set_xlim(0.1, 5)
    axs.set_xlabel("Relative income (log scale)")
    axs.text(-0.02, 0.5, "FI\nhouseholds,\n2025", transform=axs.transAxes, fontsize=6.0, color=IKINCIL, ha="right", va="center", linespacing=1.1)

    ax = fig.add_axes([0.215, 0.095, 0.235, 0.345])
    panel_etiketi_fig(fig, "c", 0.004, 0.50)
    t = bt[bt["duzey"] == "hane"].copy().sort_values("dislama")
    yy = np.arange(len(t))
    for yi, (_, r) in zip(yy, t.iterrows()):
        ci_cizgi(ax, yi, r["dislama_alt"], r["dislama_ust"], RENK_GRUP[2], lw=1.1, yatay=True)
        ax.text(111, yi, f"{sayi(r['n_FI'])}", va="center", ha="right", fontsize=6.0, color=SOLUK)
    ax.scatter(t["dislama"], yy, s=20, color=RENK_GRUP[2], zorder=3, edgecolor="white", linewidth=0.6)
    genel = a[(a["yil"] == 2025) & (a["duzey"] == "hane") & (a["olcu"] == "dislama")]["tahmin"].iloc[0]
    ax.axvline(genel, color=SOLUK, lw=0.7, ls=(0, (3, 2)), zorder=1)
    ax.text(genel - 1.2, len(t) - 0.55, f"all {genel:.1f}%", fontsize=6.0, color=SOLUK, ha="right", va="center", path_effects=HALE)
    ax.text(111, len(t) - 0.55, "n FI", fontsize=6.0, color=SOLUK, ha="right", va="center")
    ax.set_yticks(yy)
    ax.set_yticklabels(t["etiket"], fontsize=6.0)
    ax.set_ylim(-0.6, len(t) - 0.2)
    ax.set_xlabel("Exclusion error, % (2025)")
    ax.set_xlim(40, 112)
    ax.set_xticks([40, 60, 80, 100])
    ax.grid(axis="y", visible=False)

    ax = fig.add_axes([0.575, 0.095, 0.17, 0.345])
    panel_etiketi_fig(fig, "d", 0.505, 0.50)
    km = c[c["olcu"] == "cocuk_kacirilan_milyon"].sort_values("yil")
    pay = c[c["olcu"] == "cocuk_dislama"].set_index("yil")
    xx = np.arange(len(km))
    ax.bar(xx, km["tahmin"], color=[YIL_RENK[int(y_)] for y_ in km["yil"]], width=0.6, zorder=2)
    for xi, (_, r) in zip(xx, km.iterrows()):
        ci_cizgi(ax, xi, r["alt"], r["ust"], MUREKKEP, lw=0.8)
        ax.text(xi, r["ust"] + 0.12, f"{pay.loc[r['yil'], 'tahmin']:.1f}%", ha="center", va="bottom", fontsize=6.0, color=MUREKKEP, path_effects=HALE)
    ax.set_xticks(xx)
    ax.set_xticklabels(km["yil"].astype(int))
    ax.set_ylabel("Children in food-insecure,\nnon-poor households, millions", linespacing=1.1)
    ax.set_ylim(0, 6.3)
    ax.set_yticks([0, 1, 2, 3, 4, 5, 6])
    ax.grid(axis="x", visible=False)

    ax = fig.add_axes([0.845, 0.095, 0.145, 0.345])
    panel_etiketi_fig(fig, "e", 0.765, 0.50)
    dE = dE.sort_values("yil")
    xx = np.arange(len(dE))
    for xi, (_, r) in zip(xx, dE.iterrows()):
        ci_cizgi(ax, xi, r["alt"], r["ust"], YIL_RENK[int(r["yil"])], lw=1.2)
    ax.scatter(xx, dE["E"], s=24, color=[YIL_RENK[int(y_)] for y_ in dE["yil"]], zorder=3, edgecolor="white", linewidth=0.6)
    ax.set_xticks(xx)
    ax.set_xticklabels(dE["yil"].astype(int))
    ax.set_xlim(-0.5, 2.5)
    ax.set_ylim(-0.70, -0.40)
    ax.set_yticks([-0.70, -0.60, -0.50, -0.40])
    ax.set_ylabel("Erreygers concentration index")
    ax.grid(axis="x", visible=False)
    not_(ax, 0.04, 0.02, "lower: more concentrated\namong the poor", va="bottom", fontsize=6.0, linespacing=1.15)
    return kaydet(fig, "Figure2")


YONTEM_UZUN = {"cart_T2idari": "Rule set, register-like", "cart_T2": "Rule set, structural", "l1_T2": "Lasso ≤6, structural", "cart_T1T2": "Rule set, income + structural",
               "l1_T1T2": "Lasso ≤6, income + structural", "logit_lin_A1": "Ridge (linear), income + structural", "logit_A1": "Ridge (splines), income + structural",
               "lgb_A2i": "LightGBM, register-like", "lgb_A2": "LightGBM, structural", "lgb_A1": "LightGBM, income + structural", "lgb_A3": "LightGBM, + financial strain"}


def figure3():
    eg = pd.read_csv(VERI / "fig3a_kapsama_egrileri.csv")
    nk = pd.read_csv(VERI / "fig3a_esik_noktalari.csv")
    bn = pd.read_csv(VERI / "fig3a_kapsama_bantlari.csv")
    fk = pd.read_csv(SONUC / "H2_eslesik_farklar.csv")
    ag = pd.read_csv(VERI / "fig3c_agac.csv")
    kr = pd.read_csv(SONUC / "H2_kurallar.csv")
    fig = plt.figure(figsize=(TAM, 19.5 * CM))
    pov = nk.loc[nk["kol"] == "yoksul_60", "kapsama"].iloc[0]
    ax = fig.add_axes([0.075, 0.57, 0.355, 0.40])
    panel_etiketi_fig(fig, "a", 0.004, 0.995)
    ax.plot([0, 80], [0, 80], color="#D0D2D6", lw=0.7, ls=(0, (2, 2)), zorder=0)
    ax.text(70, 66, "random", fontsize=6.0, color=SOLUK, ha="center", va="top", rotation=38, path_effects=HALE)
    ciz = [("gelir_sirasi", "-", 1.0), ("cart_T2", "-", 1.3), ("lgb_A2i", (0, (1.2, 1.2)), 1.2), ("lgb_A2", (0, (4, 1.5)), 1.1), ("lgb_A1", "-", 1.5), ("yoksul+lgb_B1", (0, (5, 1.5, 1, 1.5)), 1.1)]
    for kol, ls, lw in ciz:
        e = eg[eg["kol"] == kol]
        if not len(e):
            continue
        if kol == "yoksul+lgb_B1":
            e = e[e["kapsama"] >= pov - 0.5]
        ax.plot(e["kapsama"], e["duyarlilik"], color=RENK_YONTEM[kol], lw=lw, ls=ls, zorder=3, label=ETIKET_YONTEM[kol])
        b = bn[bn["kol"] == kol]
        if len(b):
            ax.fill_between(b["kapsama"], b["alt"], b["ust"], color=RENK_YONTEM[kol], alpha=0.16, lw=0, zorder=2)
    tv = pd.read_csv(SONUC / "H2_tavan.csv")
    p_fi = tv.loc[tv["kapsama_noktasi"] == "FI_yayginligi", "FI_yayginligi"].iloc[0]
    ax.plot([0, p_fi, 80], [0, 100, 100], color=IKINCIL, lw=0.8, ls=(0, (4, 2)), zorder=6, label="Perfect ranking (ceiling)")
    ax.plot([pov, pov], [0, 61], color=MUREKKEP, lw=0.5, ls=(0, (1, 2)), zorder=1)
    isaret = {"yoksul_60": ("D", 30), "yoksul_50": ("v", 22), "yoksul_70": ("^", 22), "msy_etsiz_5": ("s", 18), "dusuk_is_yogunlugu": ("o", 18)}
    tut = []
    for kol in ("yoksul_60", "yoksul_50", "yoksul_70", "msy_etsiz_5", "dusuk_is_yogunlugu"):
        r = nk[nk["kol"] == kol].iloc[0]
        isi = kol == "yoksul_60"
        mk_, s_ = isaret[kol]
        tut.append(ax.scatter(r["kapsama"], r["duyarlilik"], s=s_, marker=mk_, color=MUREKKEP if isi else "white", edgecolor=MUREKKEP, linewidth=0.8, zorder=6, label=ETIKET_YONTEM[kol]))
    ax.set_xlim(0, 80)
    ax.set_ylim(0, 101.5)
    ax.set_yticks([0, 20, 40, 60, 80, 100])
    ax.set_xlabel("Targeting rate, % of households")
    ax.set_ylabel("Food-insecure households selected, %")
    h_, l_ = ax.get_legend_handles_labels()
    n_c = len(h_) - len(tut)
    lg = ax.legend(h_[:n_c], l_[:n_c], loc="lower right", fontsize=6.0, handlelength=2.4, labelspacing=0.3, borderaxespad=0.2)
    ax.add_artist(lg)
    ax.legend(tut, [ETIKET_YONTEM[k].replace("Very low work intensity", "Very low work\nintensity") for k in ("yoksul_60", "yoksul_50", "yoksul_70", "msy_etsiz_5", "dusuk_is_yogunlugu")],
              loc="upper left", fontsize=6.0, handletextpad=0.3, labelspacing=0.3, borderaxespad=0.3, title="Fixed rules", title_fontsize=6.2, alignment="left",
              frameon=True, facecolor="white", edgecolor="none", framealpha=0.95)

    gruplar = [("Sparse rules, structural", ["cart_T2idari", "cart_T2", "l1_T2"]), ("Sparse rules, income + structural", ["cart_T1T2", "l1_T1T2"]),
               ("Prediction models", ["logit_lin_A1", "logit_A1", "lgb_A2i", "lgb_A2", "lgb_A1", "lgb_A3"])]
    satir = []
    y_ = 0.0
    baslik = []
    for g, kl in gruplar:
        baslik.append((y_, g))
        y_ += 0.85
        for k in kl:
            satir.append((y_, k))
            y_ += 1.0
        y_ += 0.25
    f = fk[(fk["sema"] == "temiz") & (fk["karsilastirma"] == "yoksul_60")]
    for j, (metr, bas, x0) in enumerate((("duyarlilik", "Food-insecure\nhouseholds", 0.665), ("cocuk", "Children in food-\ninsecure households", 0.835))):
        ax = fig.add_axes([x0, 0.57, 0.15, 0.37])
        if j == 0:
            panel_etiketi_fig(fig, "b", 0.455, 0.995)
        ax.axvline(0, color=MUREKKEP, lw=0.7, zorder=1)
        for yy_, k in satir:
            r = f[(f["kol"] == k) & (f["metrik"] == metr)]
            if not len(r):
                continue
            r = r.iloc[0]
            rk = RENK_YONTEM.get(k, MUREKKEP)
            ci_cizgi(ax, yy_, r["alt"], r["ust"], rk, lw=1.3, yatay=True)
            ax.scatter(r["fark"], yy_, s=20, color="white" if k == "logit_lin_A1" else rk, edgecolor=rk, linewidth=0.9, zorder=4)
            if j == 0:
                ax.text(-0.05, yy_, YONTEM_UZUN[k], transform=ax.get_yaxis_transform(), ha="right", va="center", fontsize=6.6, color=MUREKKEP, fontfamily=DAR)
        if j == 0:
            for yy_, g in baslik:
                ax.text(-0.05, yy_, g, transform=ax.get_yaxis_transform(), ha="right", va="center", fontsize=6.6, color=IKINCIL, fontweight="bold", fontfamily=DAR)
        ax.set_ylim(y_ - 0.1, -0.7)
        ax.set_yticks([])
        ax.spines["left"].set_visible(False)
        ax.grid(axis="y", visible=False)
        ax.set_title(bas, fontsize=6.6, color=MUREKKEP, pad=4, loc="center", linespacing=1.1)
        ax.tick_params(labelsize=6.4)

    fig.text(0.825, 0.525, "Difference from the poverty line at its targeting rate, pp", ha="center", va="center", fontsize=6.8, color=MUREKKEP)

    ax = fig.add_axes([0.02, 0.075, 0.96, 0.40])
    panel_etiketi_fig(fig, "c", 0.004, 0.485)
    ax.set_axis_off()
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    t = ag[ag["agac"] == "cart_T2"].set_index("dugum")
    kur = kr[kr["kural_seti"] == "cart_T2"].set_index("yaprak")
    secili = set()
    kum = 0.0
    kalan_yaprak = None
    for yp, r in kur.sort_values("sira").iterrows():
        if kum + r["test_pay"] <= pov:
            secili.add(yp)
            kum += r["test_pay"]
        else:
            kalan_yaprak = yp
            break
    konum = {}

    def yerlestir(dg, x0, x1, derinlik):
        konum[dg] = ((x0 + x1) / 2, 0.90 - derinlik * 0.245)
        if t.loc[dg, "sol"] != -1:
            xm = (x0 + x1) / 2
            yerlestir(int(t.loc[dg, "sol"]), x0, xm, derinlik + 1)
            yerlestir(int(t.loc[dg, "sag"]), xm, x1, derinlik + 1)

    yerlestir(0, 0.0, 1.0, 0)

    def kisa(m):
        for a_, b_ in (("Highest education among adults", "Highest education"), ("Lowest education among adults", "Lowest education"), ("Leaking roof, damp or rot", "Damp or rot"),
                       ("Education of reference person", "Reference person's education"), ("Upper secondary", "upper secondary"), ("Lower secondary", "lower secondary"),
                       ("Satisfaction with dwelling", "Dwelling satisfaction"), ("Share of adults employed", "Share employed"), ("Heating system", "Heating"),
                       (": Tertiary", ": tertiary"), ("≥ Tertiary", "≥ tertiary"), (": not Stove", ": not stove"), (": Stove", ": stove")):
            m = m.replace(a_, b_)
        return m

    def kenar(kos):
        k_ = kisa(kos)
        if ": " in k_:
            return k_.split(": ", 1)[1]
        for isaret in (" ≤ ", " ≥ ", " > ", " = "):
            if isaret in k_:
                return isaret.strip() + " " + k_.split(isaret, 1)[1]
        return k_

    for dg, r in t.iterrows():
        x, y0_ = konum[dg]
        if r["sol"] != -1:
            for cocuk_, kos in ((int(r["sol"]), r["kosul_sol"]), (int(r["sag"]), r["kosul_sag"])):
                xc, yc = konum[cocuk_]
                ax.plot([x, xc], [y0_ - 0.035, yc + 0.045], color=SOLUK, lw=0.7, zorder=1)
                tx, ty_ = x + 0.5 * (xc - x), y0_ - 0.035 + 0.5 * (yc + 0.045 - (y0_ - 0.035))
                ax.text(tx + (0.012 if xc > x else -0.012), ty_ + 0.012, kenar(kos), fontsize=6.4, color=IKINCIL, fontfamily=DAR, ha="left" if xc > x else "right", va="bottom",
                        path_effects=HALE, zorder=2)
            ad = kisa(r["kosul_sag"]).split(":")[0].split(" ≥")[0].split(" >")[0].split(" =")[0]
            ax.text(x, y0_, ad, ha="center", va="center", fontsize=6.8, color=MUREKKEP, fontweight="bold", fontfamily=DAR,
                    bbox=dict(boxstyle="round,pad=0.3", facecolor="white", edgecolor=SOLUK, linewidth=0.6), zorder=3)
        else:
            sec = dg in secili
            kismi = dg == kalan_yaprak
            kr_ = kur.loc[dg]
            ax.add_patch(FancyBboxPatch((x - 0.047, y0_ - 0.115), 0.094, 0.165, boxstyle="round,pad=0,rounding_size=0.012", facecolor=ZEMIN_KURAL if sec else "#F2F2F3",
                                        edgecolor=RENK_KURAL if (sec or kismi) else "#CFD1D5", linewidth=0.9 if sec else 0.6, linestyle=(0, (2, 1.5)) if kismi else "-", zorder=2))
            ax.text(x, y0_ + 0.012, f"{kr_['test_FI']:.0f}%", ha="center", va="center", fontsize=7.4, fontweight="bold", color=MUREKKEP, zorder=3)
            ax.text(x, y0_ - 0.042, f"training {kr_['egitim_FI']:.0f}%", ha="center", va="center", fontsize=6.0, color=IKINCIL, fontfamily=DAR, zorder=3)
            ax.text(x, y0_ - 0.083, f"{kr_['test_pay']:.1f}% of hh", ha="center", va="center", fontsize=6.0, color=IKINCIL, fontfamily=DAR, zorder=3)
    eksik = pov - kum
    fig.text(0.02, 0.012, f"Large: % food insecure, 2025 test set · training: % in 2023–2024 · hh: share of 2025 households · at the {pov:.1f}% targeting rate the rule set takes the shaded leaves\n"
                          f"in full and {eksik:.1f}% of households from the dashed leaf",
             fontsize=6.0, color=IKINCIL, ha="left", va="bottom", linespacing=1.3)
    return kaydet(fig, "Figure3")


def isilti(ax, x, y, renk, s_cekirdek=1.3, s_hale=11, a_cekirdek=0.9, a_hale=0.05, z=3):
    ax.scatter(x, y, s=s_hale, c=renk, alpha=a_hale, linewidths=0, zorder=z, rasterized=True)
    ax.scatter(x, y, s=s_cekirdek, c=renk, alpha=a_cekirdek, linewidths=0, zorder=z + 1, rasterized=True)


def ari_konum(v, rng, genislik=0.38, n_kutu=90):
    lo, hi = np.percentile(v, [0.2, 99.8])
    kb = np.clip(((v - lo) / max(hi - lo, 1e-9) * n_kutu).astype(int), 0, n_kutu - 1)
    sayim = np.bincount(kb, minlength=n_kutu)
    off = np.zeros(len(v))
    for b in np.flatnonzero(sayim):
        i = np.flatnonzero(kb == b)
        i = i[rng.permutation(len(i))]
        k = np.arange(len(i))
        off[i] = np.where(k % 2 == 0, 1, -1) * ((k + 1) // 2)
    olcek = genislik / max(1, (sayim.max() + 1) // 2)
    return off * olcek


def figure4():
    ar = pd.read_parquet(VERI / "fig4a_shap_ari.parquet")
    gb = pd.read_parquet(VERI / "fig4b_gelir_bagimlilik.parquet")
    ge = pd.read_csv(VERI / "fig4b_gelir_egrisi.csv")
    bm = pd.read_csv(VERI / "fig4c_bicim.csv")
    hc = pd.read_csv(VERI / "fig4d_etkilesim.csv")
    ho = pd.read_csv(SONUC / "H2_etkilesim_H_ozellik.csv")
    fig = plt.figure(figsize=(TAM, 18.5 * CM))
    rng = np.random.default_rng(20261026)

    ax = fig.add_axes([0.19, 0.585, 0.43, 0.39])
    panel_etiketi_fig(fig, "a", 0.004, 0.995)
    sira = ar.groupby("degisken")["sira"].first().sort_values()
    n_ = len(sira)
    for v, s in sira.items():
        d = ar[(ar["degisken"] == v) & ar["goster"]]
        yy = (n_ + 1 - s) + ari_konum(d["shap"].values, rng)
        renk = d["renk"].values
        if np.isnan(renk).all():
            isilti(ax, d["shap"].values, yy, "#9AA0A8")
        else:
            isilti(ax, d["shap"].values, yy, AURORA_CMAP(np.nan_to_num(renk, nan=0.5)))
    ax.axvline(0, color=MUREKKEP, lw=0.6, zorder=1)
    ax.set_yticks([n_ + 1 - s for s in sira.values])
    ax.set_yticklabels([kisa_ad(v, ar[ar["degisken"] == v]["etiket"].iloc[0]) for v in sira.index], fontsize=6.8, fontfamily=DAR)
    ax.set_ylim(0.45, n_ + 0.6)
    ax.grid(axis="y", visible=False)
    ax.tick_params(axis="y", length=0)
    ax.spines["left"].set_visible(False)
    ax.set_xlabel("SHAP value, log-odds of food insecurity")
    cax = fig.add_axes([0.255, 0.505, 0.14, 0.009])
    cb = fig.colorbar(ScalarMappable(norm=Normalize(0, 1), cmap=AURORA_CMAP), cax=cax, orientation="horizontal")
    cb.set_ticks([0, 1])
    cb.set_ticklabels(["low", "high"])
    cb.ax.tick_params(labelsize=6.0, length=0, pad=1.5)
    cb.outline.set_visible(False)
    cax.text(-0.05, 0.5, "Feature value", transform=cax.transAxes, fontsize=6.2, color=IKINCIL, ha="right", va="center")
    cax.text(1.06, 0.5, "gray: region (nominal)", transform=cax.transAxes, fontsize=6.0, color=SOLUK, ha="left", va="center")

    ax = fig.add_axes([0.735, 0.585, 0.255, 0.39])
    panel_etiketi_fig(fig, "b", 0.66, 0.995)
    g = gb[gb["goster"]]
    ax.axvspan(0.05, 0.6, color="#F3F0F5", lw=0, zorder=0)
    isilti(ax, np.clip(g["goreli_gelir"].values, 0.06, 7), g["shap_gelir"].values, np.atleast_2d(AURORA_CMAP(0.42)), s_hale=9, a_hale=0.05, a_cekirdek=0.55)
    ax.fill_between(ge["goreli_gelir"], ge["shap_gelir_q25"], ge["shap_gelir_q75"], color=MUREKKEP, alpha=0.10, lw=0, zorder=5)
    ax.plot(ge["goreli_gelir"], ge["shap_gelir"], color=MUREKKEP, lw=1.4, zorder=6)
    ax.axhline(0, color=SOLUK, lw=0.6, zorder=1)
    ax.axvline(0.6, color=MUREKKEP, lw=0.8, ls=(0, (3, 2)), zorder=6)
    ax.axvline(1.0, color=SOLUK, lw=0.6, ls=(0, (1, 2)), zorder=6)
    gelir_ekseni(ax)
    ax.set_xlim(0.08, 6)
    ax.set_xlabel("Relative income (log scale)")
    ax.set_ylabel("Income contribution, log-odds")
    yl = ax.get_ylim()
    ax.text(0.58, yl[0] + 0.03 * (yl[1] - yl[0]), "60% line", rotation=90, fontsize=6.0, color=MUREKKEP, ha="right", va="bottom", path_effects=HALE, zorder=7)
    ax.text(0.97, yl[0] + 0.03 * (yl[1] - yl[0]), "median", rotation=90, fontsize=6.0, color=SOLUK, ha="right", va="bottom", path_effects=HALE, zorder=7)
    ax.grid(axis="x", visible=False)

    adlar = ["Linear", "Splines", "Boosted\nadditive", "Depth-2\n(pairwise)", "Full"]
    for j, (s, bas, x0) in enumerate((("A1", "Income + structural features", 0.075), ("A2", "Structural features only", 0.315))):
        ax = fig.add_axes([x0, 0.09, 0.205, 0.30])
        if j == 0:
            panel_etiketi_fig(fig, "c", 0.004, 0.445)
        b = bm[bm["set"] == s].sort_values("sira")
        xx = np.arange(len(b))
        cv = 1000 * (b["cv_logloss"].iloc[0] - b["cv_logloss"].values)
        ts = np.r_[0.0, -1000 * b["k_logloss"].values[1:]]
        lo_ = np.r_[0.0, -1000 * b["k_logloss_ust"].values[1:]]
        hi_ = np.r_[0.0, -1000 * b["k_logloss_alt"].values[1:]]
        rk = RENK_YONTEM["lgb_A1"] if s == "A1" else RENK_YONTEM["lgb_A2"]
        ax.plot(xx, cv, color=SOLUK, lw=1.0, ls=(0, (3, 1.5)), marker="o", ms=3.2, mfc="white", mec=SOLUK, mew=0.8, zorder=3, label="tuning folds, 2023–2024")
        for xi, l_, h_ in zip(xx[1:], lo_[1:], hi_[1:]):
            ci_cizgi(ax, xi, l_, h_, rk, lw=1.0)
        ax.plot(xx, ts, color=rk, lw=1.4, marker="o", ms=3.6, mec="white", mew=0.5, zorder=4, label="2025 test set")
        ax.axhline(0, color=MUREKKEP, lw=0.6, zorder=1)
        ax.set_xticks(xx)
        ax.set_xticklabels(adlar, fontsize=6.2, fontfamily=DAR)
        ax.set_xlim(-0.35, len(b) - 0.65)
        ax.set_title(bas, fontsize=6.6, color=MUREKKEP, pad=3)
        ax.grid(axis="x", visible=False)
        ax.tick_params(axis="y", labelsize=6.4)
        auc0, auc1 = b["auc"].iloc[0], b["auc"].iloc[-1]
        not_(ax, 0.98, 0.03, f"test AUC: linear {auc0:.3f}, full {auc1:.3f}", ha="right", va="bottom", fontsize=6.0)
        if j == 0:
            ax.set_ylabel(r"Log-loss reduction vs linear, $\times 10^{-3}$")
        else:
            ax.legend([Line2D([0], [0], color=SOLUK, lw=1.0, ls=(0, (3, 1.5)), marker="o", ms=3.2, mfc="white", mec=SOLUK, mew=0.8),
                       Line2D([0], [0], color=MUREKKEP, lw=1.4, marker="o", ms=3.6, mec="white", mew=0.5)],
                      ["tuning folds, 2023–2024", "2025 test set"], loc="upper left", fontsize=6.0, handlelength=2.0, borderaxespad=0.2, labelspacing=0.3)
    ylim = [min(a_.get_ylim()[0] for a_ in fig.axes[-2:]), max(a_.get_ylim()[1] for a_ in fig.axes[-2:])]
    ylim[0] -= 0.10 * (ylim[1] - ylim[0])
    for a_ in fig.axes[-2:]:
        a_.set_ylim(*ylim)

    ax = fig.add_axes([0.745, 0.09, 0.245, 0.30])
    panel_etiketi_fig(fig, "d", 0.545, 0.445)
    top = hc.sort_values("H_mutlak", ascending=False).head(8).iloc[::-1]
    yy = np.arange(len(top))
    rk = AURORA_CMAP(0.42)
    ax.hlines(yy, 0, top["H_mutlak"], color=rk, lw=1.8, zorder=2)
    ax.scatter(top["H_mutlak"], yy, s=24, color=rk, edgecolor="white", linewidth=0.6, zorder=3)
    kisa2 = lambda v: kisa_ad(v, ETK["degisken"].get(v, v)).split(" (")[0]
    ax.set_yticks(yy)
    ax.set_yticklabels([f"{kisa2(a_)} × {kisa2(b_)}" for a_, b_ in zip(top["degisken_1"], top["degisken_2"])], fontsize=6.4, fontfamily=DAR)
    ax.set_xlim(0, top["H_mutlak"].max() * 1.6)
    ax.set_xlabel("Interaction component (log-odds)", fontsize=6.4)
    ax.grid(axis="y", visible=False)
    ax.tick_params(axis="y", length=0)
    ax.tick_params(axis="x", labelsize=6.4)
    gi = ho[ho["degisken"] == "log_goreli_gelir"]
    not_(ax, 0.98, 0.80, f"for scale: SD of the\nincome main effect {gi['ana_etki_sd'].iloc[0]:.2f};\nall interactions of any\nfeature ≤{100 * ho['H2'].max():.1f}% of the\nprediction variance",
         ha="right", va="top", fontsize=6.0, linespacing=1.15)
    return kaydet(fig, "Figure4")


def figure5():
    a = pd.read_csv(VERI / "fig5a_uc_grup.csv")
    b = pd.read_csv(VERI / "fig5b_gelir_bandi.csv")
    c = pd.read_csv(VERI / "fig5c_karsilastirmalar.csv")
    fig = plt.figure(figsize=(TAM, 9.2 * CM))
    gs = fig.add_gridspec(1, 3, width_ratios=[1.35, 1.1, 0.62], left=0.07, right=0.99, top=0.83, bottom=0.17, wspace=0.36)
    ax = fig.add_subplot(gs[0, 0])
    panel_etiketi(ax, "a", x=-0.12, y=1.15)
    gidalar = ["et_az", "meyve_az", "sebze_az"]
    for i, gd in enumerate(gidalar):
        r = a[(a["analiz"] == "C0_uc_grup") & (a["sonuc"] == gd)].set_index("olcu")
        for j, g in enumerate((1, 2, 3)):
            x = i + (j - 1) * 0.25
            ax.bar(x, r.loc[f"p_G{g}", "tahmin"], width=0.22, color=RENK_GRUP[g], zorder=2)
            ci_cizgi(ax, x, r.loc[f"p_G{g}", "alt"], r.loc[f"p_G{g}", "ust"], MUREKKEP, lw=0.8)
        pd1 = c[(c["duzey"] == "yetiskin") & (c["karsilastirma"] == "C1") & (c["sonuc"] == gd)].set_index("olcu").loc["PD"]
        ust = r.loc[["p_G1", "p_G2", "p_G3"], "ust"].max()
        ax.text(i, ust + 3.5, f"adj. Δ {pd1['tahmin']:+.1f}\n({pd1['alt']:.1f}–{pd1['ust']:.1f})", ha="center", va="bottom", fontsize=6.0, color=MUREKKEP, linespacing=1.15,
                path_effects=HALE)
    ax.set_xticks(range(3))
    ax.set_xticklabels(["Meat, chicken, fish\n<1 per week", "Fruit\n<1 per day", "Vegetables, salad\n<1 per day"], fontsize=6.4)
    ax.set_ylabel("Standardized prevalence, % of adults")
    ax.set_ylim(0, 100)
    ax.grid(axis="x", visible=False)
    leg = [Rectangle((0, 0), 1, 1, color=RENK_GRUP[g]) for g in (1, 2, 3)]
    ax.legend(leg, [ETIKET_GRUP[g] for g in (1, 2, 3)], loc="lower left", bbox_to_anchor=(0.0, 1.0), ncol=3, fontsize=6.2, handlelength=1.0, columnspacing=0.9, borderaxespad=0.4)

    ax = fig.add_subplot(gs[0, 1])
    panel_etiketi(ax, "b", x=-0.14, y=1.15)
    xx = np.arange(5)
    ax.axvspan(-0.6, 0.5, color="#F2F2F4", zorder=0, lw=0)
    stiller = {"et_az": ("o", "-", "Meat"), "meyve_az": ("s", (0, (4, 1.5)), "Fruit"), "sebze_az": ("D", (0, (1.2, 1.2)), "Vegetables")}
    for gd in gidalar:
        mk_, ls, ad = stiller[gd]
        r = b[(b["analiz"] == "C3_gelir_bandi") & (b["sonuc"] == gd)].sort_values("bant")
        ax.fill_between(xx, r["alt"], r["ust"], color=MUREKKEP, alpha=0.07, lw=0, zorder=2)
        ax.plot(xx, r["tahmin"], color=MUREKKEP, lw=1.2, ls=ls, marker=mk_, ms=3.8, mfc="white", mec=MUREKKEP, mew=0.9, zorder=3)
        ax.text(4.3, r["tahmin"].iloc[-1], ad, fontsize=6.4, color=MUREKKEP, va="center", ha="left", fontweight="bold", path_effects=HALE)
    nb = b[(b["analiz"] == "C3_gelir_bandi") & (b["sonuc"] == "et_az")].sort_values("bant")
    ax.set_xticks(xx)
    ax.set_xticklabels([ETIKET_BANT[str(int(k))] for k in nb["bant"]], fontsize=6.0)
    for xi, n in zip(xx, nb["n_bant"]):
        ax.text(xi, 4.0, f"{sayi(n)}", ha="center", va="bottom", fontsize=6.0, color=SOLUK, path_effects=HALE)
    ax.text(-0.5, 12.0, "n adults", ha="left", va="bottom", fontsize=6.0, color=SOLUK, path_effects=HALE)
    ax.text(0.05, 97, "poor", fontsize=6.0, color=SOLUK, ha="center", va="top")
    ax.set_xlim(-0.6, 5.6)
    ax.set_ylim(0, 100)
    ax.set_xlabel("Relative income (food-insecure adults)")
    ax.set_ylabel("Standardized prevalence, %")
    ax.grid(axis="x", visible=False)
    ax.spines["bottom"].set_bounds(-0.6, 4.3)

    ax = fig.add_subplot(gs[0, 2])
    panel_etiketi(ax, "c", x=-0.30, y=1.15)
    r = a[(a["analiz"] == "C0_uc_grup_hane") & (a["sonuc"] == "saglik_yuk")].set_index("olcu")
    for j, g in enumerate((1, 2, 3)):
        ax.bar(j, r.loc[f"p_G{g}", "tahmin"], width=0.62, color=RENK_GRUP[g], zorder=2)
        ci_cizgi(ax, j, r.loc[f"p_G{g}", "alt"], r.loc[f"p_G{g}", "ust"], MUREKKEP, lw=0.8)
    pdh = c[(c["duzey"] == "hane") & (c["karsilastirma"] == "C1")].set_index("olcu").loc["PD"]
    ax.text(1, r.loc[["p_G1", "p_G2", "p_G3"], "ust"].max() + 1.0, f"adj. Δ {pdh['tahmin']:+.1f}\n({pdh['alt']:.1f}–{pdh['ust']:.1f})", ha="center", va="bottom",
            fontsize=6.0, color=MUREKKEP, linespacing=1.15, path_effects=HALE)
    ax.set_xticks(range(3))
    ax.set_xticklabels(["G1", "G2", "G3"])
    ax.set_ylabel("Heavy health-cost burden, % of households")
    ax.set_ylim(0, r.loc[["p_G1", "p_G2", "p_G3"], "ust"].max() + 6)
    ax.set_yticks([0, 5, 10, 15, 20])
    ax.grid(axis="x", visible=False)
    return kaydet(fig, "Figure5")


def figure6():
    s1 = pd.read_csv(VERI / "fig6a_ortusme_iyimserligi.csv")
    s2 = pd.read_csv(VERI / "fig6b_yanlis_siniflama.csv")
    s3 = pd.read_csv(VERI / "fig6c_kapsama.csv")
    fig = plt.figure(figsize=(TAM, 7.2 * CM))
    icc_renk = {0.3: SOLUK, 0.6: MUREKKEP}
    ax = fig.add_axes([0.07, 0.20, 0.25, 0.71])
    panel_etiketi_fig(fig, "a", 0.004, 0.99)
    gz = s1[(s1["ortusme_tanim"] == "gercek") & (s1["test_seti"].str.startswith("temiz"))].copy()
    gz["gizli"] = np.where(gz["test_seti"] == "temiz", 0.0, pd.to_numeric(gz["test_seti"].str.replace("temiz_gizli_", ""), errors="coerce"))
    for icc, mk_ in ((0.3, "o"), (0.6, "s")):
        r = gz[gz["icc"] == icc].sort_values("gizli")
        ax.errorbar(r["gizli"], r["iyimserlik_duyarlilik"], yerr=1.96 * r["iyimserlik_duyarlilik_mcse"], color=icc_renk[icc], marker=mk_, ms=3.8, lw=1.2, capsize=0,
                    markeredgecolor="white", markeredgewidth=0.5, label=f"latent ICC {icc}")
    ax.axhline(0, color=SOLUK, lw=0.6)
    gx = sorted(gz["gizli"].unique())
    ax.set_xticks(gx)
    ax.set_xticklabels([f"{x:g}" for x in gx], fontsize=6.4)
    ax.set_xlabel("Undetected re-interviewed, % of test set")
    ax.set_ylabel("Optimism in sensitivity, pp")
    ax.legend(fontsize=6.0, loc="upper left", borderaxespad=0.3)
    ax.grid(axis="x", visible=False)

    ax = fig.add_axes([0.43, 0.20, 0.27, 0.71])
    panel_etiketi_fig(fig, "b", 0.355, 0.99)
    kf = pd.read_csv(VERI / "fig6b_kapali_form_egrisi.csv")
    sp_sinir = 100 * kf["uyumlu_en_kucuk_Sp"].max()
    ax.axvspan(90, sp_sinir, color="#ECEEF1", lw=0, zorder=0)
    tur_ls = {"ayrimci_degil": "-", "gelire_gore": (0, (3, 1.6))}
    for tur, ls in tur_ls.items():
        e = kf[(kf["tur"] == tur) & (kf["Se"] == 0.90)].sort_values("Sp")
        ax.plot(100 * e["Sp"], e["kapali_form_dislama_hane"], color=MUREKKEP, lw=1.0 if tur == "ayrimci_degil" else 0.8, ls=ls, zorder=2)
    sea = sorted(s2["Se"].unique())
    tonlar = AURORA_CMAP(np.linspace(0.2, 0.75, len(sea)))
    kay = np.linspace(-0.09, 0.09, len(sea))
    se_h = []
    for se, rk, dx in zip(sea, tonlar, kay):
        for tur, ofs, dolu in (("ayrimci_degil", -0.22, True), ("gelire_gore", 0.22, False)):
            r = s2[(s2["tur"] == tur) & (s2["Se"] == se) & s2["uyumlu"].astype(bool)]
            ax.scatter(100 * r["Sp"] + ofs + dx, r["dislama_hatasi"], s=11, marker="o", color=rk if dolu else "white", edgecolor=rk, linewidth=0.7, zorder=4)
        se_h.append(Line2D([], [], ls="none", marker="o", ms=3.4, color=rk, label=f"Se {se:.2f}"))
    gzv = s2["gozlenen_dislama_hatasi"].iloc[0]
    ax.axhline(gzv, color=MUREKKEP, lw=0.5, ls=(0, (1, 1.5)), zorder=1)
    ax.text(90.2, gzv + 0.05, "observed", fontsize=6.0, color=MUREKKEP, va="bottom", ha="left")
    ax.text(sp_sinir - 0.15, 62.0, "incompatible\nwith observed\ndata", fontsize=6.0, color=IKINCIL, ha="right", va="bottom", linespacing=1.1, zorder=5)
    ax.set_xlim(90, 100)
    ax.set_ylim(61.8, 68.7)
    ax.set_xticks([90, 92, 94, 96, 98, 100])
    ax.set_xlabel("Specificity of HE090, %")
    ax.set_ylabel("Exclusion error, % of households")
    tur_h = [Line2D([], [], color=MUREKKEP, lw=1.0, ls=tur_ls["ayrimci_degil"], marker="o", ms=3.2, markerfacecolor=SOLUK, markeredgecolor=SOLUK, label="non-differential"),
             Line2D([], [], color=MUREKKEP, lw=0.8, ls=tur_ls["gelire_gore"], marker="o", ms=3.2, markerfacecolor="white", markeredgecolor=SOLUK, label="income-differential")]
    lg = ax.legend(handles=tur_h, loc="upper left", bbox_to_anchor=(0.0, 0.94), fontsize=5.8, handlelength=2.2, labelspacing=0.3, handletextpad=0.4, borderaxespad=0.3, frameon=False,
                   title="line: closed form\nmarker: simulated mean", title_fontsize=5.8, alignment="left")
    ax.add_artist(lg)
    ax.legend(handles=se_h, loc="lower right", bbox_to_anchor=(1.0, 0.24), ncol=2, fontsize=5.8, handletextpad=0.1, columnspacing=0.6, labelspacing=0.3, borderaxespad=0.3, frameon=False)

    ax = fig.add_axes([0.85, 0.20, 0.135, 0.71])
    panel_etiketi_fig(fig, "c", 0.725, 0.99)
    ad = {"dislama_hatasi": "Exclusion error", "kural_duyarlilik": "Rule-set\nsensitivity", "kural_ppv": "Rule-set PPV"}
    for i, k_ in enumerate(ad):
        r = s3[s3["olcu"] == k_].iloc[0]
        ax.errorbar(r["kapsama"], i, xerr=1.96 * r["kapsama_mcse"], color=MUREKKEP, marker="o", ms=3.8, lw=1.0, capsize=0)
        ax.text(r["kapsama"], i + 0.2, f"{r['kapsama']:.1f}", ha="center", va="bottom", fontsize=6.2, color=MUREKKEP, path_effects=HALE)
    ax.axvline(95, color=MUREKKEP, lw=0.8, ls=(0, (6, 2)))
    ax.set_yticks(range(3))
    ax.set_yticklabels(list(ad.values()), fontsize=6.6, fontfamily=DAR)
    ax.set_xlim(88, 100)
    ax.set_xticks([90, 95, 100])
    ax.set_ylim(-0.6, 2.75)
    ax.set_xlabel("Interval coverage, %")
    ax.grid(axis="y", visible=False)
    return kaydet(fig, "Figure6")


def figureS_karar():
    d = pd.read_csv(VERI / "figS_karar_egrisi.csv")
    fig, ax = plt.subplots(figsize=(TEK * 1.3, 9.0 * CM))
    fig.subplots_adjust(left=0.12, right=0.98, top=0.97, bottom=0.345)
    renk = {"lgb_A1": RENK_YONTEM["lgb_A1"], "lgb_A2": RENK_YONTEM["lgb_A2"], "lgb_A2i": RENK_YONTEM["lgb_A2i"], "logit_A1": RENK_YONTEM["logit_A1"], "cart_T2": RENK_YONTEM["cart_T2"],
            "yoksul_60": MUREKKEP, "msy_etsiz_5": "#8C7B6B", "hepsi": SOLUK}
    ad = {"lgb_A1": "LightGBM, income + structural", "lgb_A2": "LightGBM, structural", "lgb_A2i": "LightGBM, register-like", "logit_A1": "Ridge (splines), income + structural", "cart_T2": "Rule set, structural",
          "yoksul_60": "Poverty line (60%)", "msy_etsiz_5": "MSD ≥5 (same deprivation battery)", "hepsi": "Select all"}
    ls = {"lgb_A2": (0, (4, 1.5)), "lgb_A2i": (0, (1.2, 1.2)), "logit_A1": (0, (5, 1.5, 1, 1.5)), "hepsi": (0, (2, 2))}
    for k, rk in renk.items():
        r = d[d["kol"] == k]
        if not len(r):
            continue
        ax.plot(r["esik"], r["net_fayda"], color=rk, lw=0.9 if k == "hepsi" else 1.2, ls=ls.get(k, "-"), label=ad[k])
    ax.axhline(0, color=SOLUK, lw=0.6)
    ax.set_ylim(-0.05, 0.42)
    ax.set_xlabel("Threshold probability")
    ax.set_ylabel("Net benefit")
    ax.legend(fontsize=6.0, loc="upper center", bbox_to_anchor=(0.45, -0.17), ncol=2, handlelength=2.2, columnspacing=1.2, labelspacing=0.45)
    return kaydet(fig, "FigureS1", ek=True)


def figureS_kalibrasyon():
    kk = pd.read_csv(VERI / "figS_kalibrasyon_kaymasi.csv")
    mt = pd.read_csv(SONUC / "H2_yil_matrisi.csv")
    kb = pd.read_csv(VERI / "figS2b_kalibrasyon_2025.csv")
    fig, (ax, bx) = plt.subplots(1, 2, figsize=(TAM, 8.4 * CM))
    ax.plot([0, 1], [0, 1], color="#D0D2D6", lw=0.8, ls=(0, (2, 2)), zorder=0)
    for ty, mk_ in ((2023, "o"), (2024, "s"), (2025, "^")):
        k_ = kk[kk["test_yili"] == ty]
        ax.plot(k_["tahmin"], k_["gozlenen"], color=YIL_RENK[ty], lw=1.1, marker=mk_, ms=3.4, markeredgecolor="white", markeredgewidth=0.5, zorder=3)
        m = mt[(mt["set"] == "A1") & (mt["egitim_yili"] == 2023) & (mt["test_yili"] == ty) & (mt["test_seti"].isin(["temiz", "OOF"]))].iloc[0]
        lab = "2023, cross-fitted" if ty == 2023 else f"{ty}"
        ax.text(0.03, 0.97 - 0.10 * (ty - 2023), f"{lab}\nintercept " + (f"{m['kalibrasyon_kesim']:+.2f}".replace("-", "−") if abs(m["kalibrasyon_kesim"]) >= 0.005 else "0.00") + f", slope {m['kalibrasyon_egim']:.2f}",
                transform=ax.transAxes, fontsize=6.0, color=YIL_RENK[ty], ha="left", va="top", fontweight="bold", linespacing=1.1, path_effects=HALE)
    ax.set_xlim(0, 1)
    ax.set_ylim(0, 1)
    ax.set_xlabel("Predicted probability, model trained on 2023")
    ax.set_ylabel("Observed food insecurity")
    not_(ax, 0.97, 0.03, "deciles of predicted risk;\nhouseholds not matched\nto the training year", ha="right", va="bottom", fontsize=6.0, color=SOLUK, linespacing=1.1)
    panel_etiketi(ax, "a")
    bx.plot([0, 1], [0, 1], color="#D0D2D6", lw=0.8, ls=(0, (2, 2)), zorder=0)
    s2b = (("lgb_A1", "LightGBM, income + structural", RENK_YONTEM["lgb_A1"], "o", "-", "white"),
           ("logit_lin_A1", "Ridge (linear), income + structural", RENK_YONTEM["logit_lin_A1"], "s", (0, (4, 1.5)), "white"),
           ("l1_T1T2", "Lasso ≤6, income + structural", RENK_YONTEM["l1_T1T2"], "D", (0, (1.2, 1.2)), "white"),
           ("lgb_A2", "LightGBM, structural", RENK_YONTEM["lgb_A2"], "^", (0, (5, 1.5, 1, 1.5)), "white"))
    tut = []
    for kol, ad_, rk, mk_, ls_, ke in s2b:
        k_ = kb[kb["kol"] == kol].sort_values("dilim")
        bx.plot(k_["tahmin"], k_["gozlenen"], color=rk, lw=1.1, ls=ls_, marker=mk_, ms=3.2, markeredgecolor=ke, markeredgewidth=0.5, zorder=3)
        r = k_.iloc[0]
        kes = f"{r['kalibrasyon_kesim']:+.2f}".replace("-", "−")
        tut.append((Line2D([0], [0], color=rk, lw=1.1, ls=ls_, marker=mk_, ms=3.2, markeredgecolor=ke, markeredgewidth=0.5), f"{ad_}\nintercept {kes}, slope {r['kalibrasyon_egim']:.2f}"))
    bx.legend([t[0] for t in tut], [t[1] for t in tut], loc="lower right", fontsize=5.8, frameon=False, handlelength=2.4, labelspacing=0.45, borderaxespad=0.2)
    bx.set_xlim(0, 1)
    bx.set_ylim(0, 1)
    bx.set_xlabel("Predicted probability, models trained on 2023–2024")
    bx.set_ylabel("Observed food insecurity")
    not_(bx, 0.03, 0.97, "deciles of predicted risk;\n2025 main test set", ha="left", va="top", fontsize=6.0, color=SOLUK, linespacing=1.1)
    panel_etiketi(bx, "b")
    fig.tight_layout(w_pad=2.2)
    return kaydet(fig, "FigureS2", ek=True)


def figureS_shap():
    d = pd.read_csv(VERI / "figS_shap_bagimlilik.csv")
    d = d[d["model"] == "A1_ana"]
    sira = d.groupby("degisken", sort=False).size().index.tolist()[:12]
    bolge = ETK.get("bolge_nuts2", {})
    fig = plt.figure(figsize=(TAM, 20.0 * CM))
    gs = fig.add_gridspec(4, 4, left=0.08, right=0.985, top=0.962, bottom=0.075, hspace=0.68, wspace=0.42)
    bos = iter([(0, 0), (0, 1), (0, 3), (1, 0), (1, 1), (1, 3), (2, 0), (2, 1), (2, 3), (3, 0), (3, 1), (3, 3)])
    for i, v in enumerate(sira):
        r = d[d["degisken"] == v].copy()
        ax = fig.add_subplot(gs[0:4, 2]) if v == "HB031" else fig.add_subplot(gs[next(bos)])
        if v == "HB031":
            p_ = ax.get_position()
            ax.set_position([p_.x0 + 0.035, p_.y0, p_.width - 0.035, p_.height])
        if r["tur"].iloc[0] == "kategori":
            if v == "HB031":
                r = r.sort_values("shap_ort")
                yy = np.arange(len(r))
                renk = AURORA_CMAP(0.3)
                ax.hlines(yy, r["shap_q25"], r["shap_q75"], color=renk, lw=0.9, alpha=0.6)
                ax.scatter(r["shap_ort"], yy, s=12, color=renk, zorder=3, edgecolor="white", linewidth=0.4)
                ax.set_yticks(yy)
                ax.set_yticklabels([f"{z} {bolge.get(str(z), '')}".strip() for z in r["x"]], fontsize=6.0, fontfamily=DAR)
                ax.set_ylim(-0.7, len(r) - 0.3)
                ax.set_xlabel("SHAP value, log-odds", fontsize=6.4)
                ax.axvline(0, color=SOLUK, lw=0.6)
                ax.grid(axis="y", visible=False)
                ax.tick_params(axis="y", length=0, pad=1)
            else:
                xx = np.arange(len(r))
                renk = AURORA_CMAP(0.3)
                ax.vlines(xx, r["shap_q25"], r["shap_q75"], color=renk, lw=1.0, alpha=0.6)
                ax.scatter(xx, r["shap_ort"], s=22, color=renk, zorder=3, edgecolor="white", linewidth=0.5)
                ax.set_xticks(xx)
                ax.set_xticklabels([str(z) if len(str(z)) <= 21 else str(z)[:20] + "." for z in r["x_etiket"]], rotation=30, ha="right", fontsize=6.0, fontfamily=DAR)
                ax.set_xlim(-0.6, len(r) - 0.4)
                ax.axhline(0, color=SOLUK, lw=0.6)
                ax.grid(axis="x", visible=False)
        else:
            xv = pd.to_numeric(r["x"]).values
            if v == "log_goreli_gelir":
                xv = np.exp(xv)
                ax.set_xscale("log")
                ax.xaxis.set_major_locator(FixedLocator([0.25, 0.5, 1, 2, 4]))
                ax.xaxis.set_major_formatter(FixedFormatter(["0.25", "0.5", "1", "2", "4"]))
                ax.xaxis.set_minor_formatter(NullFormatter())
                ax.axvline(0.6, color=MUREKKEP, lw=0.6, ls=(0, (3, 2)))
            ax.fill_between(xv, r["shap_q25"], r["shap_q75"], color=AURORA_CMAP(0.3), alpha=0.16, lw=0)
            ax.plot(xv, r["shap_ort"], color=AURORA_CMAP(0.3), lw=1.3, zorder=3)
            ax.axhline(0, color=SOLUK, lw=0.6)
        et = "Relative income" if v == "log_goreli_gelir" else kisa_ad(v, r["etiket"].iloc[0]) + (", m²" if v == "HH070" else "")
        ax.set_title(et, fontsize=6.6, loc="left", pad=3)
        ax.tick_params(labelsize=6.0)
        panel_etiketi(ax, "abcdefghijkl"[i], x=-0.08, y=1.005 if v == "HB031" else 1.02)
    fig.supylabel("SHAP value, log-odds (weighted mean and interquartile range)", fontsize=6.8, x=0.012)
    return kaydet(fig, "FigureS3", ek=True)


FIGURLER = {"1": figure1, "2": figure2, "3": figure3, "4": figure4, "5": figure5, "6": figure6, "S1": figureS_karar, "S2": figureS_kalibrasyon, "S3": figureS_shap}

if __name__ == "__main__":
    secim = sys.argv[1:] or list(FIGURLER)
    for k in secim:
        dosyalar = FIGURLER[k]()
        print("Figure", k, "->", ", ".join(p.name for p in dosyalar))
