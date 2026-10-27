# Food insecurity, income poverty and targeting rules in Türkiye (ILCS 2023–2025)

Analysis code and aggregated outputs for a study of household food insecurity and
relative income poverty in Türkiye, using the 2023–2025 cross-sections of the
Income and Living Conditions Survey (ILCS/EU-SILC, Turkish Statistical Institute).
The analysis estimates the exclusion error of the 60% relative poverty line,
compares targeting rules (decision trees, penalized regression, gradient boosting)
trained on 2023–2024 and evaluated on 2025, and standardizes dietary frequencies
by g-computation. A manuscript describing the analysis is under review; citation
information will be added here.

## Data

The ILCS microdata were obtained from the Turkish Statistical Institute (TurkStat)
under its microdata user agreement and cannot be redistributed (Statistical Law
No. 5429). Researchers may apply for access through TurkStat's official microdata
procedures (https://data.tuik.gov.tr). **This repository contains no microdata**:
`Results/` and `Figures/` hold aggregated outputs only.

## Repository structure

- `Codes/` — the full pipeline: `analiz.R` (data preparation, validation checks,
  H1 and H3 estimation; single entry point), `kesif.R` (descriptive screening),
  `ml.py` / `mlp.py` (targeting models), `simulasyon.py` (plasmode simulations),
  `figurler.py` + `figur_stili.py` + `etiketler.json` (figures),
  `xlsx_simge.py`, `sayilar_karsilastir.py` (reproduction check).
- `Results/` — aggregated outputs: tables (CSV and DOCX), machine-readable
  results (`sayilar.json`), model summaries, the written analysis protocol
  (`model_protokolu.csv`), validation checks, session and environment records.
- `Figures/` — main and supplementary figures (PDF, 450 dpi).
- `docs/README_kodlar.md` — detailed run guide (in Turkish): execution order,
  caches, timings and seeds.

## How to run

With the TurkStat microdata in place under `R_Data ve Python Data/` (not part of
this repository): `Rscript Codes/analiz.R` runs the entire pipeline and calls the
Python scripts; `python Codes/figurler.py` then draws all figures. A clean run
reproduces all archived results exactly, including bit-identical figures
(115 automated validation checks against published TurkStat and Eurostat series).
All random seeds are fixed in the scripts.

## Environment

R 4.6.1 (survey, data.table, arrow, future/furrr, jsonlite) and Python 3.13
(numpy, pandas, pyarrow, scikit-learn 1.9.1, LightGBM 4.7.0, SHAP 0.54.1,
PyTorch 2.14.1, SciPy, Matplotlib, joblib). Exact versions: `Results/sessionInfo.txt`
and `Results/python_ortam.txt`.

## License

MIT (code). The aggregated outputs may be reused with attribution.
