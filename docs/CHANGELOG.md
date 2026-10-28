# Changelog

## v1.1.0 (2026-10-27)

All H1, H2 and H3 estimates of v1.0.0 are reproduced unchanged. Only the outputs of simulation S2 changed; everything else listed below is added.

### Changed

- Simulation S2 (misclassification of the single food insecurity item) was rebuilt so that the assigned true status is consistent with the observed data within cells of equivalized income quintile × poverty status (design A). The previous version clipped the assignment probabilities, which shifted the simulated exclusion error upwards; a diagnostic rerun of the previous method is kept in `S2_tani_eski.csv`.
- S2 now reports the closed-form exclusion error for every scenario and checks each scenario's compatibility with the observed prevalences, at the level of income-quintile × poverty cells and of LightGBM risk deciles.
- A second error structure (design B: the same sensitivity and specificity for every household, from a recalibrated out-of-time LightGBM probability) is evaluated alongside design A. No scenario of the original grid is compatible with design B, so near-error-free scenarios (Se 0.98–1.00 × Sp 0.999–1.000) were added for both designs.
- Supplementary Table S19 (S2 results by design) and the S2 row of Table S6 were rewritten. Figure 6b shows the closed-form and simulated exclusion error, with the incompatible region shaded.
- Table 3 and Figure 3a show the perfect-ranking ceiling.
- Supplementary Table S11 shows the intercepts of the lasso models; Supplementary Table S16 has a crude row at the start of each block; the composition note of Supplementary Table S3 moved to the new sample-comparison table.

### Added

- **Targeting ceiling and model comparisons (H2):**
  - targeting ceiling and achievable-gain shares (`H2_tavan.csv`, `H2_kazanc_payi.csv`);
  - paired model–model contrasts (`H2_model_model_farklar.csv`);
  - profile of the selected households (`H2_secilen_profil.csv`);
  - arithmetic floor of the H1 exclusion error (`H1_kapasite_tabani.csv`).
- **Supporting tables:**
  - missing-data summary (`eksik_veri_ozeti.csv`);
  - comparison of the development samples, the 2025 main test set and the excluded 2025 households (`orneklem_karsilastirma.csv`);
  - crude group counts, prevalences and differences for H3 (`H3_ham_oranlar.csv`);
  - IRLS convergence of the H3 bootstrap replicates (`H3_bootstrap_yakinsama.csv`).
- **Interval estimates:**
  - 95% intervals for the Brier score and the calibration intercept and slope of every model;
  - intervals for the multilayer perceptron from the same 8,000 bootstrap replicates (`H2_esiksiz_metrikler_GA.csv`, produced by `Codes/esiksiz_ga.py`).
- **Figure S2b:** calibration of the final models in the 2025 main test set.
- **Model files** (`Results/modeller/`):
  - intercepts, coefficients and preprocessing parameters of the ridge and lasso logistic models, with the input column list;
  - `Codes/tahmin_uygula.py`, which scores a household table with these files.

  Trained gradient-boosting models are not distributed because individual trees contain leaves based on fewer than five training households; they are re-created exactly by the code from the licensed microdata.
- **Search space:** definition of every search stage and grid (`H2_arama_uzayi_tanim.csv`).
- **Analysis plan:** the written analysis plan (`docs/analysis_plan_TR.md`).
