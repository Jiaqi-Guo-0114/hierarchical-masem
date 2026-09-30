---
name: hierarchical-masem
description: "Run two-stage meta-analytic structural equation modeling (MASEM/TSSEM) on complete Pearson correlation matrices from independent samples nested in studies, including categorical study-level moderators. Use for 层级元分析结构方程, correlated-matrix synthesis, or the Dang 2026 tutorial. Provides a checked R engine, likelihood-based intervals, direct multigroup contrasts, and reproducible sensitivity analysis. Incomplete matrices, overlapping/repeated samples, continuous moderation, and latent or cyclic SEM need a separate method."
---

# Hierarchical MASEM

Use this skill for executable analysis, not merely an explanation of the tutorial. Work from the research question, study coding and actual extraction data. Follow [method and evidence](references/method.md) for assumptions, interpretation and known corrections to Dang (2026).

## Choose the appropriate route

- Complete Pearson correlation matrices; independent participant samples nested within study clusters; observed-variable acyclic path model: use this engine.
- Missing correlations: explain what is missing and select a separately justified partial-matrix method. Do not silently drop matrices, impute correlations, or fill missing values with zero.
- Continuous moderators: a separately validated one-stage MASEM route is needed. Do not split a continuous variable into arbitrary categories.
- Repeated waves, alternative measures on the same participants, overlapping cohorts, or studies appearing in multiple moderator groups: this independent-sample/group workflow does not cover their extra sampling covariance.
- Ordinary univariate effect-size meta-analysis: use `psych-meta-workbench:psych-meta-workbench`. Its Fisher-z and approximate dependence defaults do **not** govern this raw-correlation MASEM engine.

## Input and execution

Resolve this skill's actual directory from the active plugin; do not hardcode a plugin-cache version. All commands below use `<skill>/scripts/masem.py`. Read [data and model contract](references/data-contract.md) before mapping a new dataset.

1. Inspect the protocol, construct definitions, correlation direction, sample/report crosswalk, required path contrasts, and categorical moderator. Confirm participant-level sample independence from study coding; IDs alone cannot establish it. Keep preregistered, other planned, and exploratory analyses distinct.
2. Initialize a new project: `python3 <skill>/scripts/masem.py init --project <dir>`. Fill the CSV/XLSX extraction table, `config.json` and observed-variable `model.json`. Preserve source files; use an explicit column mapping and record any documented coding correction.
3. Check the runtime: `python3 <skill>/scripts/masem.py check`. When environment preparation is within the authorized task, run `setup`. This is the only command allowed to fetch packages; `validate`, `run`, `verify` and `benchmark` are offline. Never change the old workbench's environment.
4. Run `validate --project <dir>`. Resolve invalid/missing correlations, duplicate samples or pairs, overlap, non-positive-definite matrices, incompatible sample sizes, and unsupported models. Do not automatically repair matrices or alter data to make fitting succeed.
5. Run `run --project <dir>`. The engine fits all four CS/HCS combinations with the same fixed effects and complete sampling covariance, selects the admissible minimum-AIC model, aligns Stage 2 inputs by pair identity, and estimates WLS paths with diagonal constraints and 95% likelihood-based intervals.
6. Run `verify --run <returned-run-directory>`. Inspect interval/optimizer status, boundary variances, subgroup study counts, sensitivity and study influence. A completed run with diagnostics is not proof that every estimate is reliable or that every requested interval succeeded.
7. Deliver the relevant tables, plots and report with source code and environment records. Use `psychology-methods-writer` for an actual manuscript Methods request, and the relevant section skill for further writing. Do not turn this statistical task into screening, Zotero synchronization, or submission administration.

For an openly redistributable synthetic demonstration, use `init --example --project <new-dir>`, then run and verify it. Its data are software tests, not research evidence. To exercise the author dataset, use `benchmark --project <new-dir> --tutorial-data <original-XLSX>`. The checksum must match the recorded supplement version; author data and code are not included in the public release. The engine corrects documented computational errors and is not a promise of verbatim numerical identity with the paper.

## Inference and reporting

- Report study count, independent-sample count and participant N separately. Sum N by sample identity, never by unique numeric N and never across correlation rows.
- Preserve the same full sampling covariance in working-correlation sensitivity analyses, and inspect Stage 2 effects as well as pooled correlations.
- Use explicit direct contrasts for group/path differences. Do not infer a difference from one significant and one nonsignificant coefficient.
- The overall multigroup comparison is available whenever supported groups are specified. Path/pairwise follow-ups require named tests and `planned` or `exploratory` role. Holm correction applies to all requested tests in each declared family; pairwise confidence intervals are pointwise, not simultaneous intervals.
- Nonsignificance is not equivalence. A saturated SEM has no informative overall model-fit test. Correlational path arrows do not identify causal effects, and study-level moderation does not establish individual-level effects.
- Intervals and tests are conditional on the selected Stage 1 working model. This integrated hierarchy/selection/multigroup workflow has not been comprehensively simulation-validated, particularly with few studies. Do not claim universal bias, coverage, Type I error or power guarantees.
- If native interval search fails, the engine fixes the target parameter or contrast and profiles the same WLS objective. Each recovered endpoint requires a converged admissible fit, unit implied variances and an independently checked chi-square objective cutoff; see `profile_audit.csv`. A failed fallback remains an explicit failure.

Read [verification and outputs](references/verification.md) for numerical checks and failure handling. Keep technical correction records outside publishable prose. Do not label the capability verified until the saved acceptance tests pass.
