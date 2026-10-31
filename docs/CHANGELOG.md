# Changelog

## v1.2.0 (2026-10-31)

Analyses added after an external assessment round. No model was retrained: every new H2 evaluation uses the stored scores of v1.1.0. All estimates of v1.1.0 are reproduced unchanged, except the intervals of the year-difference column of Table 2, which now count households matched across survey years as one cluster.

### Changed

- **Terminology:** the outcome is labeled "meal-affordability deprivation" (households: "meal-deprived") in every table, figure and note; the outcome definition includes the vegetarian equivalent; consumption items are labeled as frequencies (no quantities, intake or diet quality were measured); "Türkiye" in table titles. Variable names in the code are unchanged.
- **Table 2:** year differences and the year tests use households matched in any pair of survey years as clusters; the income-curve block reports the overall association (4 df), departure from linearity (3 df), the three step estimates, and the equality of the 2023 and 2025 curves (5 df) and of their shape (4 df).
- **Figure 2b:** a strip with the 2025 − 2023 difference between the curves and its 95% band; the linearity note names the test.
- **Supplementary Table S1:** codebook wording (Turkish, with English translation), recall period, coding and missing values of the outcome and of the consumption-frequency and health-cost items.
- **Labels of the upper-bound model:** "upper bound: + other deprivation items (same battery as the outcome)".

### Added

- **Income curve (H1):** overall-association tests; year tests with matched households as clusters, for 2023–2025, 2023–2024, 2024–2025 and all three years (`H1_gelir_egrisi_testleri.csv`); predicted probabilities and year differences at ten relative incomes under four variance assumptions (`H1_egri_tahminleri.csv`; `fig2b_yil_farki.csv`); knot sensitivity with 3–7 knots and design-based AIC (`H1_dugum_duyarliligi.csv`); year differences of every Table 2 row with matched households as clusters (`H1_yil_farklari.csv`) and of the Erreygers index (`H1_erreygers_farklar.csv`); distribution of the matched-household clusters (`H1_bagli_kume_dagilimi.csv`); real value of the 60% line (`H1_esik_reel_deger.csv`).
- **Income reference year (H1):** households classified by change in main activity between the income reference year and the interview (`H1_gelir_yili_uyumsuzlugu.csv`).
- **Internal consistency of the item (H1):** prevalence by ability to make ends meet and by the number of other deprivation items (`H1_madde_gradyan.csv`).
- **Test-set weights (H2):** main-test-set weights raked to the 2025 household population, with raking repeated in every bootstrap replicate (`H2_kalibrasyon_denge.csv`, `H2_kalibre_test.csv`); the main test set without TR63 (`H2_tr63_haric.csv`); national counterpart of the absolute gains (`H2_ulusal_karsilik.csv`); bootstrap standard deviations of the paired differences (`H2_fark_bootstrap_sd.csv`).
- **Design effect:** the design effect at which each principal 95% interval would include zero, and intervals under design effects of 2 and 3 (`tasarim_etkisi_devrilme.csv`; Supplementary Table S26).
- **New supplementary blocks and tables:** Table S4 (calibrated column), Table S11 (change in main activity, ability to make ends meet, other deprivation items), Table S12 (matched-cluster differences, tests, curve estimates, knot sensitivity, real value of the line), Table S14 (national counterpart, `Ek_ulusal_karsilik`), Table S20 (calibrated and TR63-excluded test sets), Table S26 (`Ek_tasarim_etkisi`); the software table becomes Table S27. Mapping of Supplementary numbers to files: `docs/supplementary_table_map.md`.

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
