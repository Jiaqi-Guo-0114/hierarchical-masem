# Data and model contract

## Project inputs

The CLI accepts `config.json`, a mapped CSV/XLSX long table, and `model.json`. A new project starts with an empty extraction table; supplied tutorial data are activated only through `init --tutorial` or `benchmark`.

Required semantic columns are `study_id`, `sample_id`, `var1`, `var2`, `r`, `n`. Map existing headers in `config.columns`. Optional mapped columns are `effect_id` and `overlap_group`.

- `study_id` identifies the actual shared study/dependence cluster; multiple reports of one study share it. Record source/report provenance in the original extraction ledger.
- `sample_id` identifies distinct participant sets within that cluster. The unique key is the study/sample combination. Repeated measurements or alternative operationalizations on the same participants do not create independent samples.
- `overlap_group`, when provided, identifies known shared participants. Two samples with the same nonempty overlap group are rejected. Different IDs do not prove independence: set `sample_independence` to `confirmed_independent` only after substantive coding checks.
- Each sample supplies each unordered variable pair exactly once, with no diagonal entries. Reversed duplicates are errors. The number of rows per matrix is p(p−1)/2.
- All rows of one sample have one actual sample N, an integer at least five. Different samples may have identical N; they remain distinct. Pairwise deletion with varying denominators needs reconciliation before this release can analyze it.
- `r` is an untransformed Pearson correlation strictly between −1 and 1. Missing values, rank correlations and unverified scale harmonization are not silently converted.
- Every sample matrix, sampling covariance, pooled matrix and pooled fixed-effect covariance must be positive definite. No nearPD replacement is performed.

The `variables` array controls scientific ordering. Internal correlation keys use positions, not concatenated variable names, so renaming constructs or shuffling rows does not change meaning. `rcalc()`'s returned data and covariance are explicitly aligned, and Stage 2 uses columnwise lower-triangle order in both inputs.

## Model JSON

`model.json` has `variables`, `A`, `S`. A/S are square row arrays in the same variable order. A cell is either a number or a string such as `"0.1*b_x"` (start and parameter label). A rows are outcomes, columns are predictors. S must be symmetric. Fixed variances are one; endogenous residual variances are free, with nonnegative bounds and model-implied diagonal constraints.

Use distinct ASCII parameter labels in A and S. Directed paths need unique labels. Arbitrary observed-variable recursive path models are allowed when their local Jacobian is identified. Latent-variable models, feedback loops and automatic indirect-effect claims are outside the tested interface. A user request for mediation requires specifying the indirect estimand and an additional validated contrast/interval implementation; paths alone do not deliver an indirect-effect test.

The engine derives sensible regression/residual starting values from the pooled matrix, without changing the data or objective. It checks the fitted implied diagonal, residual variances and local identification before reporting results.

## Moderation and sensitivity

Set `moderator` to `{"column":"instrument","type":"categorical"}`. Groups must be disjoint at the study level and have at least two independent studies each. This is an identifiability floor, not an assurance of adequate power.

`moderation.mode` is `none` (omnibus only), `planned`, or `exploratory`. `path_tests` names paths tested equal across all groups; `pairwise_paths` names paths tested across every group pair. Holm families are all requested path tests and all requested path-by-pair tests, respectively. Do not select the correction family after inspecting raw p values. A planned flag does not assert preregistration; that requires a supplied protocol/registration record.

`sensitivity.settings` contains requested [rho,phi] pairs, defaulting to [[0,0],[0.5,0.5],[1,1]]. `leave_one_study_out` defaults to true in the templates. The same sampling V is retained throughout the working-correlation grid. With one row per ES identifier, rho has no effective within-identifier covariance to alter; report this explicitly. Phi is the study-level working correlation. Leave-one-study-out omits whole study clusters and holds the selected heterogeneity structure fixed.

No numerical model failures are silently converted into successful estimates. Failed intervals remain failed; failed candidate models are excluded from AIC selection with an explicit record.
