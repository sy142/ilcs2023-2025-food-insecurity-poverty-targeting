# Food insecurity, income poverty and targeting rules in Türkiye (ILCS 2023–2025)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23685840.svg)](https://doi.org/10.5281/zenodo.23685840)

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
`Results/` and `Figures/` hold aggregated outputs and, in `Results/modeller/`, the
trained ridge and lasso logistic models with their preprocessing parameters.
Trained gradient-boosting models are not distributed because individual trees
contain leaves based on fewer than five training households; the code re-creates
them from the licensed microdata.

## Repository structure

- `Codes/` — the full pipeline: `analiz.R` (data preparation, validation checks,
  H1 and H3 estimation; single entry point), `kesif.R` (descriptive screening),
  `ml.py` / `mlp.py` / `esiksiz_ga.py` (targeting models and threshold-free
  metrics), `simulasyon.py` / `s3_aralik.py` (plasmode simulations),
  `figurler.py` + `figur_stili.py` + `etiketler.json` (figures),
  `tahmin_uygula.py` (scores a household table with the archived logistic models),
  `gizlilik_taramasi.py` (disclosure check of the outputs), `xlsx_simge.py`,
  `sayilar_karsilastir.py` (reproduction check).
- `Results/` — aggregated outputs: tables (CSV and DOCX; supplementary tables in
  `Results/Supplementary/`), machine-readable results (`sayilar.json`), model
  summaries, the written analysis protocol (`model_protokolu.csv`), validation
  checks, session and environment records.
- `Results/modeller/` — trained ridge and lasso logistic models (JSON and
  coefficient tables), preprocessing parameters (`on_isleme.json`), input columns
  and the scoring audit.
- `Figures/` — main and supplementary figures (PDF).
- `docs/` — `README_kodlar.md`, detailed run guide (in Turkish): execution order,
  caches, timings and seeds; `analysis_plan_TR.md`, the written analysis plan (in
  Turkish); `CHANGELOG.md`, changes between archived versions.

## How to run

With the TurkStat microdata in place under `R_Data ve Python Data/` (not part of
this repository): `Rscript Codes/analiz.R` runs the entire pipeline and calls the
Python scripts; `python Codes/figurler.py` then draws all figures. A clean run
reproduces all archived results exactly, including bit-identical figures
(115 automated validation checks against published TurkStat and Eurostat series).
All random seeds are fixed in the scripts. `python Codes/tahmin_uygula.py` applies
the archived logistic models to a household table with the same input columns.

## Environment

R 4.6.1 (survey, data.table, arrow, future/furrr, jsonlite) and Python 3.13
(numpy, pandas, pyarrow, scikit-learn 1.9.1, LightGBM 4.7.0, SHAP 0.54.1,
PyTorch 2.14.1, SciPy, Matplotlib, joblib). Exact versions: `Results/sessionInfo.txt`
and `Results/python_ortam.txt`.

## License

MIT (code). The aggregated outputs may be reused with attribution.
