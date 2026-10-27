from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib import patheffects as pe
from matplotlib.colors import LinearSegmentedColormap

KOK = Path(__file__).resolve().parents[1]
VERI = KOK / "R_Data ve Python Data" / "figur_verileri"
SIM = KOK / "R_Data ve Python Data" / "simulasyon"
SONUC = KOK / "Results"
FIG = KOK / "Figures"
FIG_EK = FIG / "Supplementary"

CM = 1 / 2.54
TAM = 17.4 * CM
TEK = 8.5 * CM

MUREKKEP = "#1B1F2A"
IKINCIL = "#545A64"
SOLUK = "#8A9099"
IZGARA = "#E7E8EB"
ZEMIN = "#FFFFFF"
KAGIT = "#F5F2EC"

RENK_GRUP = {1: "#0E9384", 2: "#D47228", 3: "#8E3563"}
ETIKET_GRUP = {1: "Food secure", 2: "Food insecure, not poor", 3: "Food insecure, poor"}
ETIKET_GRUP_KISA = {1: "Food secure", 2: "FI, not poor", 3: "FI, poor"}
ZEMIN_GRUP = {1: "#D3EDEA", 2: "#F7E2D1", 3: "#EFD9E3"}
RENK_YOKSUL = "#5B606A"
GRI_YOKSUL = "#C4C8CE"
RENK_YONTEM = {
    "yoksul_60": MUREKKEP, "gelir_sirasi": SOLUK, "cart_T2": "#C08A1E", "cart_T1T2": "#C08A1E", "cart_T2idari": "#C08A1E", "l1_T2": "#C08A1E", "l1_T1T2": "#C08A1E",
    "lgb_A1": "#2F6DB0", "lgb_A2": "#4E9BD1", "lgb_A2i": "#7B6FC4", "lgb_A3": "#1F4F82", "logit_A1": "#6C7A89", "logit_lin_A1": "#6C7A89", "yoksul+lgb_B1": "#2F8F4E", "yoksul+cart_B_T2": "#2F8F4E",
}
ETIKET_YONTEM = {
    "yoksul_60": "Poverty line (60%)", "yoksul_50": "50% line", "yoksul_70": "70% line", "msy_etsiz_5": "MSD ≥5", "dusuk_is_yogunlugu": "Very low work intensity",
    "gelir_sirasi": "Income ranking", "cart_T2": "Rule set, structural", "cart_T1T2": "Rule set, income + structural", "cart_T2idari": "Rule set, register-like",
    "l1_T2": "Lasso ≤6, structural", "l1_T1T2": "Lasso ≤6, with income",
    "lgb_A1": "LightGBM, income + structural", "lgb_A2": "LightGBM, structural", "lgb_A2i": "LightGBM, register-like", "lgb_A3": "LightGBM, + financial strain",
    "logit_A1": "Ridge logistic", "yoksul+lgb_B1": "Poverty line + LightGBM top-up", "yoksul+cart_B_T2": "Poverty line + rule-set top-up",
}
RENK_GIDA = {"et_az": MUREKKEP, "meyve_az": MUREKKEP, "sebze_az": MUREKKEP, "saglik_yuk": MUREKKEP}
ETIKET_GIDA = {
    "et_az": "Meat, chicken or fish\nless than once a week",
    "meyve_az": "Fruit\nless than once a day",
    "sebze_az": "Vegetables or salad\nless than once a day",
    "saglik_yuk": "Medical or medicine costs\na heavy burden",
}
ETIKET_GIDA_KISA = {"et_az": "Meat, chicken, fish", "meyve_az": "Fruit", "sebze_az": "Vegetables", "saglik_yuk": "Health costs"}
ETIKET_BANT = {"1": "<0.6", "2": "0.6–0.8", "3": "0.8–1.0", "4": "1.0–1.5", "5": ">1.5"}
YIL_RENK = {2023: "#8D95A2", 2024: "#5F6B7A", 2025: "#1B1F2A"}
RENK_KURAL = "#C08A1E"
ZEMIN_KURAL = "#F3E6CC"
AURORA = ["#1D1A4D", "#35286F", "#5B358C", "#8A3F94", "#B94C86", "#DE6A6B", "#F0904F", "#F6B547"]
AURORA_CMAP = LinearSegmentedColormap.from_list("aurora", AURORA)
RENK_NEG = "#35286F"
RENK_POZ = "#E07A5A"
HALE = [pe.withStroke(linewidth=2.4, foreground="white")]
DAR = "Avenir Next Condensed"


def yazi_tipi():
    mevcut = {f.name for f in font_manager.fontManager.ttflist}
    for ad in ("Avenir Next", "Helvetica Neue", "Arial"):
        if ad in mevcut:
            return ad
    return "DejaVu Sans"


def stil_kur():
    ad = yazi_tipi()
    mpl.rcParams.update({
        "font.family": ad,
        "mathtext.fontset": "custom",
        "mathtext.rm": ad,
        "mathtext.sf": ad,
        "mathtext.cal": ad,
        "mathtext.it": f"{ad}:italic",
        "mathtext.bf": f"{ad}:bold",
        "font.size": 8,
        "axes.titlesize": 8.5,
        "axes.labelsize": 8,
        "xtick.labelsize": 7.5,
        "ytick.labelsize": 7.5,
        "legend.fontsize": 7.5,
        "axes.edgecolor": IKINCIL,
        "axes.labelcolor": MUREKKEP,
        "axes.linewidth": 0.6,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.grid": True,
        "axes.axisbelow": True,
        "grid.color": IZGARA,
        "grid.linewidth": 0.5,
        "xtick.color": IKINCIL,
        "ytick.color": IKINCIL,
        "xtick.major.width": 0.6,
        "ytick.major.width": 0.6,
        "xtick.major.size": 2.5,
        "ytick.major.size": 2.5,
        "text.color": MUREKKEP,
        "legend.frameon": False,
        "legend.handlelength": 1.4,
        "figure.facecolor": ZEMIN,
        "axes.facecolor": ZEMIN,
        "savefig.facecolor": ZEMIN,
        "pdf.fonttype": 42,
        "ps.fonttype": 42,
        "lines.solid_capstyle": "round",
    })


def panel_etiketi(ax, harf, x=-0.02, y=1.02):
    ax.text(x, y, f"({harf})", transform=ax.transAxes, fontsize=11, fontweight="bold", ha="right", va="bottom", color=MUREKKEP)


def panel_etiketi_fig(fig, harf, x, y):
    fig.text(x, y, f"({harf})", fontsize=11, fontweight="bold", ha="left", va="top", color=MUREKKEP)


def kaydet(fig, ad, ek=False):
    klasor = FIG_EK if ek else FIG
    klasor.mkdir(parents=True, exist_ok=True)
    fig.savefig(klasor / f"{ad}.png", dpi=600)
    fig.savefig(klasor / f"{ad}.pdf", dpi=600)
    fig.savefig(klasor / f"{ad}.tiff", dpi=600, pil_kwargs={"compression": "tiff_lzw"})
    plt.close(fig)
    return [klasor / f"{ad}.{u}" for u in ("png", "pdf", "tiff")]
