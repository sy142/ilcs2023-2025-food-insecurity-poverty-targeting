# Revision 1: analyses by education

This addendum accompanies release v1.2.0 of the analysis code for the Income and Living Conditions Survey (TurkStat, 2023–2025 cross-sections). It adds analyses by education, requested during peer review after the main results were known.

## What was added

- **Meal-affordability deprivation and the exclusion error by the highest education among adults.** The prevalence of meal-affordability deprivation, the exclusion error of the 60% relative poverty line and the composition of the missed households are given by the highest education among the household's adults (five levels). Estimates are given for 2023, 2024 and 2025, at household level (HB040) and person level (FK050, households as clusters). Within each equivalized income quintile, the prevalence is also given by education. Uncertainty comes from Taylor linearization.
- **Comparison C1 by the adult's education.** C1 compares meal-deprived with non-deprived adults among the non-poor in 2025. The fully interacted main model of C1 is unchanged; within each of three education groups (primary or less, secondary, tertiary), predictions are standardized to the covariates of that group's non-poor adults. Intervals come from 4,000 rescaled household bootstrap replicates, using the multiplier matrix of the main estimates. A design-based Wald test assesses the group-by-education interaction.

No estimate of earlier versions changed.

## How to run

```
Rscript Codes/rev1_egitim.R
```

Run the script from the project root. It requires the licensed TurkStat microdata and the outputs of the v1.2.0 pipeline (`Codes/analiz.R`), which are not distributed. Functions are copied unchanged from `analiz.R`. Outputs are written to `Results/Rev1/`. Bootstrap replicates are cached locally; the cache contains household-level multipliers and is not distributed.

## Checks

All three checks passed (`Results/Rev1/kontrol_rev1.csv`):

1. **Input data: 5 of 5 checks.** The checks cover the number of person records, the 2025 households and the adult sample.
2. **Exclusion-error breakdown: 48 of 48 checks.** Category counts add up to the totals. Overall estimates match the v1.2.0 estimates within 1e-6.
3. **Comparison C1: 57 of 57 checks.** The main model specification is unchanged. Overall estimates and bootstrap limits match the v1.2.0 estimates within 1e-4 and 0.01 percentage points.

## Contents

- `Codes/rev1_egitim.R`: the analysis script.
- `Results/Rev1/R1_egitim_H1_kirilim.csv`: the exclusion-error breakdown by education.
- `Results/Rev1/R1_egitim_H1_gelir_dilimi.csv`: the prevalence by income quintile and education.
- `Results/Rev1/R1_egitim_C1.csv` and `R1_egitim_C1_etkilesim.csv`: comparison C1 by education, with the interaction tests and group sizes.
- `Results/Rev1/S11_egitim_blogu_2025.csv` and `S22_egitim_blogu_C1.csv`: the rows added to Supplementary Tables S11 and S22.
- `Results/Rev1/Supplementary/`: two tables by education (CSV and DOCX).
- `Results/Rev1/sayilar_rev1.json`: all reported numbers.
- `Results/Rev1/kontrol_rev1.csv`: the results of the three checks.
- `Results/Rev1/sessionInfo_rev1.txt` and `Results/Rev1/log/`: the computing environment and run logs.

Cells based on fewer than 20 meal-deprived households are suppressed, and cells with 20–50 are flagged. Households without an adult with an individual questionnaire are not shown; there was one such household, in 2025. No file contains household- or person-level records.
